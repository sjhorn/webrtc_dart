import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/utils.dart';
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';
import 'package:webrtc_dart/src/stun/protocol.dart';
import 'package:webrtc_dart/src/turn/turn_client.dart';

/// ICE connection state
/// See RFC 5245
enum IceState {
  /// Initial state
  newState,

  /// Gathering candidates
  gathering,

  /// Performing connectivity checks
  checking,

  /// At least one pair is working
  connected,

  /// All checks are complete, one pair nominated
  completed,

  /// No working pairs found
  failed,

  /// Connection has been closed
  closed,

  /// Connection lost
  disconnected;
}

/// ICE role
enum IceRole {
  controlling,
  controlled;
}

/// Generate random string for ICE credentials
String randomString(int length) {
  final bytes = randomBytes(length);
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, length);
}

/// ICE connection options
class IceOptions {
  /// STUN server address
  final (String, int)? stunServer;

  /// TURN server address
  final (String, int)? turnServer;

  /// TURN username
  final String? turnUsername;

  /// TURN password
  final String? turnPassword;

  /// Use IPv4 addresses
  final bool useIpv4;

  /// Use IPv6 addresses
  final bool useIpv6;

  /// Port range for local candidates
  final (int, int)? portRange;

  const IceOptions({
    this.stunServer,
    this.turnServer,
    this.turnUsername,
    this.turnPassword,
    this.useIpv4 = true,
    this.useIpv6 = true,
    this.portRange,
  });
}

/// ICE connection interface
abstract class IceConnection {
  /// Whether this agent is controlling
  bool get iceControlling;
  set iceControlling(bool value);

  /// Local ICE username fragment
  String get localUsername;

  /// Local ICE password
  String get localPassword;

  /// Remote ICE username fragment
  String get remoteUsername;

  /// Remote ICE password
  String get remotePassword;

  /// Whether remote peer is ICE-lite
  bool get remoteIsLite;

  /// Current state
  IceState get state;

  /// Local candidates
  List<Candidate> get localCandidates;

  /// Remote candidates
  List<Candidate> get remoteCandidates;

  /// Candidate pairs (check list)
  List<CandidatePair> get checkList;

  /// Nominated pair (selected for data transmission)
  CandidatePair? get nominated;

  /// Generation (for ICE restarts)
  int get generation;

  /// Whether local candidate gathering is complete
  bool get localCandidatesEnd;

  /// Whether all remote candidates have been received
  bool get remoteCandidatesEnd;

  /// Stream of state changes
  Stream<IceState> get onStateChanged;

  /// Stream of discovered local candidates
  Stream<Candidate> get onIceCandidate;

  /// Stream of incoming data
  Stream<Uint8List> get onData;

  /// Set remote ICE parameters
  void setRemoteParams({
    required bool iceLite,
    required String usernameFragment,
    required String password,
  });

  /// Gather local candidates
  Future<void> gatherCandidates();

  /// Start connectivity checks
  Future<void> connect();

  /// Add a remote candidate
  Future<void> addRemoteCandidate(Candidate? candidate);

  /// Send data over the nominated pair
  Future<void> send(Uint8List data);

  /// Close the connection
  Future<void> close();

  /// Restart ICE (generate new credentials)
  Future<void> restart();

  /// Get the default candidate (for SDP)
  Candidate? getDefaultCandidate();
}

/// Basic ICE connection implementation
class IceConnectionImpl implements IceConnection {
  bool _iceControlling;
  String _localUsername;
  String _localPassword;
  String _remoteUsername = '';
  String _remotePassword = '';
  bool _remoteIsLite = false;
  IceState _state = IceState.newState;
  int _generation = 0;

  final List<Candidate> _localCandidates = [];
  final List<Candidate> _remoteCandidates = [];
  final List<CandidatePair> _checkList = [];
  CandidatePair? _nominated;

  bool _localCandidatesEnd = false;
  bool _remoteCandidatesEnd = false;

  // Map of candidate foundation to socket
  final Map<String, RawDatagramSocket> _sockets = {};

