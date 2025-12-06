import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/mdns.dart';
import 'package:webrtc_dart/src/ice/tcp_transport.dart';
import 'package:webrtc_dart/src/ice/utils.dart';
import 'package:webrtc_dart/src/stun/attributes.dart' show Address;
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
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .substring(0, length);
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

  /// Enable TCP candidates (RFC 6544)
  final bool useTcp;

  /// Enable UDP candidates
  final bool useUdp;

  /// Enable mDNS candidate obfuscation (RFC 8828)
  ///
  /// When enabled, local IP addresses in host candidates are replaced
  /// with random `.local` hostnames to protect user privacy.
  final bool useMdns;

  const IceOptions({
    this.stunServer,
    this.turnServer,
    this.turnUsername,
    this.turnPassword,
    this.useIpv4 = true,
    this.useIpv6 = true,
    this.portRange,
    this.useTcp = false, // Disabled by default for compatibility
    this.useUdp = true,
    this.useMdns = false, // Disabled by default for compatibility
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

  /// Tie-breaker for ICE role conflict resolution (RFC 8445)
  /// Random 64-bit number
  late final BigInt _tieBreaker;

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

  // TURN channel numbers for efficient data relay (peer address -> channel)
  final Map<String, int> _turnChannels = {};

  // Subscription for TURN receive stream
  StreamSubscription<(Address, Uint8List)>? _turnReceiveSubscription;

  // TCP candidate gatherer for passive TCP candidates
  TcpCandidateGatherer? _tcpGatherer;

  // Map of candidate foundation to TCP connection
  final Map<String, IceTcpConnection> _tcpConnections = {};

  // mDNS hostname to IP address mapping (for obfuscated candidates)
  final Map<String, String> _mdnsHostnames = {};

  // Whether mDNS service is started
  bool _mdnsStarted = false;

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
    // Generate random 64-bit tie-breaker for ICE role conflict resolution
    final bytes = randomBytes(8);
    _tieBreaker = BigInt.from(bytes[0]) |
        (BigInt.from(bytes[1]) << 8) |
        (BigInt.from(bytes[2]) << 16) |
        (BigInt.from(bytes[3]) << 24) |
        (BigInt.from(bytes[4]) << 32) |
        (BigInt.from(bytes[5]) << 40) |
        (BigInt.from(bytes[6]) << 48) |
        (BigInt.from(bytes[7]) << 56);
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
      // Start mDNS service if obfuscation is enabled
      if (options.useMdns && !_mdnsStarted) {
        await mdnsService.start();
        _mdnsStarted = true;
      }

      // Gather host candidates from network interfaces
      final addresses = await getHostAddresses(
        useIpv4: options.useIpv4,
        useIpv6: options.useIpv6,
        useLinkLocalAddress: false,
      );

      // Create UDP host candidates for each address
      if (options.useUdp) {
        for (final address in addresses) {
          try {
            final addr = InternetAddress(address);

            // Bind a UDP socket to get a port
            final socket = await RawDatagramSocket.bind(
              addr,
              0, // Use any available port
            );

            // Obfuscate the host address with mDNS if enabled
            String candidateHost = address;
            if (options.useMdns) {
              final mdnsHostname = mdnsService.registerHostname(address);
              _mdnsHostnames[mdnsHostname] = address;
              candidateHost = mdnsHostname;
            }

            final foundation = candidateFoundation('host', 'udp', address);
            final candidate = Candidate(
              foundation: foundation,
              component: 1, // RTP component
              transport: 'udp',
              priority: candidatePriority('host'),
              host: candidateHost,
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
      }

      // Create TCP host candidates (passive mode) for each address
      if (options.useTcp) {
        await _gatherTcpCandidates(addresses);
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
    final hostCandidates =
        _localCandidates.where((c) => c.type == 'host').toList();

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
          final xorMapped =
              response.getAttribute(StunAttributeType.xorMappedAddress);
          final mapped = response.getAttribute(StunAttributeType.mappedAddress);

          final address = xorMapped ?? mapped;
          if (address != null) {
            final (mappedHost, mappedPort) = address as (String, int);

            // Create server reflexive candidate
            final foundation =
                candidateFoundation('srflx', 'udp', hostCandidate.host);
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
      final baseCandidates =
          _localCandidates.where((c) => c.type == 'host').toList();
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

      // Wire up TURN receive stream to deliver relayed data
      _turnReceiveSubscription = _turnClient!.onReceive.listen((event) {
        final (peerAddress, data) = event;
        _handleTurnData(peerAddress, data);
      });

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

  /// Gather TCP host candidates (passive mode per RFC 6544)
  ///
  /// TCP candidates are gathered as passive (tcptype=passive), meaning
  /// we listen for incoming connections rather than initiating them.
  /// The remote peer with active TCP type will connect to us.
  Future<void> _gatherTcpCandidates(List<String> addresses) async {
    _tcpGatherer = TcpCandidateGatherer();

    final tcpHosts = await _tcpGatherer!.gatherHostCandidates(addresses);

    for (final tcpHost in tcpHosts) {
      final foundation = candidateFoundation('host', 'tcp', tcpHost.address);
      final candidate = Candidate(
        foundation: foundation,
        component: 1, // RTP component
        transport: 'tcp',
        priority: candidatePriority('host',
            transportPreference: 6), // TCP has lower preference
        host: tcpHost.address,
        port: tcpHost.port,
        type: 'host',
        tcpType: 'passive', // We listen for connections (RFC 6544)
      );

      _localCandidates.add(candidate);
      _candidateController.add(candidate);

      // Set up listener for incoming TCP connections
      final server = _tcpGatherer!.getServer(tcpHost.address);
      if (server != null) {
        server.onConnection.listen(_handleTcpConnection);
      }

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
    }

    // Sort pairs by priority
    if (tcpHosts.isNotEmpty) {
      _checkList.sort((a, b) => b.priority.compareTo(a.priority));
    }
  }

  /// Handle incoming TCP connection
  void _handleTcpConnection(IceTcpConnection connection) {
    final remoteKey =
        '${connection.remoteAddress.address}:${connection.remotePort}';
    _tcpConnections[remoteKey] = connection;

    // Listen for incoming STUN messages over TCP
    connection.onMessage.listen((data) {
      if (_isStunMessage(data)) {
        _handleStunMessage(
            data, connection.remoteAddress, connection.remotePort);
      } else {
        // Non-STUN data received over TCP (e.g., DTLS)
        if (!_dataController.isClosed) {
          _dataController.add(data);
        }
      }
    });

    connection.onStateChange.listen((state) {
      if (state == TcpConnectionState.closed ||
          state == TcpConnectionState.failed) {
        _tcpConnections.remove(remoteKey);
      }
    });
  }

  /// Handle data received through TURN relay
  void _handleTurnData(Address peerAddress, Uint8List data) {
    final (host, port) = peerAddress;

    // Check if this is a STUN message
    if (_isStunMessage(data)) {
      _handleStunMessage(data, InternetAddress(host), port);
      return;
    }

    // Non-STUN data - deliver to application layer
    print(
        '[ICE] Delivering ${data.length} bytes of TURN-relayed data to application');
    _dataController.add(data);
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
  /// Uses multiple rounds with retries for trickle ICE scenarios
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

    // RFC 5245: Perform checks with retries
    // Try up to 3 rounds of connectivity checks to allow remote to be ready
    const maxRounds = 3;
    const delayBetweenRounds = Duration(seconds: 2);

    for (var round = 0; round < maxRounds; round++) {
      if (round > 0) {
        print('[ICE] Connectivity check round ${round + 1}/$maxRounds');
        await Future.delayed(delayBetweenRounds);
      }

      // RFC 5245: Perform checks in priority order
      for (final pair in _checkList) {
        // Skip already succeeded pairs
        if (pair.state == CandidatePairState.succeeded) {
          continue;
        }

        // Reset failed pairs on retry rounds
        if (pair.state == CandidatePairState.failed && round > 0) {
          pair.updateState(CandidatePairState.waiting);
        }

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

      // Check if any pair succeeded
      if (_nominated != null) {
        return;
      }
    }

    // No successful pairs found after all retry rounds
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
    print(
        '[ICE] Delivering ${data.length} bytes of non-STUN data to application');
    _dataController.add(data);
  }

  /// Handle incoming STUN message
  void _handleStunMessage(Uint8List data, InternetAddress address, int port) {
    try {
      final message = parseStunMessage(data);
      if (message == null) {
        print(
            '[ICE] Failed to parse STUN message from ${address.address}:$port');
        return; // Invalid STUN message
      }

      print(
          '[ICE] Received STUN ${message.messageClass} from ${address.address}:$port');

      // Check if this is a response to a pending transaction
      if (message.messageClass == StunClass.successResponse ||
          message.messageClass == StunClass.errorResponse) {
        final tid = message.transactionIdHex;
        final completer = _pendingStunTransactions.remove(tid);
        if (completer != null && !completer.isCompleted) {
          print('[ICE] STUN response matched pending transaction');
          completer.complete(message);
        } else {
          print('[ICE] STUN response for unknown transaction: $tid');
        }
      } else if (message.messageClass == StunClass.request) {
        // Handle incoming STUN requests (binding requests from remote peer)
        print('[ICE] Processing incoming STUN binding request');
        _handleStunRequest(message, address, port);
      }
    } catch (e) {
      print('[ICE] Error handling STUN message: $e');
    }
  }

  /// Handle incoming STUN binding request
  void _handleStunRequest(
      StunMessage request, InternetAddress address, int port) {
    // Create a success response
    final response = StunMessage(
      method: request.method,
      messageClass: StunClass.successResponse,
      transactionId: request.transactionId,
    );

    // Add XOR-MAPPED-ADDRESS with the source address/port
    print(
        '[ICE] Creating response with XOR-MAPPED-ADDRESS: (${address.address}, $port)');
    response.setAttribute(
      StunAttributeType.xorMappedAddress,
      (address.address, port),
    );

    // Add MESSAGE-INTEGRITY if request had it
    // For ICE, responses use the local password (which is the remote's perspective)
    if (request.getAttribute(StunAttributeType.messageIntegrity) != null) {
      final passwordBytes = Uint8List.fromList(_localPassword.codeUnits);
      response.addMessageIntegrity(passwordBytes);
    }

    // Always add FINGERPRINT for ICE (RFC 8445 requires it)
    response.addFingerprint();

    // RFC 8445: When a controlled agent receives a valid STUN request from the
    // controlling agent, it considers connectivity established from its perspective.
    // Find and update the matching candidate pair.
    if (!_iceControlling) {
      _handleTriggeredCheck(address.address, port);
    }

    // Find the socket that matches the remote's address family (IPv4 vs IPv6)
    // Since we're responding to a request that arrived on our socket, we need to
    // send the response from the same socket. In practice, find the socket
    // that can reach the remote address.
    RawDatagramSocket? sendSocket;
    for (final socket in _sockets.values) {
      // Match IPv4 to IPv4, IPv6 to IPv6
      if (socket.address.type == address.type) {
        sendSocket = socket;
        break;
      }
    }

    // Fallback to any socket if we couldn't find a matching type
    sendSocket ??= _sockets.values.isNotEmpty ? _sockets.values.first : null;

    if (sendSocket != null) {
      final responseBytes = response.toBytes();
      sendSocket.send(responseBytes, address, port);
      print('[ICE] Sent STUN response to ${address.address}:$port');
    } else {
      print('[ICE] No socket available to send STUN response');
    }
  }

  /// Handle a triggered check - when controlled agent receives a check from controlling
  /// This allows the controlled agent to succeed connectivity based on the controlling agent's check
  void _handleTriggeredCheck(String remoteHost, int remotePort) {
    // Find the candidate pair matching this remote address
    for (final pair in _checkList) {
      if (pair.remoteCandidate.host == remoteHost &&
          pair.remoteCandidate.port == remotePort) {
        // Mark this pair as succeeded (we received a valid check and responded)
        if (pair.state != CandidatePairState.succeeded) {
          print('[ICE] Triggered check succeeded for $remoteHost:$remotePort');
          pair.updateState(CandidatePairState.succeeded);

          // First successful pair transitions to connected
          if (_state == IceState.checking) {
            _setState(IceState.connected);
          }

          // Nominate this pair
          if (_nominated == null) {
            _nominated = pair;
            _setState(IceState.completed);
          }
        }
        return;
      }
    }

    // No matching pair found - create peer reflexive candidate (RFC 5245 Section 7.2.1.3)
    // This handles the case where remote candidate was added with mDNS hostname (.local)
    // but binding request arrives from actual IP address
    print(
        '[ICE] Creating peer reflexive candidate for $remoteHost:$remotePort');

    // Create peer reflexive remote candidate
    final prflxCandidate = Candidate(
      foundation: 'prflx${_remoteCandidates.length}',
      component: 1,
      transport: 'UDP',
      priority: 2130706431, // High priority for prflx
      host: remoteHost,
      port: remotePort,
      type: 'prflx',
    );

    // Add to remote candidates
    _remoteCandidates.add(prflxCandidate);

    // Create pairs with all local candidates
    for (final localCandidate in _localCandidates) {
      final pairId =
          '${localCandidate.foundation}-${prflxCandidate.foundation}';
      final pair = CandidatePair(
        id: pairId,
        localCandidate: localCandidate,
        remoteCandidate: prflxCandidate,
        iceControlling: iceControlling,
      );
      _checkList.add(pair);

      // Mark this new pair as succeeded immediately
      print(
          '[ICE] Triggered check succeeded for prflx $remoteHost:$remotePort');
      pair.updateState(CandidatePairState.succeeded);

      // First successful pair transitions to connected
      if (_state == IceState.checking) {
        _setState(IceState.connected);
      }

      // Nominate this pair if none nominated yet
      if (_nominated == null) {
        _nominated = pair;
        _setState(IceState.completed);
      }
      return; // Only need one pair
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
      final magicCookie =
          (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
      return magicCookie == 0x2112A442;
    }

    return false;
  }

  /// Perform a connectivity check on a single candidate pair
  Future<bool> _performConnectivityCheck(CandidatePair pair) async {
    try {
      pair.updateState(CandidatePairState.inProgress);

      final localCandidate = pair.localCandidate;
      final remoteCandidate = pair.remoteCandidate;

      print(
          '[ICE] Checking ${localCandidate.host}:${localCandidate.port} -> ${remoteCandidate.host}:${remoteCandidate.port} (controlling: $_iceControlling)');

      // For relay candidates, we need TURN client
      final isRelay = localCandidate.type == 'relay';
      if (isRelay && _turnClient == null) {
        return false;
      }

      // For non-relay candidates, get the socket
      RawDatagramSocket? socket;
      if (!isRelay) {
        socket = _sockets[localCandidate.foundation];
        if (socket == null) {
          print(
              '[ICE] ERROR: Socket not found for foundation ${localCandidate.foundation}');
          print('[ICE] Available sockets: ${_sockets.keys.toList()}');
          return false;
        }
      }

      // Resolve remote address
      final remoteAddr = InternetAddress(remoteCandidate.host);

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
        localCandidate.priority,
      );

      // Add ICE-CONTROLLING or ICE-CONTROLLED attribute
      if (_iceControlling) {
        request.setAttribute(StunAttributeType.iceControlling, _tieBreaker);
        // Aggressive nomination: add USE-CANDIDATE when controlling
        // This tells the controlled agent we want to nominate this pair
        request.setAttribute(StunAttributeType.useCandidate, null);
      } else {
        request.setAttribute(StunAttributeType.iceControlled, _tieBreaker);
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

      // Send request - via TURN for relay candidates, direct for others
      final requestBytes = request.toBytes();
      print(
          '[ICE] Sending STUN request (${requestBytes.length} bytes) to ${remoteCandidate.host}:${remoteCandidate.port}');
      if (isRelay) {
        final peerAddress = (remoteCandidate.host, remoteCandidate.port);
        await _turnClient!.sendData(peerAddress, requestBytes);
      } else {
        socket!.send(requestBytes, remoteAddr, remoteCandidate.port);
      }

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

    final localCandidate = _nominated!.localCandidate;
    final remoteCandidate = _nominated!.remoteCandidate;

    // Check if this is a relay candidate - route through TURN
    if (localCandidate.type == 'relay' && _turnClient != null) {
      await _sendViaTurn(remoteCandidate, data);
    } else {
      // Direct send for host/srflx candidates
      final socket = _sockets[localCandidate.foundation];
      if (socket == null) {
        throw StateError('Socket not found for nominated pair');
      }

      final remoteAddr = InternetAddress(remoteCandidate.host);
      socket.send(data, remoteAddr, remoteCandidate.port);
    }

    // Update statistics
    _nominated!.stats.packetsSent++;
    _nominated!.stats.bytesSent += data.length;
  }

  /// Send data through TURN relay
  Future<void> _sendViaTurn(Candidate remoteCandidate, Uint8List data) async {
    if (_turnClient == null) {
      throw StateError('TURN client not available');
    }

    final peerAddress = (remoteCandidate.host, remoteCandidate.port);
    final addrKey = '${remoteCandidate.host}:${remoteCandidate.port}';

    // Try to use channel data (more efficient) if we have a channel bound
    var channelNumber = _turnChannels[addrKey];

    if (channelNumber == null) {
      // Bind a channel for this peer (first time)
      try {
        channelNumber = await _turnClient!.bindChannel(peerAddress);
        _turnChannels[addrKey] = channelNumber;
      } catch (e) {
        // Fall back to Send indication if channel binding fails
        await _turnClient!.sendData(peerAddress, data);
        return;
      }
    }

    // Send via channel data (4-byte header vs ~36+ bytes for Send indication)
    await _turnClient!.sendChannelData(channelNumber, data);
  }

  @override
  Future<void> close() async {
    _setState(IceState.closed);

    // Cancel TURN receive subscription
    await _turnReceiveSubscription?.cancel();
    _turnReceiveSubscription = null;

    // Close TURN client if present
    if (_turnClient != null) {
      await _turnClient!.close();
      _turnClient = null;
    }
    _turnChannels.clear();

    // Close all UDP sockets
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();

    // Close all TCP connections
    for (final connection in _tcpConnections.values) {
      await connection.close();
    }
    _tcpConnections.clear();

    // Close TCP gatherer (closes all server sockets)
    await _tcpGatherer?.close();
    _tcpGatherer = null;

    // Clear mDNS mappings
    _mdnsHostnames.clear();
    // Note: We don't stop the global mDNS service as it may be shared

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

    // Cancel TURN receive subscription
    await _turnReceiveSubscription?.cancel();
    _turnReceiveSubscription = null;

    // Close TURN client if present
    if (_turnClient != null) {
      await _turnClient!.close();
      _turnClient = null;
    }
    _turnChannels.clear();

    // Close existing UDP sockets
    for (final socket in _sockets.values) {
      socket.close();
    }
    _sockets.clear();

    // Close TCP connections
    for (final connection in _tcpConnections.values) {
      await connection.close();
    }
    _tcpConnections.clear();

    // Close TCP gatherer
    await _tcpGatherer?.close();
    _tcpGatherer = null;

    // Clear mDNS mappings
    _mdnsHostnames.clear();

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
