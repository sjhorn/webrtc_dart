import 'dart:async';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/candidate_pair.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';

final _log = WebRtcLogging.transport;

/// RTCIceConnectionState
/// W3C ICE connection state machine.
/// Reference: https://w3c.github.io/webrtc-pc/#dom-rtciceconnectionstate
///
/// State diagram:
/// ```
///                                     +------------+
///                                     |            |
///                                     |disconnected|
///                                     |            |
///                                     +------------+
///                                     ^           ^
///                                     |           |
/// +------+      +----------+      +-----------+      +----------+
/// |      |      |          |      |           |      |          |
/// | new  | ---> | checking | ---> | connected | ---> | completed|
/// |      |      |          |      |           |      |          |
/// +------+      +----+-----+      +-----------+      +----------+
///                    |
///                    |
///                    v
///                +-------+
///                |       |
///                | failed|
///                |       |
///                +-------+
/// ```
enum RtcIceConnectionState {
  /// Initial state
  new_,

  /// Performing connectivity checks
  checking,

  /// At least one pair is working
  connected,

  /// All checks complete, nominated pair selected
  completed,

  /// Connection lost
  disconnected,

  /// No working pairs found
  failed,

  /// Connection has been closed
  closed,
}

/// RTCIceTransport - Wrapper for ICE connection with W3C state machine
/// Reference: werift-webrtc/packages/webrtc/src/transport/ice.ts RTCIceTransport
///
/// The ICE transport manages:
/// - ICE connectivity state machine
/// - Starting/stopping connectivity checks
/// - Adding remote candidates
/// - ICE restart
/// - Delegation to underlying gatherer
class RtcIceTransport {
  /// The underlying ICE gatherer
  final RtcIceGatherer gatherer;

  /// Current connection state
  RtcIceConnectionState _state = RtcIceConnectionState.new_;

  /// Whether renomination is in progress
  bool _renominating = false;

  /// Completer for waiting on start() completion
  Completer<void>? _waitStart;

  /// Stream controller for state changes
  final _stateController = StreamController<RtcIceConnectionState>.broadcast();

  /// Stream controller for ICE candidates (forwarded from gatherer)
  final _candidateController = StreamController<Candidate?>.broadcast();

  /// Stream controller for negotiation needed events
  final _negotiationNeededController = StreamController<void>.broadcast();

  /// Subscription to gatherer's candidate stream
  StreamSubscription<Candidate?>? _candidateSubscription;

  /// Subscription to connection's state stream
  StreamSubscription<IceState>? _connectionStateSubscription;

  /// Creates an RTCIceTransport wrapping the given ICE gatherer.
  RtcIceTransport(this.gatherer) {
    // Subscribe to connection state changes
    _connectionStateSubscription =
        connection.onStateChanged.listen(_handleConnectionStateChange);

    // Forward candidates from gatherer
    _candidateSubscription = gatherer.onIceCandidate.listen((candidate) {
      if (!_candidateController.isClosed) {
        _candidateController.add(candidate);
      }
    });
  }

  /// Direct access to the underlying ICE connection
  IceConnection get connection => gatherer.connection;

  /// Current connection state
  RtcIceConnectionState get state => _state;

  /// ICE role (controlling or controlled)
  String get role => connection.iceControlling ? 'controlling' : 'controlled';

  /// Gathering state (proxied from gatherer)
  IceGathererState get gatheringState => gatherer.gatheringState;

  /// Local candidates (proxied from gatherer)
  List<Candidate> get localCandidates => gatherer.localCandidates;

  /// Local ICE parameters (proxied from gatherer)
  RtcIceParameters get localParameters => gatherer.localParameters;

  /// Remote candidates
  List<Candidate> get remoteCandidates => connection.remoteCandidates;

  /// Candidate pairs (check list)
  List<CandidatePair> get candidatePairs => connection.checkList;

  /// Stream of connection state changes
  Stream<RtcIceConnectionState> get onStateChange => _stateController.stream;

  /// Stream of ICE candidates (null indicates end-of-candidates)
  Stream<Candidate?> get onIceCandidate => _candidateController.stream;

  /// Stream of negotiation needed events (fired on restart/renomination)
  Stream<void> get onNegotiationNeeded => _negotiationNeededController.stream;

  /// Gather candidates (delegates to gatherer)
  Future<void> gather() => gatherer.gather();