  // Map of STUN transaction ID to completer (for connectivity checks)
  final Map<String, Completer<StunMessage>> _pendingStunTransactions = {};

  // TURN client for relay candidates
  TurnClient? _turnClient;

  final IceOptions options;

  final _stateController = StreamController<IceState>.broadcast();
  final _candidateController = StreamController<Candidate>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();

  IceConnectionImpl({
    required bool iceControlling,
    this.options = const IceOptions(),
  })  : _iceControlling = iceControlling,
        _localUsername = randomString(4),
        _localPassword = randomString(22) {
    _generation = 0;
  }

  @override
  bool get iceControlling => _iceControlling;

  @override
  set iceControlling(bool value) {
    if (_generation > 0 || _nominated != null) {
      return; // Cannot change role after connection established
    }
    _iceControlling = value;
    // Note: Would need to recreate pairs with new role if needed
  }

  @override
  String get localUsername => _localUsername;

  @override
  String get localPassword => _localPassword;

  @override
  String get remoteUsername => _remoteUsername;

  @override
  String get remotePassword => _remotePassword;

  @override
  bool get remoteIsLite => _remoteIsLite;

  @override
  IceState get state => _state;

  @override
  List<Candidate> get localCandidates => List.unmodifiable(_localCandidates);

  @override
  List<Candidate> get remoteCandidates => List.unmodifiable(_remoteCandidates);

  @override
  List<CandidatePair> get checkList => List.unmodifiable(_checkList);

  @override
  CandidatePair? get nominated => _nominated;

  @override
  int get generation => _generation;

  @override
  bool get localCandidatesEnd => _localCandidatesEnd;

  @override
  bool get remoteCandidatesEnd => _remoteCandidatesEnd;

  @override
  Stream<IceState> get onStateChanged => _stateController.stream;

