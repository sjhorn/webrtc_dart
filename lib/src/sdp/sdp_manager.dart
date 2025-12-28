import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

/// SDPManager handles SDP building, parsing, and description state management.
///
/// This class matches the architecture of werift-webrtc's sdpManager.ts,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Building offer/answer SDP from transceiver and SCTP state
/// - Parsing and validating SDP strings
/// - Managing pending/current description state
/// - Allocating unique media IDs (MIDs)
/// - Transport description generation
///
/// Reference: werift-webrtc/packages/webrtc/src/sdpManager.ts
class SdpManager {
  /// Current local description (after negotiation complete)
  SessionDescription? currentLocalDescription;

  /// Current remote description (after negotiation complete)
  SessionDescription? currentRemoteDescription;

  /// Pending local description (during negotiation)
  SessionDescription? pendingLocalDescription;

  /// Pending remote description (during negotiation)
  SessionDescription? pendingRemoteDescription;

  /// Canonical name for RTCP SDES
  final String cname;

  /// Bundle policy from RTCConfiguration
  final BundlePolicy bundlePolicy;

  /// Whether remote SDP uses bundling
  bool remoteIsBundled = false;

  /// Established m-line order (MIDs) after first negotiation.
  /// Used to preserve m-line order in subsequent offers per RFC 3264.
  List<String>? establishedMlineOrder;

  /// Set of allocated MIDs to prevent duplicates
  final Set<String> _seenMid = {};

  /// Next MID counter (starts at 1, 0 reserved for DataChannel)
  int _nextMidCounter = 1;

  SdpManager({
    required this.cname,
    this.bundlePolicy = BundlePolicy.maxCompat,
  });

  /// Get the effective local description (pending takes precedence)
  SessionDescription? get localDescriptionInternal =>
      pendingLocalDescription ?? currentLocalDescription;

  /// Get the effective remote description (pending takes precedence)
  SessionDescription? get remoteDescriptionInternal =>
      pendingRemoteDescription ?? currentRemoteDescription;

  /// Get local description as RTCSessionDescription for public API
  RTCSessionDescription? get localDescription {
    final desc = localDescriptionInternal;
    if (desc == null) return null;
    return RTCSessionDescription(
      type: desc.type,
      sdp: desc.sdp,
    );
  }

  /// Get remote description as RTCSessionDescription for public API
  RTCSessionDescription? get remoteDescription {
    final desc = remoteDescriptionInternal;
    if (desc == null) return null;
    return RTCSessionDescription(
      type: desc.type,
      sdp: desc.sdp,
    );
  }

  /// Allocate a unique MID for a new media section
  /// Matches werift: allocateMid(type)
  String allocateMid({String suffix = ''}) {
    String mid;
    while (true) {
      mid = '${_nextMidCounter++}$suffix';
      if (!_seenMid.contains(mid)) break;
    }
    _seenMid.add(mid);
    return mid;
  }

  /// Register an existing MID (e.g., from remote SDP)
  /// Matches werift: registerMid(mid)
  void registerMid(String mid) {
    _seenMid.add(mid);
  }

  /// Set local description and update pending/current state
  /// Matches werift: setLocalDescription(description)
  void setLocalDescription(SessionDescription description) {
    currentLocalDescription = description;
    if (description.type == 'answer') {
      pendingLocalDescription = null;
    } else {
      pendingLocalDescription = description;
    }
  }

  /// Set remote description and update pending/current state
  /// Returns the parsed SessionDescription
  /// Matches werift: setRemoteDescription(sessionDescription, signalingState)
  SessionDescription setRemoteDescription(
    RTCSessionDescription sessionDescription,
    SignalingState signalingState,
  ) {
    if (sessionDescription.sdp == null || sessionDescription.type == null) {
      throw StateError('Invalid sessionDescription: missing sdp or type');
    }

    // Create and validate
    final remoteSdp = createDescription(
      sdp: sessionDescription.sdp!,
      isLocal: false,
      signalingState: signalingState,
      type: sessionDescription.type!,
    );

    if (remoteSdp.type == 'answer') {
      currentRemoteDescription = remoteSdp;
      pendingRemoteDescription = null;
    } else {
      pendingRemoteDescription = remoteSdp;
    }

    return remoteSdp;
  }