  /// Add a remote candidate
  ///
  /// [candidate] - The remote candidate to add, or null for end-of-candidates
  Future<void> addRemoteCandidate(Candidate? candidate) async {
    if (!connection.remoteCandidatesEnd) {
      await connection.addRemoteCandidate(candidate);
    }
  }

  /// Set remote ICE parameters
  ///
  /// [remoteParameters] - The remote ICE parameters (ufrag, pwd)
  /// [renomination] - If true, indicates renomination rather than restart
  void setRemoteParams(RtcIceParameters remoteParameters,
      {bool renomination = false}) {
    if (renomination) {
      _renominating = true;
    }

    // Check if credentials changed (indicates restart or renomination)
    final remoteUsername = connection.remoteUsername;
    final remotePassword = connection.remotePassword;

    if (remoteUsername.isNotEmpty &&
        remotePassword.isNotEmpty &&
        (remoteUsername != remoteParameters.usernameFragment ||
            remotePassword != remoteParameters.password)) {
      if (_renominating) {
        _log.fine('$_debugLabel: renomination with new params');
        // Note: resetNominatedPair not implemented - renomination handled by ICE restart
        _renominating = false;
      } else {
        _log.fine('$_debugLabel: restart with new params');
        restart();
      }
    }

    connection.setRemoteParams(
      iceLite: remoteParameters.iceLite,
      usernameFragment: remoteParameters.usernameFragment,
      password: remoteParameters.password,
    );
  }

  /// Restart ICE (generate new credentials)
  void restart() {
    connection.restart();
    _setState(RtcIceConnectionState.new_);
    gatherer.gatheringState = IceGathererState.new_;
    _waitStart = null;

    if (!_negotiationNeededController.isClosed) {
      _negotiationNeededController.add(null);
    }
  }

  /// Start connectivity checks
  ///
  /// Throws if:
  /// - Transport is closed
  /// - Remote parameters are missing
  Future<void> start() async {
    if (_state == RtcIceConnectionState.closed) {
      throw StateError('RTCIceTransport is closed');
    }

    if (connection.remotePassword.isEmpty ||
        connection.remoteUsername.isEmpty) {
      throw StateError('Remote ICE parameters missing');
    }

    // If already starting, wait for completion
    if (_waitStart != null) {
      await _waitStart!.future;
      return;
    }

    _waitStart = Completer<void>();

    _setState(RtcIceConnectionState.checking);

    try {
      await connection.connect();
      _waitStart?.complete();
    } catch (error) {
      _setState(RtcIceConnectionState.failed);
      _waitStart?.completeError(error);
      rethrow;
    } finally {
      _waitStart = null;
    }
  }

  /// Stop and close the transport
  Future<void> stop() async {
    if (_state != RtcIceConnectionState.closed) {
      _setState(RtcIceConnectionState.closed);
      await connection.close();
    }

    await _candidateSubscription?.cancel();
    _candidateSubscription = null;

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    await _stateController.close();
    await _candidateController.close();
    await _negotiationNeededController.close();

    await gatherer.close();
  }

  /// Handle state changes from the underlying ICE connection
  void _handleConnectionStateChange(IceState iceState) {
    final newState = _mapIceState(iceState);
    if (newState != null) {
      _setState(newState);
    }
  }

  /// Map internal IceState to W3C RTCIceConnectionState
  RtcIceConnectionState? _mapIceState(IceState internal) {
    switch (internal) {
      case IceState.newState:
        return RtcIceConnectionState.new_;
      case IceState.gathering:
        // Gathering is not a connection state - it's tracked separately
        return null;
      case IceState.checking:
        return RtcIceConnectionState.checking;
      case IceState.connected:
        return RtcIceConnectionState.connected;
      case IceState.completed:
        return RtcIceConnectionState.completed;
      case IceState.disconnected:
        return RtcIceConnectionState.disconnected;
      case IceState.failed:
        return RtcIceConnectionState.failed;
      case IceState.closed:
        return RtcIceConnectionState.closed;
    }
  }

  /// Set state and emit event
  void _setState(RtcIceConnectionState state) {
    if (state != _state) {
      _log.fine('$_debugLabel: state change $_state -> $state');
      _state = state;
      if (!_stateController.isClosed) {
        _stateController.add(state);
      }
    }
  }

  String get _debugLabel => 'RtcIceTransport';
}
