import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/stun/attributes.dart';
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';

import 'channel_data.dart';

/// TURN transport protocol
enum TurnTransport {
  udp(17),
  tcp(6);

  final int value;
  const TurnTransport(this.value);

  /// Get as REQUESTED-TRANSPORT value (protocol in upper 8 bits)
  int get requestedTransport => value << 24;
}

/// TURN client state
enum TurnState {
  idle,
  connecting,
  connected,
  failed,
  closed,
}

/// TURN allocation
class TurnAllocation {
  /// Relayed address (server-allocated relay address)
  final Address relayedAddress;

  /// Mapped address (server-reflexive address)
  final Address? mappedAddress;

  /// Allocation lifetime in seconds
  final int lifetime;

  /// Creation time
  final DateTime createdAt;

  TurnAllocation({
    required this.relayedAddress,
    this.mappedAddress,
    required this.lifetime,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Check if allocation is expired
  bool get isExpired {
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    return elapsed >= lifetime;
  }

  /// Get remaining lifetime in seconds
  int get remainingLifetime {
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    return (lifetime - elapsed).clamp(0, lifetime);
  }
}

/// TURN client
/// Implements TURN protocol (RFC 5766) for relay-based NAT traversal
class TurnClient {
  /// TURN server address
  final Address serverAddress;

  /// Username for long-term credentials
  final String username;

  /// Password for long-term credentials
  final String password;

  /// Transport protocol
  final TurnTransport transport;

  /// Default allocation lifetime (seconds)
  final int lifetime;

  /// UDP socket (if using UDP transport)
  RawDatagramSocket? _udpSocket;

  /// TCP socket (if using TCP transport)
  Socket? _tcpSocket;

  /// Current state
  TurnState _state = TurnState.idle;
  TurnState get state => _state;

  /// Current allocation
  TurnAllocation? _allocation;
  TurnAllocation? get allocation => _allocation;

  /// Authentication realm
  String? _realm;

  /// Authentication nonce
  Uint8List? _nonce;

  /// Integrity key (MD5 hash of username:realm:password)
  Uint8List? _integrityKey;

  /// Active transactions (transaction ID -> completer)
  final Map<String, Completer<StunMessage>> _transactions = {};

  /// Channel number mappings (peer address -> channel number)
  final Map<String, int> _channelByAddress = {};

  /// Channel number reverse mappings (channel number -> peer address)
  final Map<int, Address> _addressByChannel = {};

  /// Next available channel number
  int _nextChannelNumber = channelNumberMin;

  /// Permissions (peer IP -> expiry time)
  final Map<String, DateTime> _permissions = {};

  /// Refresh timer
  Timer? _refreshTimer;

  /// Permission refresh timer
  Timer? _permissionTimer;

  /// Receive stream controller
  final StreamController<(Address, Uint8List)> _receiveController =
      StreamController.broadcast();

  /// Receive stream (peer address, data)
  Stream<(Address, Uint8List)> get onReceive => _receiveController.stream;

  TurnClient({
    required this.serverAddress,
    required this.username,
    required this.password,
    this.transport = TurnTransport.udp,
    this.lifetime = 600, // 10 minutes default
  });

  /// Connect to TURN server and create allocation
  Future<void> connect() async {
    if (_state != TurnState.idle && _state != TurnState.failed) {
      throw StateError('Already connected or connecting');
    }

    _state = TurnState.connecting;

    try {
      // Create transport
      if (transport == TurnTransport.udp) {
        _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        _udpSocket!.listen(_handleUdpData);
      } else {
        final (host, port) = serverAddress;
        _tcpSocket = await Socket.connect(host, port);
        _tcpSocket!.listen(_handleTcpData);
      }

      // Perform allocation
      await _allocate();

      _state = TurnState.connected;

      // Start refresh timer (refresh at 5/6 of lifetime)
      final refreshInterval = (_allocation!.lifetime * 5 ~/ 6);
      _refreshTimer = Timer.periodic(
        Duration(seconds: refreshInterval),
        (_) => _refresh(),
      );

      // Start permission refresh timer (refresh every 4 minutes, expire at 5)
      _permissionTimer = Timer.periodic(
        Duration(minutes: 4),
        (_) => _refreshPermissions(),
      );

    } catch (e) {
      _state = TurnState.failed;
      rethrow;
    }
  }

  /// Perform ALLOCATE request
  Future<void> _allocate() async {
    // First attempt without credentials (will get 401)
    var request = StunMessage(
      method: StunMethod.allocate,
      messageClass: StunClass.request,
    );
    request.setAttribute(StunAttributeType.requestedTransport, transport.requestedTransport);
    request.setAttribute(StunAttributeType.lifetime, lifetime);

    var response = await _sendRequest(request);

    // Handle 401 Unauthorized - need credentials
    if (response.messageClass == StunClass.errorResponse) {
      final errorCode = response.getAttribute(StunAttributeType.errorCode);
      if (errorCode != null && errorCode is (int, String)) {
        final (code, reason) = errorCode;
        if (code == 401) {
          // Extract realm and nonce
          _realm = response.getAttribute(StunAttributeType.realm) as String?;
          _nonce = response.getAttribute(StunAttributeType.nonce) as Uint8List?;

          if (_realm == null || _nonce == null) {
            throw Exception('401 response missing realm or nonce');
          }

          // Compute integrity key: MD5(username:realm:password)
          final keyInput = '$username:$_realm:$password';
          _integrityKey = md5Hash(Uint8List.fromList(keyInput.codeUnits));

          // Retry with credentials
          request = StunMessage(
            method: StunMethod.allocate,
            messageClass: StunClass.request,
          );
          request.setAttribute(StunAttributeType.requestedTransport, transport.requestedTransport);
          request.setAttribute(StunAttributeType.lifetime, lifetime);
          request.setAttribute(StunAttributeType.username, username);
          request.setAttribute(StunAttributeType.realm, _realm);
          request.setAttribute(StunAttributeType.nonce, _nonce);
          request.addMessageIntegrity(_integrityKey!);
          request.addFingerprint();

          response = await _sendRequest(request);
        }
      }
    }

    // Check for success
    if (response.messageClass != StunClass.successResponse) {
      final errorCode = response.getAttribute(StunAttributeType.errorCode);
      if (errorCode != null && errorCode is (int, String)) {
        final (code, reason) = errorCode;
        throw Exception('ALLOCATE failed: $code $reason');
      }
      throw Exception('ALLOCATE failed with unknown error');
    }

    // Extract allocation info
    final relayedAddress = response.getAttribute(StunAttributeType.xorRelayedAddress) as Address?;
    final mappedAddress = response.getAttribute(StunAttributeType.xorMappedAddress) as Address?;
    final allocLifetime = response.getAttribute(StunAttributeType.lifetime) as int?;

    if (relayedAddress == null || allocLifetime == null) {
      throw Exception('ALLOCATE response missing XOR-RELAYED-ADDRESS or LIFETIME');
    }

    _allocation = TurnAllocation(
      relayedAddress: relayedAddress,
      mappedAddress: mappedAddress,
      lifetime: allocLifetime,
    );
  }

  /// Refresh allocation
  Future<void> _refresh() async {
    if (_allocation == null) return;

    final request = StunMessage(
      method: StunMethod.refresh,
      messageClass: StunClass.request,
    );
    request.setAttribute(StunAttributeType.lifetime, lifetime);
    _addAuthentication(request);

    final response = await _sendRequest(request);

    if (response.messageClass == StunClass.successResponse) {
      final newLifetime = response.getAttribute(StunAttributeType.lifetime) as int?;
      if (newLifetime != null) {
        _allocation = TurnAllocation(
          relayedAddress: _allocation!.relayedAddress,
          mappedAddress: _allocation!.mappedAddress,
          lifetime: newLifetime,
        );
      }
    }
  }

  /// Create permission for peer address
  Future<void> createPermission(Address peerAddress) async {
    final (peerHost, _) = peerAddress;

    // Check if permission already exists and is valid
    final expiry = _permissions[peerHost];
    if (expiry != null && DateTime.now().isBefore(expiry)) {
      return; // Permission still valid
    }

    final request = StunMessage(
      method: StunMethod.createPermission,
      messageClass: StunClass.request,
    );
    request.setAttribute(StunAttributeType.xorPeerAddress, peerAddress);
    _addAuthentication(request);

    final response = await _sendRequest(request);

    if (response.messageClass == StunClass.successResponse) {
      // Permission valid for 5 minutes
      _permissions[peerHost] = DateTime.now().add(Duration(minutes: 5));
    }
  }

  /// Refresh all permissions
  Future<void> _refreshPermissions() async {
    final peerHosts = _permissions.keys.toList();
    for (final peerHost in peerHosts) {
      // Reconstruct address (use port 0 as placeholder, only IP matters for permissions)
      await createPermission((peerHost, 0));
    }
  }

  /// Bind channel to peer address
  Future<int> bindChannel(Address peerAddress) async {
    final addrKey = '${peerAddress.$1}:${peerAddress.$2}';

    // Check if already bound
    final existing = _channelByAddress[addrKey];
    if (existing != null) {
      return existing;
    }

    // Allocate channel number
    final channelNumber = _nextChannelNumber++;
    if (channelNumber > channelNumberMax) {
      throw Exception('No more channel numbers available');
    }

    // Ensure permission exists
    await createPermission(peerAddress);

    // Send ChannelBind request
    final request = StunMessage(
      method: StunMethod.channelBind,
      messageClass: StunClass.request,
    );
    request.setAttribute(StunAttributeType.channelNumber, channelNumber);
    request.setAttribute(StunAttributeType.xorPeerAddress, peerAddress);
    _addAuthentication(request);

    final response = await _sendRequest(request);

    if (response.messageClass != StunClass.successResponse) {
      throw Exception('ChannelBind failed');
    }

    // Store mapping
    _channelByAddress[addrKey] = channelNumber;
    _addressByChannel[channelNumber] = peerAddress;

    return channelNumber;
  }

  /// Send data to peer (uses Send indication)
  Future<void> sendData(Address peerAddress, Uint8List data) async {
    // Ensure permission exists
    await createPermission(peerAddress);

    final indication = StunMessage(
      method: StunMethod.send,
      messageClass: StunClass.indication,
    );
    indication.setAttribute(StunAttributeType.xorPeerAddress, peerAddress);
    indication.setAttribute(StunAttributeType.data, data);

    await _sendIndication(indication);
  }

  /// Send data via channel (more efficient than Send indication)
  Future<void> sendChannelData(int channelNumber, Uint8List data) async {
    final channelData = ChannelData(
      channelNumber: channelNumber,
      data: data,
    );

    final encoded = channelData.encode();

    if (transport == TurnTransport.udp) {
      final (host, port) = serverAddress;
      _udpSocket!.send(encoded, InternetAddress(host), port);
    } else {
      _tcpSocket!.add(encoded);
    }
  }

  /// Add authentication attributes to request
  void _addAuthentication(StunMessage message) {
    if (_realm != null && _nonce != null && _integrityKey != null) {
      message.setAttribute(StunAttributeType.username, username);
      message.setAttribute(StunAttributeType.realm, _realm);
      message.setAttribute(StunAttributeType.nonce, _nonce);
      message.addMessageIntegrity(_integrityKey!);
      message.addFingerprint();
    }
  }

  /// Send STUN request and wait for response
  Future<StunMessage> _sendRequest(StunMessage request) async {
    final completer = Completer<StunMessage>();
    final txId = request.transactionIdHex;
    _transactions[txId] = completer;

    final data = request.toBytes();

    if (transport == TurnTransport.udp) {
      final (host, port) = serverAddress;
      _udpSocket!.send(data, InternetAddress(host), port);
    } else {
      _tcpSocket!.add(data);
    }

    // Timeout after 3 seconds
    Timer(Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        _transactions.remove(txId);
        completer.completeError(TimeoutException('STUN request timeout'));
      }
    });

    return completer.future;
  }