  /// Create and validate a SessionDescription
  /// Matches werift: parseSdp({sdp, isLocal, signalingState, type})
  SessionDescription createDescription({
    required String sdp,
    required bool isLocal,
    required SignalingState signalingState,
    required String type,
  }) {
    final description = SessionDescription(type: type, sdp: sdp);
    validateDescription(
      description: description,
      isLocal: isLocal,
      signalingState: signalingState,
    );
    return description;
  }

  /// Validate description against signaling state machine
  /// Matches werift: validateDescription({description, isLocal, signalingState})
  void validateDescription({
    required SessionDescription description,
    required bool isLocal,
    required SignalingState signalingState,
  }) {
    if (isLocal) {
      if (description.type == 'offer') {
        if (signalingState != SignalingState.stable &&
            signalingState != SignalingState.haveLocalOffer) {
          throw StateError(
              'Cannot handle offer in signaling state: $signalingState');
        }
      } else if (description.type == 'answer') {
        if (signalingState != SignalingState.haveRemoteOffer &&
            signalingState != SignalingState.haveLocalPranswer) {
          throw StateError(
              'Cannot handle answer in signaling state: $signalingState');
        }
      }
    } else {
      if (description.type == 'offer') {
        if (signalingState != SignalingState.stable &&
            signalingState != SignalingState.haveRemoteOffer) {
          throw StateError(
              'Cannot handle offer in signaling state: $signalingState');
        }
      } else if (description.type == 'answer') {
        if (signalingState != SignalingState.haveLocalOffer &&
            signalingState != SignalingState.haveRemotePranswer) {
          throw StateError(
              'Cannot handle answer in signaling state: $signalingState');
        }
      }
    }
  }

  /// Validate local description can be set in current signaling state
  /// Returns true if valid, throws if invalid
  void validateSetLocalDescription(
    String type,
    SignalingState signalingState,
  ) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (signalingState) {
      case SignalingState.stable:
        if (type != 'offer') {
          throw StateError('Can only set offer in stable state');
        }
        break;
      case SignalingState.haveLocalOffer:
        if (type != 'offer') {
          throw StateError('Can only set offer in have-local-offer state');
        }
        break;
      case SignalingState.haveRemoteOffer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-remote-offer state',
          );
        }
        break;
      case SignalingState.haveLocalPranswer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-local-pranswer state',
          );
        }
        break;
      case SignalingState.haveRemotePranswer:
        throw StateError(
          'Cannot set local description in have-remote-pranswer state',
        );
      case SignalingState.closed:
        throw StateError('PeerConnection is closed');
    }
  }

  /// Validate remote description can be set in current signaling state
  /// Returns true if valid, throws if invalid
  void validateSetRemoteDescription(
    String type,
    SignalingState signalingState,
  ) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (signalingState) {
      case SignalingState.stable:
        if (type != 'offer') {
          throw StateError('Can only set offer in stable state');
        }
        break;
      case SignalingState.haveLocalOffer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-local-offer state',
          );
        }
        break;
      case SignalingState.haveRemoteOffer:
        if (type != 'offer') {
          throw StateError('Can only set offer in have-remote-offer state');
        }
        break;
      case SignalingState.haveLocalPranswer:
        throw StateError(
          'Cannot set remote description in have-local-pranswer state',
        );
      case SignalingState.haveRemotePranswer:
        if (type != 'answer' && type != 'pranswer') {
          throw StateError(
            'Can only set answer/pranswer in have-remote-pranswer state',
          );
        }
        break;
      case SignalingState.closed:
        throw StateError('PeerConnection is closed');
    }
  }
}

/// RTCSessionDescription - W3C WebRTC API compatible description
class RTCSessionDescription {
  final String? type;
  final String? sdp;

  const RTCSessionDescription({this.type, this.sdp});

  Map<String, String?> toJson() => {'type': type, 'sdp': sdp};

  @override
  String toString() => 'RTCSessionDescription(type: $type)';
}
