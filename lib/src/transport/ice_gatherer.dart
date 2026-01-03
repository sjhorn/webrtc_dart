import 'dart:async';

import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

/// ICE Gatherer state
/// Represents the gathering state of the ICE gatherer.
/// See: https://w3c.github.io/webrtc-pc/#dom-rtcicegathererstate
enum IceGathererState {
  /// The ICE gatherer is in the "new" state and gathering has not started.
  new_,

  /// The ICE gatherer is in the process of gathering candidates.
  gathering,

  /// The ICE gatherer has finished gathering candidates.
  complete,
}

/// ICE Parameters
/// Contains the ICE credentials (username fragment and password).
/// Reference: werift-webrtc/packages/webrtc/src/transport/ice.ts RTCIceParameters
class RtcIceParameters {
  /// Whether this is ICE-lite
  final bool iceLite;

  /// ICE username fragment
  final String usernameFragment;

  /// ICE password
  final String password;

  const RtcIceParameters({
    this.iceLite = false,
    required this.usernameFragment,
    required this.password,
  });

  @override
  String toString() =>
      'RtcIceParameters(ufrag: $usernameFragment, pwd: ${password.substring(0, 4)}...)';
}

/// RTCIceGatherer - Handles candidate gathering
/// Reference: werift-webrtc/packages/webrtc/src/transport/ice.ts RTCIceGatherer
///
/// The ICE gatherer is responsible for:
/// - Managing the underlying ICE connection
/// - Gathering local candidates
/// - Tracking gathering state
/// - Exposing local ICE parameters
class RtcIceGatherer {
  /// The underlying ICE connection
  final IceConnection connection;

  /// Current gathering state
  IceGathererState _gatheringState = IceGathererState.new_;

  /// Stream controller for gathering state changes
  final _gatheringStateController =
      StreamController<IceGathererState>.broadcast();

  /// Stream controller for ICE candidates
  /// null indicates end-of-candidates
  final _iceCandidateController =
      StreamController<RTCIceCandidate?>.broadcast();

  /// Subscription to connection's candidate stream
  StreamSubscription<RTCIceCandidate>? _candidateSubscription;

  /// Creates an RTCIceGatherer wrapping the given ICE connection.
  ///
  /// [connection] - The underlying IceConnection to wrap
  RtcIceGatherer(this.connection) {
    // Subscribe to candidates from the underlying connection
    _candidateSubscription = connection.onIceCandidate.listen((candidate) {
      if (!_iceCandidateController.isClosed) {
        _iceCandidateController.add(candidate);
      }
    });
  }

  /// Current gathering state
  IceGathererState get gatheringState => _gatheringState;

  /// Allow setting gathering state (for ICE restart)
  set gatheringState(IceGathererState state) {
    _setState(state);
  }

  /// Stream of gathering state changes
  Stream<IceGathererState> get onGatheringStateChange =>
      _gatheringStateController.stream;

  /// Stream of ICE candidates (null indicates end-of-candidates)
  Stream<RTCIceCandidate?> get onIceCandidate => _iceCandidateController.stream;

  /// Local candidates that have been gathered
  List<RTCIceCandidate> get localCandidates => connection.localCandidates;

  /// Local ICE parameters (username fragment and password)
  RtcIceParameters get localParameters => RtcIceParameters(
        usernameFragment: connection.localUsername,
        password: connection.localPassword,
      );

  /// Gather local ICE candidates
  ///
  /// Transitions through: new -> gathering -> complete
  /// Emits candidates via [onIceCandidate] and a final null for end-of-candidates.
  Future<void> gather() async {
    if (_gatheringState == IceGathererState.new_) {
      _setState(IceGathererState.gathering);

      await connection.gatherCandidates();

      // Emit end-of-candidates signal (null candidate)
      if (!_iceCandidateController.isClosed) {
        _iceCandidateController.add(null);
      }

      _setState(IceGathererState.complete);
    }
  }

  /// Set gathering state and emit event
  void _setState(IceGathererState state) {
    if (state != _gatheringState) {
      _gatheringState = state;
      if (!_gatheringStateController.isClosed) {
        _gatheringStateController.add(state);
      }
    }
  }

  /// Close the gatherer and release resources
  Future<void> close() async {
    await _candidateSubscription?.cancel();
    _candidateSubscription = null;

    // Only close controllers if not already closed
    if (!_gatheringStateController.isClosed) {
      await _gatheringStateController.close();
    }
    if (!_iceCandidateController.isClosed) {
      await _iceCandidateController.close();
    }
  }
}
