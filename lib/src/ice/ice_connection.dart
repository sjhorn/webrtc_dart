import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/mdns.dart';
import 'package:webrtc_dart/src/ice/tcp_transport.dart';
import 'package:webrtc_dart/src/ice/utils.dart';
import 'package:webrtc_dart/src/stun/attributes.dart' show Address;
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';
import 'package:webrtc_dart/src/turn/turn_client.dart';

final _log = WebRtcLogging.ice;

/// ICE Consent Freshness constants per RFC 7675
const _consentIntervalSeconds = 5;
const _consentMaxFailures = 6;

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

  /// Only gather relay (TURN) candidates.
  ///
  /// When true, host and server-reflexive (STUN) candidates are not gathered.
  /// This forces all traffic through the TURN relay server.
  /// Corresponds to iceTransportPolicy: "relay" in W3C WebRTC spec.
  final bool relayOnly;

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
    this.relayOnly = false,
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

  // ICE Consent Freshness (RFC 7675)
  Timer? _consentTimer;
  int _consentFailureCount = 0;
  final Random _random = Random();

  final IceOptions options;

  /// Debug label for tracing (e.g., "audio" or "video")
  final String debugLabel;

  final _stateController = StreamController<IceState>.broadcast();
  final _candidateController = StreamController<Candidate>.broadcast();
  final _dataController = StreamController<Uint8List>.broadcast();

  IceConnectionImpl({
    required bool iceControlling,
    this.options = const IceOptions(),
    this.debugLabel = '',
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
      final labelStr = debugLabel.isNotEmpty ? ':$debugLabel' : '';
      _log.fine('$labelStr State: $_state -> $newState');
      _state = newState;
      _stateController.add(newState);

      // Start consent freshness checks when connection is established
      if (newState == IceState.completed) {
        _startConsentChecks();
      }
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
    _log.fine(
        '[ICE] setRemoteParams: iceLite=$iceLite, ufrag=$usernameFragment, pwd=${password.substring(0, 8)}...');
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

      // In relay-only mode, skip host and STUN candidates
      // Just gather relay (TURN) candidates
      if (options.relayOnly) {
        _log.fine('[ICE] Relay-only mode: skipping host and STUN candidates');

        // Gather relay candidates via TURN
        if (options.turnServer != null &&
            options.turnUsername != null &&
            options.turnPassword != null) {
          await _gatherRelayCandidates();
        } else {
          _log.fine('[ICE] Relay-only mode but no TURN server configured!');
        }
      } else {
        // Normal mode: gather host, STUN, and TURN candidates

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
          _log.fine(
              '[ICE] Gathering reflexive candidates from STUN server: ${options.stunServer}');
          await _gatherReflexiveCandidates();
          _log.fine(
              '[ICE] Finished STUN gathering, local candidates: ${_localCandidates.length}');
        } else {
          _log.fine(' No STUN server configured');
        }

        // Gather relay candidates via TURN
        if (options.turnServer != null &&
            options.turnUsername != null &&
            options.turnPassword != null) {
          await _gatherRelayCandidates();
        }
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
    _log.fine(' STUN: Resolving $stunHost:$stunPort');

    // Resolve STUN server address
    List<InternetAddress> stunAddresses;
    try {
      stunAddresses = await InternetAddress.lookup(stunHost);
      _log.fine(
          '[ICE] STUN: Resolved to ${stunAddresses.map((a) => a.address).toList()}');
    } catch (e) {
      // DNS resolution failed, skip reflexive candidate gathering
      _log.fine(' STUN: DNS resolution failed: $e');
      return;
    }

    if (stunAddresses.isEmpty) {
      _log.fine(' STUN: No addresses found');
      return;
    }

    final stunAddress = stunAddresses.first;
    _log.fine(' STUN: Using address ${stunAddress.address}');

    // Create a copy to avoid concurrent modification
    final hostCandidates =
        _localCandidates.where((c) => c.type == 'host').toList();
    _log.fine(
        '[ICE] STUN: Found ${hostCandidates.length} host candidates to probe');

    // Try to get reflexive candidates for each host candidate
    for (final hostCandidate in hostCandidates) {
      _log.fine(
          '[ICE] STUN: Probing from ${hostCandidate.host}:${hostCandidate.port}');
      try {
        final socket = _sockets[hostCandidate.foundation];
        if (socket == null) {
          _log.fine(
              '[ICE] STUN: No socket for foundation ${hostCandidate.foundation}');
          continue;
        }

        // Create STUN binding request
        final request = StunMessage(
          method: StunMethod.binding,
          messageClass: StunClass.request,
        );

        // Register pending transaction
        final tid = request.transactionIdHex;
        final completer = Completer<StunMessage>();
        _pendingStunTransactions[tid] = completer;

        // Send binding request directly via socket
        _log.fine(
            '[ICE] STUN: Sending binding request to ${stunAddress.address}:$stunPort (tid=$tid)');
        final bytes = request.toBytes();
        socket.send(bytes, stunAddress, stunPort);

        // Wait for response with timeout
        StunMessage response;
        try {
          response = await completer.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              _pendingStunTransactions.remove(tid);
              throw TimeoutException('STUN request timed out');
            },
          );
        } catch (e) {
          _pendingStunTransactions.remove(tid);
          rethrow;
        }
        _log.fine(' STUN: Got response class=${response.messageClass}');

        // Extract mapped address from response
        if (response.messageClass == StunClass.successResponse) {
          final xorMapped =
              response.getAttribute(StunAttributeType.xorMappedAddress);
          final mapped = response.getAttribute(StunAttributeType.mappedAddress);
          _log.fine(' STUN: xorMapped=$xorMapped, mapped=$mapped');

          final address = xorMapped ?? mapped;
          if (address != null) {
            final (mappedHost, mappedPort) = address as (String, int);
            _log.fine(' STUN: Got reflexive address $mappedHost:$mappedPort');

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
      } catch (e) {
        // Failed to get reflexive candidate for this host, continue
        _log.fine(
            '[ICE] STUN: Failed for ${hostCandidate.host}:${hostCandidate.port}: $e');
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
      _log.fine('[ICE] Connecting to TURN server: ${options.turnServer}');

      // Create TURN client
      _turnClient = TurnClient(
        serverAddress: options.turnServer!,
        username: options.turnUsername!,
        password: options.turnPassword!,
        transport: TurnTransport.udp,
      );

      // Connect and allocate
      await _turnClient!.connect();
      _log.fine('[ICE] TURN allocation successful');

      final allocation = _turnClient!.allocation;
      if (allocation == null) {
        _log.fine('[ICE] TURN allocation returned null');
        return;
      }

      // Get relayed address from allocation
      final (relayHost, relayPort) = allocation.relayedAddress;
      _log.fine('[ICE] TURN relayed address: $relayHost:$relayPort');

      // Get base candidate info from host candidate if available,
      // otherwise use the mapped address from TURN or empty values
      String? relatedAddress;
      int? relatedPort;

      final baseCandidates =
          _localCandidates.where((c) => c.type == 'host').toList();
      if (baseCandidates.isNotEmpty) {
        final baseCandidate = baseCandidates.first;
        relatedAddress = baseCandidate.host;
        relatedPort = baseCandidate.port;
      } else if (allocation.mappedAddress != null) {
        // Use the mapped (server-reflexive) address from TURN response
        final (mappedHost, mappedPort) = allocation.mappedAddress!;
        relatedAddress = mappedHost;
        relatedPort = mappedPort;
      }

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
        relatedAddress: relatedAddress,
        relatedPort: relatedPort,
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
    } catch (e, st) {
      // Failed to get relay candidate, log and continue without it
      _log.warning('[ICE] TURN allocation failed: $e');
      _log.fine('[ICE] TURN allocation stack trace: $st');
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

  /// Generate a TCP active candidate to pair with a remote TCP passive candidate
  /// RFC 6544: Active candidates have port 9 (discard port) as a placeholder
  /// since the actual port is only known after connection establishment.
  Future<void> _generateTcpActiveCandidate(Candidate remotePassive) async {
    // Determine which local IP to use based on the remote candidate's IP version
    final remoteIsV4 =
        InternetAddress(remotePassive.host).type == InternetAddressType.IPv4;

    // Get local addresses
    final addresses = await getHostAddresses(
      useIpv4: options.useIpv4,
      useIpv6: options.useIpv6,
      useLinkLocalAddress: false,
    );
    String? localHost;

    for (final addr in addresses) {
      final isV4 = InternetAddress(addr).type == InternetAddressType.IPv4;
      if (isV4 == remoteIsV4) {
        localHost = addr;
        break;
      }
    }

    if (localHost == null) {
      _log.fine(
          '[ICE-TCP] No matching local address for TCP active candidate (need ${remoteIsV4 ? 'IPv4' : 'IPv6'})');
      return;
    }

    // Create TCP active candidate
    // RFC 6544: Active candidates use port 9 (discard) as placeholder
    final foundation = candidateFoundation('host', 'tcp', localHost);
    final activeCandidate = Candidate(
      foundation: foundation,
      component: 1,
      transport: 'tcp',
      priority: candidatePriority('host',
          transportPreference: 6), // TCP has lower preference than UDP
      host: localHost,
      port: 9, // RFC 6544: Active candidates use port 9
      type: 'host',
      tcpType: 'active',
    );

    // Check if we already have this candidate
    final exists = _localCandidates.any((c) =>
        c.transport.toLowerCase() == 'tcp' &&
        c.tcpType == 'active' &&
        c.host == localHost);

    if (!exists) {
      _localCandidates.add(activeCandidate);
      _log.fine(
          '[ICE-TCP] Generated TCP active candidate: ${activeCandidate.host}:${activeCandidate.port} tcptype=active');
    }
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
    _log.fine(
        '[ICE] Delivering ${data.length} bytes of TURN-relayed data to application');
    _dataController.add(data);
  }

  @override
  Future<void> connect() async {
    if (_state != IceState.checking) {
      await gatherCandidates();
    }

    _log.fine(
        '[ICE] connect() called, local candidates: ${_localCandidates.length}, remote candidates: ${_remoteCandidates.length}');
    _log.fine(
        '[ICE] Local candidates: ${_localCandidates.map((c) => '${c.type}:${c.host}:${c.port}').join(', ')}');
    _log.fine(
        '[ICE] Remote candidates: ${_remoteCandidates.map((c) => '${c.type}:${c.host}:${c.port}').join(', ')}');
    _log.fine(' Check list size: ${_checkList.length}');

    // Transition to checking state before performing checks
    _setState(IceState.checking);

    // Perform connectivity checks
    await _performConnectivityChecks();
  }

  /// Perform connectivity checks on candidate pairs
  /// Uses multiple rounds with retries for trickle ICE scenarios
  Future<void> _performConnectivityChecks() async {
    final labelStr = debugLabel.isNotEmpty ? ':$debugLabel' : '';

    // In trickle ICE, checklist may be empty initially
    // Don't fail immediately - wait for candidates to arrive
    if (_checkList.isEmpty) {
      _log.fine('$labelStr Check list is EMPTY');
      if (_remoteCandidatesEnd) {
        // Only fail if we know no more candidates are coming
        _setState(IceState.failed);
      }
      // Otherwise, just stay in checking state and wait for trickle ICE candidates
      return;
    }

    _log.fine(
        '$labelStr Starting connectivity checks with ${_checkList.length} pairs');
    for (final pair in _checkList) {
      _log.fine(
          '$labelStr   - ${pair.localCandidate.host}:${pair.localCandidate.port} -> ${pair.remoteCandidate.host}:${pair.remoteCandidate.port}');
    }

    // RFC 5245: Perform checks with retries
    // Try up to 3 rounds of connectivity checks to allow remote to be ready
    const maxRounds = 3;
    const delayBetweenRounds = Duration(seconds: 2);

    for (var round = 0; round < maxRounds; round++) {
      if (round > 0) {
        _log.fine('$labelStr Connectivity check round ${round + 1}/$maxRounds');
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
        final labelStr = debugLabel.isNotEmpty ? ':$debugLabel' : '';
        final localAddr =
            '${pair.localCandidate.host}:${pair.localCandidate.port}';
        final remoteAddr =
            '${pair.remoteCandidate.host}:${pair.remoteCandidate.port}';
        _log.fine('$labelStr Checking pair $localAddr -> $remoteAddr');
        final success = await _performConnectivityCheck(pair);
        _log.fine('$labelStr Check result: ${success ? 'SUCCESS' : 'FAILED'}');

        if (success) {
          pair.updateState(CandidatePairState.succeeded);

          // First successful pair transitions to connected
          _log.fine(
              '[ICE$labelStr] Current state=$_state, checking transition to connected');
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
          _log.fine(
              '[ICE] Socket received ${datagram.data.length} bytes from ${datagram.address.address}:${datagram.port}');
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
    _log.fine(
        '[ICE] Delivering ${data.length} bytes of non-STUN data to application');
    _dataController.add(data);
  }

  /// Handle incoming STUN message
  void _handleStunMessage(Uint8List data, InternetAddress address, int port) {
    try {
      final message = parseStunMessage(data);
      if (message == null) {
        _log.fine(
            '[ICE] Failed to parse STUN message from ${address.address}:$port');
        return; // Invalid STUN message
      }

      _log.fine(
          '[ICE] Received STUN ${message.messageClass} from ${address.address}:$port');

      // Check if this is a response to a pending transaction
      if (message.messageClass == StunClass.successResponse ||
          message.messageClass == StunClass.errorResponse) {
        final tid = message.transactionIdHex;
        final completer = _pendingStunTransactions.remove(tid);
        if (completer != null && !completer.isCompleted) {
          _log.fine(' STUN response matched pending transaction');
          completer.complete(message);
        } else {
          _log.fine(' STUN response for unknown transaction: $tid');
        }
      } else if (message.messageClass == StunClass.request) {
        // Handle incoming STUN requests (binding requests from remote peer)
        _log.fine(' Processing incoming STUN binding request');
        _handleStunRequest(message, address, port);
      }
    } catch (e) {
      _log.fine(' Error handling STUN message: $e');
    }
  }

  /// Handle incoming STUN binding request
  void _handleStunRequest(
      StunMessage request, InternetAddress address, int port) {
    // RFC 8445 Section 7.2.1.1: Detecting and Repairing Role Conflicts
    if (!_handleRoleConflict(request, address, port)) {
      return; // Role conflict detected, 487 error response sent
    }

    // Create a success response
    final response = StunMessage(
      method: request.method,
      messageClass: StunClass.successResponse,
      transactionId: request.transactionId,
    );

    // Add XOR-MAPPED-ADDRESS with the source address/port
    _log.fine(
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
      _log.fine(' Sent STUN response to ${address.address}:$port');
    } else {
      _log.fine(' No socket available to send STUN response');
    }
  }

  /// RFC 8445 Section 7.2.1.1: Detecting and Repairing Role Conflicts
  ///
  /// Returns true if the request should continue processing, false if a 487 error was sent.
  bool _handleRoleConflict(
      StunMessage request, InternetAddress address, int port) {
    final remoteControlling =
        request.getAttribute(StunAttributeType.iceControlling);
    final remoteControlled =
        request.getAttribute(StunAttributeType.iceControlled);

    // No role attribute means no conflict possible
    if (remoteControlling == null && remoteControlled == null) {
      return true;
    }

    // Extract remote tie-breaker (returned as BigInt from parsed STUN message)
    final BigInt remoteTieBreaker;
    final bool remoteIsControlling;
    if (remoteControlling != null) {
      remoteTieBreaker = remoteControlling as BigInt;
      remoteIsControlling = true;
    } else {
      remoteTieBreaker = remoteControlled as BigInt;
      remoteIsControlling = false;
    }

    // Check for role conflict
    final bool isConflict;
    if (_iceControlling && remoteIsControlling) {
      // Both agents think they're controlling
      isConflict = true;
    } else if (!_iceControlling && !remoteIsControlling) {
      // Both agents think they're controlled
      isConflict = true;
    } else {
      // No conflict
      return true;
    }

    if (!isConflict) {
      return true;
    }

    _log.fine('[ICE] Role conflict detected: we are '
        '${_iceControlling ? "controlling" : "controlled"}, '
        'remote is ${remoteIsControlling ? "controlling" : "controlled"}');

    // Compare tie-breakers to resolve conflict (both are BigInt)
    final theirTieBreaker = remoteTieBreaker;

    if (_iceControlling) {
      // We are controlling, remote also thinks they're controlling
      if (theirTieBreaker >= _tieBreaker) {
        // Remote wins - we switch to controlled
        _log.fine('[ICE] Tie-breaker: remote wins ($theirTieBreaker >= $_tieBreaker), '
            'switching to controlled');
        _iceControlling = false;
        return true; // Continue processing
      } else {
        // We win - send 487 error response
        _log.fine('[ICE] Tie-breaker: we win ($_tieBreaker > $theirTieBreaker), '
            'sending 487 Role Conflict');
        _send487RoleConflict(request, address, port);
        return false;
      }
    } else {
      // We are controlled, remote also thinks they're controlled
      if (theirTieBreaker >= _tieBreaker) {
        // Remote wins - they should be controlled, we switch to controlling
        _log.fine('[ICE] Tie-breaker: remote wins ($theirTieBreaker >= $_tieBreaker), '
            'switching to controlling');
        _iceControlling = true;
        return true; // Continue processing
      } else {
        // We win - we should be controlled, send 487 error response
        _log.fine('[ICE] Tie-breaker: we win ($_tieBreaker > $theirTieBreaker), '
            'sending 487 Role Conflict');
        _send487RoleConflict(request, address, port);
        return false;
      }
    }
  }

  /// Send a 487 Role Conflict error response
  void _send487RoleConflict(
      StunMessage request, InternetAddress address, int port) {
    final response = StunMessage(
      method: request.method,
      messageClass: StunClass.errorResponse,
      transactionId: request.transactionId,
    );

    // Add ERROR-CODE attribute with 487 Role Conflict
    response.setAttribute(
      StunAttributeType.errorCode,
      (487, 'Role Conflict'),
    );

    // Add MESSAGE-INTEGRITY if request had it
    if (request.getAttribute(StunAttributeType.messageIntegrity) != null) {
      final passwordBytes = Uint8List.fromList(_localPassword.codeUnits);
      response.addMessageIntegrity(passwordBytes);
    }

    // Always add FINGERPRINT for ICE
    response.addFingerprint();

    // Find socket to send response
    RawDatagramSocket? sendSocket;
    for (final socket in _sockets.values) {
      if (socket.address.type == address.type) {
        sendSocket = socket;
        break;
      }
    }
    sendSocket ??= _sockets.values.isNotEmpty ? _sockets.values.first : null;

    if (sendSocket != null) {
      final responseBytes = response.toBytes();
      sendSocket.send(responseBytes, address, port);
      _log.fine('[ICE] Sent 487 Role Conflict response to ${address.address}:$port');
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
          _log.fine(' Triggered check succeeded for $remoteHost:$remotePort');
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
    _log.fine(
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
      _log.fine(
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

      _log.fine(
          '[ICE] Checking ${localCandidate.host}:${localCandidate.port} -> ${remoteCandidate.host}:${remoteCandidate.port} (transport=${localCandidate.transport}, controlling: $_iceControlling)');

      // Check if this is a TCP candidate pair
      final isTcp = localCandidate.transport.toLowerCase() == 'tcp';
      if (isTcp) {
        return _performTcpConnectivityCheck(pair);
      }

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
          _log.fine(
              '[ICE] ERROR: Socket not found for foundation ${localCandidate.foundation}');
          _log.fine(' Available sockets: ${_sockets.keys.toList()}');
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

      // Add FINGERPRINT (required by RFC 8445 for ICE)
      request.addFingerprint();

      // Register pending transaction
      final tid = request.transactionIdHex;
      final completer = Completer<StunMessage>();
      _pendingStunTransactions[tid] = completer;

      // Send request - via TURN for relay candidates, direct for others
      final requestBytes = request.toBytes();
      _log.fine(
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

        // RFC 8445 Section 7.2.1.1: Handle 487 Role Conflict error
        if (response.messageClass == StunClass.errorResponse) {
          final errorCode = response.getAttribute(StunAttributeType.errorCode);
          if (errorCode != null) {
            final (code, reason) = errorCode as (int, String);
            if (code == 487) {
              _log.fine('[ICE] Received 487 Role Conflict - switching role and retrying');
              // Switch role and retry the check
              _iceControlling = !_iceControlling;
              // Recursive retry with new role
              return _performConnectivityCheck(pair);
            }
            _log.fine('[ICE] Connectivity check failed with error $code: $reason');
          }
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

  /// Perform TCP connectivity check for a candidate pair
  /// RFC 6544: TCP ICE connectivity checks
  Future<bool> _performTcpConnectivityCheck(CandidatePair pair) async {
    final localCandidate = pair.localCandidate;
    final remoteCandidate = pair.remoteCandidate;

    _log.fine(
        '[ICE-TCP] Checking ${localCandidate.host}:${localCandidate.port} (tcptype=${localCandidate.tcpType}) -> ${remoteCandidate.host}:${remoteCandidate.port} (tcptype=${remoteCandidate.tcpType})');

    // Only active candidates can initiate TCP connections
    if (localCandidate.tcpType != 'active') {
      _log.fine(
          '[ICE-TCP] Skipping check - local candidate is not active (tcptype=${localCandidate.tcpType})');
      return false;
    }

    // Remote must be passive for active to connect
    if (remoteCandidate.tcpType != 'passive') {
      _log.fine(
          '[ICE-TCP] Skipping check - remote candidate is not passive (tcptype=${remoteCandidate.tcpType})');
      return false;
    }

    try {
      // Create TCP connection to remote passive candidate
      final tcpConnection = IceTcpConnection(
        remoteAddress: InternetAddress(remoteCandidate.host),
        remotePort: remoteCandidate.port,
        localTcpType: IceTcpType.active,
      );

      _log.fine(
          '[ICE-TCP] Connecting to ${remoteCandidate.host}:${remoteCandidate.port}...');

      // Connect with timeout
      await tcpConnection.connect().timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('TCP connection timed out'),
          );

      _log.fine('[TCP] TCP connection established!');

      // Store the connection for later use
      final connectionKey = '${remoteCandidate.host}:${remoteCandidate.port}';
      _tcpConnections[connectionKey] = tcpConnection;

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
        request.setAttribute(StunAttributeType.useCandidate, null);
      } else {
        request.setAttribute(StunAttributeType.iceControlled, _tieBreaker);
      }

      // Add MESSAGE-INTEGRITY
      if (_remotePassword.isNotEmpty) {
        final passwordBytes = Uint8List.fromList(_remotePassword.codeUnits);
        request.addMessageIntegrity(passwordBytes);
      }

      // Add FINGERPRINT
      request.addFingerprint();

      // Register pending transaction
      final tid = request.transactionIdHex;
      final completer = Completer<StunMessage>();
      _pendingStunTransactions[tid] = completer;

      // Set up listener for STUN responses over TCP
      final subscription = tcpConnection.onMessage.listen((data) {
        if (_isStunMessage(data)) {
          final response = parseStunMessage(data);
          if (response != null &&
              (response.messageClass == StunClass.successResponse ||
                  response.messageClass == StunClass.errorResponse)) {
            final responseTid = response.transactionIdHex;
            final pendingCompleter = _pendingStunTransactions[responseTid];
            if (pendingCompleter != null && !pendingCompleter.isCompleted) {
              _pendingStunTransactions.remove(responseTid);
              pendingCompleter.complete(response);
            }
          }
        }
      });

      // Send STUN request over TCP
      final requestBytes = request.toBytes();
      _log.fine(
          '[ICE-TCP] Sending STUN request (${requestBytes.length} bytes) over TCP');
      await tcpConnection.send(requestBytes);

      // Wait for response
      try {
        final response = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _pendingStunTransactions.remove(tid);
            throw TimeoutException('STUN TCP connectivity check timed out');
          },
        );

        await subscription.cancel();

        if (response.messageClass == StunClass.successResponse) {
          _log.fine('[TCP] Connectivity check SUCCEEDED!');
          pair.stats.packetsReceived++;

          // Set up listener for application data
          tcpConnection.onMessage.listen((data) {
            if (!_isStunMessage(data)) {
              if (!_dataController.isClosed) {
                _dataController.add(data);
              }
            }
          });

          return true;
        }

        // RFC 8445 Section 7.2.1.1: Handle 487 Role Conflict error
        if (response.messageClass == StunClass.errorResponse) {
          final errorCode = response.getAttribute(StunAttributeType.errorCode);
          if (errorCode != null) {
            final (code, reason) = errorCode as (int, String);
            if (code == 487) {
              _log.fine('[TCP] Received 487 Role Conflict - switching role and retrying');
              _iceControlling = !_iceControlling;
              await tcpConnection.close();
              _tcpConnections.remove(connectionKey);
              return _performTcpConnectivityCheck(pair);
            }
            _log.fine('[TCP] Connectivity check failed with error $code: $reason');
          }
        }

        _log.fine('[TCP] Connectivity check failed - not a success response');
        await tcpConnection.close();
        _tcpConnections.remove(connectionKey);
        return false;
      } catch (e) {
        _log.fine('[TCP] Connectivity check failed: $e');
        await subscription.cancel();
        _pendingStunTransactions.remove(tid);
        await tcpConnection.close();
        _tcpConnections.remove(connectionKey);
        return false;
      }
    } catch (e) {
      _log.fine('[TCP] TCP connectivity check failed: $e');
      return false;
    }
  }

  @override
  Future<void> addRemoteCandidate(Candidate? candidate) async {
    if (candidate == null) {
      _remoteCandidatesEnd = true;
      _log.fine(' Remote candidate end-of-candidates marker received');
      return;
    }

    // Validate candidate
    validateRemoteCandidate(candidate);

    // Add to remote candidates
    _remoteCandidates.add(candidate);
    _log.fine(
        '[ICE] Added remote candidate: ${candidate.type} ${candidate.transport} ${candidate.host}:${candidate.port} tcptype=${candidate.tcpType}');

    // For TCP passive remote candidates, generate a TCP active local candidate
    // RFC 6544: Active candidates initiate connections to passive candidates
    if (candidate.transport.toLowerCase() == 'tcp' &&
        candidate.tcpType?.toLowerCase() == 'passive') {
      await _generateTcpActiveCandidate(candidate);
    }

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
        _log.fine(
            '[ICE] Created pair: ${local.type}:${local.transport}:${local.host}:${local.port} (tcptype=${local.tcpType}) <-> ${candidate.type}:${candidate.transport}:${candidate.host}:${candidate.port} (tcptype=${candidate.tcpType})');
      } else {
        _log.fine(
            '[ICE] Cannot pair: ${local.type}:${local.transport}:${local.host} (comp=${local.component}, tcptype=${local.tcpType}) with ${candidate.type}:${candidate.transport}:${candidate.host} (comp=${candidate.component}, tcptype=${candidate.tcpType})');
      }
    }
    _log.fine(
        '[ICE] Created ${newPairs.length} new pairs, total checklist size: ${_checkList.length}');

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

  /// Start ICE consent freshness checks (RFC 7675)
  /// Called after connection reaches completed state
  void _startConsentChecks() {
    _stopConsentChecks(); // Clear any existing timer
    _consentFailureCount = 0;

    _log.fine('[ICE] Starting consent freshness checks');
    _scheduleNextConsentCheck();
  }

  /// Stop consent freshness checks
  void _stopConsentChecks() {
    _consentTimer?.cancel();
    _consentTimer = null;
  }

  /// Schedule the next consent check with randomized interval
  void _scheduleNextConsentCheck() {
    final interval = _getRandomizedConsentInterval();
    _consentTimer = Timer(interval, () => _performConsentCheck());
  }

  /// Get randomized consent interval (4-6 seconds per RFC 7675)
  Duration _getRandomizedConsentInterval() {
    // RFC 7675: CONSENT_INTERVAL * (0.8 + 0.4 * random)
    // Results in 80% to 120% of base interval = 4 to 6 seconds
    final jitter = 0.8 + (_random.nextDouble() * 0.4);
    final ms = (_consentIntervalSeconds * 1000 * jitter).toInt();
    return Duration(milliseconds: ms);
  }

  /// Perform a consent freshness check on the nominated pair
  Future<void> _performConsentCheck() async {
    if (_nominated == null || _state == IceState.closed) {
      return;
    }

    final pair = _nominated!;
    final labelStr = debugLabel.isNotEmpty ? ':$debugLabel' : '';

    try {
      // Send STUN binding request to nominated pair
      final success = await _sendConsentRequest(pair);

      if (success) {
        // Reset failure count on success
        _consentFailureCount = 0;

        // If we were disconnected, restore to connected state
        if (_state == IceState.disconnected) {
          _log.fine('$labelStr Consent check succeeded, restoring connection');
          _setState(IceState.connected);
        }
      } else {
        // Increment failure count
        _consentFailureCount++;
        _log.fine(
            '$labelStr Consent check failed ($_consentFailureCount/$_consentMaxFailures)');

        if (_consentFailureCount >= _consentMaxFailures) {
          // Too many failures - close the connection
          _log.fine(
              '$labelStr Consent freshness failed after $_consentMaxFailures attempts');
          _stopConsentChecks();
          _setState(IceState.failed);
          return;
        } else if (_state == IceState.completed ||
            _state == IceState.connected) {
          // First failure - transition to disconnected
          _setState(IceState.disconnected);
        }
      }

      // Schedule next check
      _scheduleNextConsentCheck();
    } catch (e) {
      _log.fine('$labelStr Error during consent check: $e');
      _consentFailureCount++;
      if (_consentFailureCount >= _consentMaxFailures) {
        _stopConsentChecks();
        _setState(IceState.failed);
      } else {
        _scheduleNextConsentCheck();
      }
    }
  }

  /// Send a consent request to the nominated pair
  Future<bool> _sendConsentRequest(CandidatePair pair) async {
    final localCandidate = pair.localCandidate;
    final remoteCandidate = pair.remoteCandidate;

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
        return false;
      }
    }

    // Resolve remote address
    final remoteAddr = InternetAddress(remoteCandidate.host);

    // Create STUN binding request (simpler than connectivity check)
    final request = StunMessage(
      method: StunMethod.binding,
      messageClass: StunClass.request,
    );

    // Add USERNAME attribute
    request.setAttribute(
      StunAttributeType.username,
      '$_remoteUsername:$_localUsername',
    );

    // Add MESSAGE-INTEGRITY
    if (_remotePassword.isNotEmpty) {
      final passwordBytes = Uint8List.fromList(_remotePassword.codeUnits);
      request.addMessageIntegrity(passwordBytes);
    }

    // Add FINGERPRINT
    request.addFingerprint();

    // Register pending transaction
    final tid = request.transactionIdHex;
    final completer = Completer<StunMessage>();
    _pendingStunTransactions[tid] = completer;

    // Send request
    final requestBytes = request.toBytes();
    if (isRelay) {
      final peerAddress = (remoteCandidate.host, remoteCandidate.port);
      await _turnClient!.sendData(peerAddress, requestBytes);
    } else {
      socket!.send(requestBytes, remoteAddr, remoteCandidate.port);
    }

    // Wait for response with short timeout (consent checks should be quick)
    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _pendingStunTransactions.remove(tid);
          throw TimeoutException('Consent check timed out');
        },
      );

      return response.messageClass == StunClass.successResponse;
    } catch (e) {
      _pendingStunTransactions.remove(tid);
      return false;
    }
  }

  @override
  Future<void> close() async {
    _stopConsentChecks();
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
    _stopConsentChecks();
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