  /// Send STUN indication (no response expected)
  Future<void> _sendIndication(StunMessage indication) async {
    final data = indication.toBytes();

    if (transport == TurnTransport.udp) {
      final (host, port) = serverAddress;
      _udpSocket!.send(data, InternetAddress(host), port);
    } else {
      _tcpSocket!.add(data);
    }
  }

  /// Handle UDP data
  void _handleUdpData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _udpSocket!.receive();
      if (datagram != null) {
        _handleIncomingData(datagram.data);
      }
    }
  }

  /// Handle TCP data
  void _handleTcpData(Uint8List data) {
    _handleIncomingData(data);
  }

  /// Handle incoming data
  void _handleIncomingData(Uint8List data) {
    // Check if ChannelData
    if (ChannelData.isChannelData(data)) {
      final channelData = ChannelData.decode(data);
      final peerAddress = _addressByChannel[channelData.channelNumber];
      if (peerAddress != null) {
        _receiveController.add((peerAddress, channelData.data));
      }
      return;
    }

    // Parse as STUN message
    final message = parseStunMessage(data, integrityKey: _integrityKey);
    if (message == null) return;

    // Handle Data indication
    if (message.method == StunMethod.data &&
        message.messageClass == StunClass.indication) {
      final peerAddress = message.getAttribute(StunAttributeType.xorPeerAddress) as Address?;
      final msgData = message.getAttribute(StunAttributeType.data) as Uint8List?;
      if (peerAddress != null && msgData != null) {
        _receiveController.add((peerAddress, msgData));
      }
      return;
    }

    // Handle response to transaction
    if (message.messageClass == StunClass.successResponse ||
        message.messageClass == StunClass.errorResponse) {
      final txId = message.transactionIdHex;
      final completer = _transactions.remove(txId);
      completer?.complete(message);
    }
  }

  /// Close TURN client
  Future<void> close() async {
    _state = TurnState.closed;

    // Cancel timers
    _refreshTimer?.cancel();
    _permissionTimer?.cancel();

    // Send REFRESH with lifetime=0 to deallocate
    if (_allocation != null && _integrityKey != null) {
      try {
        final request = StunMessage(
          method: StunMethod.refresh,
          messageClass: StunClass.request,
        );
        request.setAttribute(StunAttributeType.lifetime, 0);
        _addAuthentication(request);
        await _sendRequest(request);
      } catch (e) {
        // Ignore errors during close
      }
    }

    // Close sockets
    _udpSocket?.close();
    _tcpSocket?.close();

    // Clear state
    _allocation = null;
    _transactions.clear();
    _channelByAddress.clear();
    _addressByChannel.clear();
    _permissions.clear();

    await _receiveController.close();
  }
}