  @override
  Stream<Candidate> get onIceCandidate => _candidateController.stream;

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  void _setState(IceState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  void setRemoteParams({
    required bool iceLite,
    required String usernameFragment,
    required String password,
  }) {
    _remoteIsLite = iceLite;
    _remoteUsername = usernameFragment;
    _remotePassword = password;
  }

  @override
  Future<void> gatherCandidates() async {
    if (_state != IceState.newState) {
      return;
    }

    _setState(IceState.gathering);

    try {
      // Gather host candidates from network interfaces
      final addresses = await getHostAddresses(
        useIpv4: options.useIpv4,
        useIpv6: options.useIpv6,
        useLinkLocalAddress: false,
      );

      // Create host candidates for each address
      for (final address in addresses) {
        try {
          final addr = InternetAddress(address);

          // Bind a UDP socket to get a port
          final socket = await RawDatagramSocket.bind(
            addr,
            0, // Use any available port
          );

          final foundation = candidateFoundation('host', 'udp', address);
          final candidate = Candidate(
            foundation: foundation,
            component: 1, // RTP component
            transport: 'udp',
            priority: candidatePriority('host'),
            host: address,
            port: socket.port,
            type: 'host',
          );

          _localCandidates.add(candidate);
          _candidateController.add(candidate);
          _sockets[foundation] = socket;

          // Set up socket listener for incoming data
          _setupSocketListener(socket);

          // Create pairs with any already-received remote candidates
          for (final remote in _remoteCandidates) {
            if (candidate.canPairWith(remote)) {
              final pair = CandidatePair(
                id: '${candidate.foundation}-${remote.foundation}',
                localCandidate: candidate,
                remoteCandidate: remote,
                iceControlling: _iceControlling,
              );
              _checkList.add(pair);
            }
          }
          // Sort pairs by priority
          _checkList.sort((a, b) => b.priority.compareTo(a.priority));
        } catch (e) {
          // Failed to bind to this address, skip it
          continue;
        }
      }

      // Gather server reflexive candidates via STUN
      if (options.stunServer != null) {
        await _gatherReflexiveCandidates();
      }

      // Gather relay candidates via TURN
      if (options.turnServer != null &&
          options.turnUsername != null &&
          options.turnPassword != null) {
        await _gatherRelayCandidates();
      }

      _localCandidatesEnd = true;
      // Note: Don't transition to 'checking' here - that happens in connect()
      // when we're ready to perform connectivity checks
    } catch (e) {
      _setState(IceState.failed);
      rethrow;
    }
  }

  /// Gather server reflexive candidates via STUN
  Future<void> _gatherReflexiveCandidates() async {
    if (options.stunServer == null) return;

    final (stunHost, stunPort) = options.stunServer!;

    // Resolve STUN server address
    List<InternetAddress> stunAddresses;
    try {
      stunAddresses = await InternetAddress.lookup(stunHost);
    } catch (e) {
      // DNS resolution failed, skip reflexive candidate gathering
      return;
    }

    if (stunAddresses.isEmpty) return;

    final stunAddress = stunAddresses.first;

    // Create a copy to avoid concurrent modification
    final hostCandidates = _localCandidates.where((c) => c.type == 'host').toList();

    // Try to get reflexive candidates for each host candidate
    for (final hostCandidate in hostCandidates) {
      try {
        final socket = _sockets[hostCandidate.foundation];
        if (socket == null) continue;

        // Create STUN protocol instance bound to this socket
        final stun = StunProtocol(
          socket: socket,
          serverAddress: stunAddress,
          serverPort: stunPort,
        );

        // Perform STUN binding request
        final response = await stun.sendBindingRequest(
          timeout: Duration(seconds: 3),
        );

        // Extract mapped address from response
        if (response.messageClass == StunClass.successResponse) {
          final xorMapped = response.getAttribute(StunAttributeType.xorMappedAddress);
          final mapped = response.getAttribute(StunAttributeType.mappedAddress);

          final address = xorMapped ?? mapped;
          if (address != null) {
            final (mappedHost, mappedPort) = address as (String, int);

            // Create server reflexive candidate
            final foundation = candidateFoundation('srflx', 'udp', hostCandidate.host);
            final srflxCandidate = Candidate(
              foundation: foundation,
              component: 1,
              transport: 'udp',
              priority: candidatePriority('srflx'),
              host: mappedHost,
              port: mappedPort,
              type: 'srflx',
              relatedAddress: hostCandidate.host,
              relatedPort: hostCandidate.port,
            );

            _localCandidates.add(srflxCandidate);
            _candidateController.add(srflxCandidate);

            // Use the same socket as the base host candidate
            _sockets[foundation] = socket;

            // Create pairs with any already-received remote candidates
            for (final remote in _remoteCandidates) {
              if (srflxCandidate.canPairWith(remote)) {
                final pair = CandidatePair(
                  id: '${srflxCandidate.foundation}-${remote.foundation}',
                  localCandidate: srflxCandidate,
                  remoteCandidate: remote,
                  iceControlling: _iceControlling,
                );
                _checkList.add(pair);
              }
            }
            // Sort pairs by priority
            _checkList.sort((a, b) => b.priority.compareTo(a.priority));
          }
        }

        // Note: We don't close the StunProtocol here because we're reusing the socket
      } catch (e) {
        // Failed to get reflexive candidate for this host, continue
        continue;
      }
    }
  }

  /// Gather relay candidates via TURN
  Future<void> _gatherRelayCandidates() async {
    if (options.turnServer == null ||
        options.turnUsername == null ||
        options.turnPassword == null) {
      return;
    }

    try {
      // Create TURN client
      _turnClient = TurnClient(
        serverAddress: options.turnServer!,
        username: options.turnUsername!,
        password: options.turnPassword!,
        transport: TurnTransport.udp,
      );

      // Connect and allocate
      await _turnClient!.connect();

      final allocation = _turnClient!.allocation;
      if (allocation == null) return;

      // Get relayed address from allocation
      final (relayHost, relayPort) = allocation.relayedAddress;

      // Get base candidate (use first host candidate)
      final baseCandidates = _localCandidates.where((c) => c.type == 'host').toList();
      if (baseCandidates.isEmpty) return;

      final baseCandidate = baseCandidates.first;

      // Create relay candidate
      final foundation = candidateFoundation('relay', 'udp', relayHost);
      final relayCandidate = Candidate(
        foundation: foundation,
        component: 1,
        transport: 'udp',
        priority: candidatePriority('relay'),
        host: relayHost,
        port: relayPort,
        type: 'relay',
        relatedAddress: baseCandidate.host,
        relatedPort: baseCandidate.port,
      );

      _localCandidates.add(relayCandidate);
      _candidateController.add(relayCandidate);

      // Create pairs with any already-received remote candidates
      for (final remote in _remoteCandidates) {
        if (relayCandidate.canPairWith(remote)) {
          final pair = CandidatePair(
            id: '${relayCandidate.foundation}-${remote.foundation}',
            localCandidate: relayCandidate,
            remoteCandidate: remote,
            iceControlling: _iceControlling,
          );
          _checkList.add(pair);
        }
      }
      // Sort pairs by priority
      _checkList.sort((a, b) => b.priority.compareTo(a.priority));

    } catch (e) {
      // Failed to get relay candidate, continue without it
      _turnClient = null;
    }
  }

  @override
  Future<void> connect() async {
    if (_state != IceState.checking) {
      await gatherCandidates();
    }

    // Transition to checking state before performing checks
    _setState(IceState.checking);

    // Perform connectivity checks
    await _performConnectivityChecks();
  }

  /// Perform connectivity checks on candidate pairs
  Future<void> _performConnectivityChecks() async {
    // In trickle ICE, checklist may be empty initially
    // Don't fail immediately - wait for candidates to arrive
    if (_checkList.isEmpty) {
      if (_remoteCandidatesEnd) {
        // Only fail if we know no more candidates are coming
        _setState(IceState.failed);
      }
      // Otherwise, just stay in checking state and wait for trickle ICE candidates
      return;
    }

    // RFC 5245: Perform checks in priority order
    // For now, we'll do a simple sequential check
    for (final pair in _checkList) {
      if (pair.state != CandidatePairState.frozen &&
          pair.state != CandidatePairState.waiting) {
        continue;
      }

      // Attempt connectivity check
      final success = await _performConnectivityCheck(pair);

      if (success) {
        pair.updateState(CandidatePairState.succeeded);

        // First successful pair transitions to connected
        if (_state == IceState.checking) {
          _setState(IceState.connected);
        }

        // If controlling, nominate this pair
        if (_iceControlling && _nominated == null) {
          _nominated = pair;
          _setState(IceState.completed);
          return;
        }

        // If controlled, wait for nomination from remote
        // For now, just use the first successful pair
        if (!_iceControlling && _nominated == null) {
          _nominated = pair;
          _setState(IceState.completed);
          return;
        }
      } else {
        pair.updateState(CandidatePairState.failed);
      }
    }

    // No successful pairs found
    if (_nominated == null) {
      _setState(IceState.failed);
    }
  }

  /// Set up socket listener for incoming data
  void _setupSocketListener(RawDatagramSocket socket) {
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          _handleIncomingData(datagram.data, datagram.address, datagram.port);
        }
      }
    });
  }

  /// Handle incoming data from socket
  void _handleIncomingData(Uint8List data, InternetAddress address, int port) {
    // Check if this is a STUN message
    if (_isStunMessage(data)) {
      _handleStunMessage(data, address, port);
      return;
    }

    // Non-STUN data - deliver to application layer
    // This would be DTLS data in a real WebRTC connection
    print('[ICE] Delivering ${data.length} bytes of non-STUN data to application');
    _dataController.add(data);
  }

  /// Handle incoming STUN message
  void _handleStunMessage(Uint8List data, InternetAddress address, int port) {
    try {
      final message = parseStunMessage(data);
      if (message == null) {
        return; // Invalid STUN message
      }

      // Check if this is a response to a pending transaction
      if (message.messageClass == StunClass.successResponse ||
          message.messageClass == StunClass.errorResponse) {
        final tid = message.transactionIdHex;
        final completer = _pendingStunTransactions.remove(tid);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      } else if (message.messageClass == StunClass.request) {
        // Handle incoming STUN requests (binding requests from remote peer)
        _handleStunRequest(message, address, port);
      }
    } catch (e) {
      // Failed to parse STUN message, ignore
    }
  }

  /// Handle incoming STUN binding request
  void _handleStunRequest(StunMessage request, InternetAddress address, int port) {
    // Create a success response
    final response = StunMessage(
      method: request.method,
      messageClass: StunClass.successResponse,
      transactionId: request.transactionId,
    );

    // Add XOR-MAPPED-ADDRESS with the source address/port
    response.setAttribute(
      StunAttributeType.xorMappedAddress,
      (address.address, port),
    );

    // Add MESSAGE-INTEGRITY if request had it
    if (request.getAttribute(StunAttributeType.messageIntegrity) != null) {
      final passwordBytes = Uint8List.fromList(_localPassword.codeUnits);
      response.addMessageIntegrity(passwordBytes);
    }

    // Send response back to source
    // Find the socket to use (should be the one that received the request)
    for (final socket in _sockets.values) {
      if (socket.address.address == address.address ||
          socket.address.type == address.type) {
        final responseBytes = response.toBytes();
        socket.send(responseBytes, address, port);
        break;
      }
    }
  }

  /// Check if data looks like a STUN message
  bool _isStunMessage(Uint8List data) {
    if (data.length < 20) return false;

    // STUN messages start with 0x00 or 0x01 in the first two bits
    // and have the magic cookie at bytes 4-7
    final firstByte = data[0];
    if ((firstByte & 0xC0) != 0) return false;

    // Check for STUN magic cookie (0x2112A442) at offset 4
    if (data.length >= 8) {
      final magicCookie = (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
      return magicCookie == 0x2112A442;
    }

    return false;
  }

  /// Perform a connectivity check on a single candidate pair
  Future<bool> _performConnectivityCheck(CandidatePair pair) async {
    try {
      pair.updateState(CandidatePairState.inProgress);

      // Get the socket for the local candidate
      final socket = _sockets[pair.localCandidate.foundation];
      if (socket == null) {
        return false;
      }

      // Resolve remote address
      final remoteAddr = InternetAddress(pair.remoteCandidate.host);

      // Create STUN binding request with ICE credentials
      final request = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );

      // Add USERNAME attribute (remote:local for requests)
      request.setAttribute(
        StunAttributeType.username,
        '$_remoteUsername:$_localUsername',
      );

      // Add PRIORITY attribute
      request.setAttribute(
        StunAttributeType.priority,
        pair.localCandidate.priority,
      );

      // Add ICE-CONTROLLING or ICE-CONTROLLED attribute
      if (_iceControlling) {
        request.setAttribute(StunAttributeType.iceControlling, 0);
      } else {
        request.setAttribute(StunAttributeType.iceControlled, 0);
      }

      // Add MESSAGE-INTEGRITY
      if (_remotePassword.isNotEmpty) {
        final passwordBytes = Uint8List.fromList(_remotePassword.codeUnits);
        request.addMessageIntegrity(passwordBytes);
      }

      // Register pending transaction
      final tid = request.transactionIdHex;
      final completer = Completer<StunMessage>();
      _pendingStunTransactions[tid] = completer;

      // Send request
      final requestBytes = request.toBytes();
      socket.send(requestBytes, remoteAddr, pair.remoteCandidate.port);

      // Wait for response with timeout
      try {
        final response = await completer.future.timeout(
          Duration(seconds: 3),
          onTimeout: () {
            _pendingStunTransactions.remove(tid);
            throw TimeoutException('STUN connectivity check timed out');
          },
        );

        // Check if response is successful
        if (response.messageClass == StunClass.successResponse) {
          pair.stats.packetsReceived++;
          return true;
        }

        return false;
      } catch (e) {
        _pendingStunTransactions.remove(tid);
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> addRemoteCandidate(Candidate? candidate) async {
    if (candidate == null) {
      _remoteCandidatesEnd = true;
      return;
    }

    // Validate candidate
    validateRemoteCandidate(candidate);

    // Add to remote candidates
    _remoteCandidates.add(candidate);

    // Create pairs with local candidates
    final newPairs = <CandidatePair>[];
    for (final local in _localCandidates) {
      if (local.canPairWith(candidate)) {
        final pair = CandidatePair(
          id: '${local.foundation}-${candidate.foundation}',
          localCandidate: local,
          remoteCandidate: candidate,
          iceControlling: _iceControlling,
        );
        _checkList.add(pair);
        newPairs.add(pair);
      }
    }

    // Sort pairs by priority
    _checkList.sort((a, b) => b.priority.compareTo(a.priority));

    // If we're in checking state and got new pairs, perform checks on them (trickle ICE)
    if (_state == IceState.checking && newPairs.isNotEmpty) {
      _checkNewPairs(newPairs);
    }
  }

  /// Perform connectivity checks on new candidate pairs (for trickle ICE)
  /// This runs asynchronously to not block addRemoteCandidate
  void _checkNewPairs(List<CandidatePair> newPairs) {
    // Run checks asynchronously
    Future(() async {
      for (final pair in newPairs) {
        // Skip if already checked or in progress
        if (pair.state != CandidatePairState.frozen &&
            pair.state != CandidatePairState.waiting) {
          continue;
        }

        // Perform connectivity check
        final success = await _performConnectivityCheck(pair);

        if (success) {
          pair.updateState(CandidatePairState.succeeded);

          // First successful pair transitions to connected
          if (_state == IceState.checking) {
            _setState(IceState.connected);
          }

          // If controlling, nominate this pair
          if (_iceControlling && _nominated == null) {
            _nominated = pair;
            _setState(IceState.completed);
            return;
          }

          // If controlled, wait for nomination from remote
          // For now, just use the first successful pair
          if (!_iceControlling && _nominated == null) {
            _nominated = pair;
            _setState(IceState.completed);
            return;
          }
        } else {
          pair.updateState(CandidatePairState.failed);
        }
      }
    });
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_nominated == null) {
      throw StateError('No nominated pair available');
    }

    // Get the socket for the local candidate
    final socket = _sockets[_nominated!.localCandidate.foundation];
    if (socket == null) {
      throw StateError('Socket not found for nominated pair');
    }

    // Send data to remote candidate
    final remoteAddr = InternetAddress(_nominated!.remoteCandidate.host);
    final remotePort = _nominated!.remoteCandidate.port;

    socket.send(data, remoteAddr, remotePort);

    // Update statistics
    _nominated!.stats.packetsSent++;
    _nominated!.stats.bytesSent += data.length;
  }

  @override
  Future<void> close() async {
    _setState(IceState.closed);

    // Close TURN client if present
    if (_turnClient != null) {
      await _turnClient!.close();
      _turnClient = null;
    }

    // Close all sockets
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();

    await _stateController.close();
    await _candidateController.close();
    await _dataController.close();
  }

  @override
  Future<void> restart() async {
    _generation++;
    _localUsername = randomString(4);
    _localPassword = randomString(22);
    _remoteUsername = '';
    _remotePassword = '';

    // Close existing sockets
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();

    _localCandidates.clear();
    _remoteCandidates.clear();
    _checkList.clear();
    _nominated = null;
    _localCandidatesEnd = false;
    _remoteCandidatesEnd = false;
    _setState(IceState.newState);
  }

  @override
  Candidate? getDefaultCandidate() {
    // Return the first host candidate, or first candidate if no host
    final hostCandidates = _localCandidates.where((c) => c.type == 'host');
    if (hostCandidates.isNotEmpty) {
      return hostCandidates.first;
    }
    return _localCandidates.isNotEmpty ? _localCandidates.first : null;
  }
}
