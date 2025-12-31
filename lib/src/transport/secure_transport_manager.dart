import 'dart:async';

import 'package:logging/logging.dart';

import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';
import 'package:webrtc_dart/src/transport/transport.dart';
import 'package:webrtc_dart/src/peer_connection.dart'
    show PeerConnectionState, IceConnectionState, IceGatheringState;

/// SecureTransportManager handles ICE/DTLS/SRTP transport lifecycle.
///
/// This class matches the architecture of werift-webrtc's SecureTransportManager,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Managing SRTP sessions (bundled and per-transport)
/// - Aggregate connection state from multiple transports
/// - ICE connection lookup by MID
/// - State aggregation and event emission
///
/// Reference: werift-webrtc/packages/webrtc/src/secureTransportManager.ts
class SecureTransportManager {
  final Logger _log = Logger('SecureTransportManager');

  // ============================================================
  // State Properties (matching werift SecureTransportManager)
  // ============================================================

  /// Aggregated connection state from all DTLS transports
  PeerConnectionState _connectionState = PeerConnectionState.new_;

  /// Aggregated ICE connection state from all ICE transports
  IceConnectionState _iceConnectionState = IceConnectionState.new_;

  /// Aggregated ICE gathering state from all ICE gatherers
  IceGatheringState _iceGatheringState = IceGatheringState.new_;

  /// Get current connection state
  PeerConnectionState get connectionState => _connectionState;

  /// Get current ICE connection state
  IceConnectionState get iceConnectionState => _iceConnectionState;

  /// Get current ICE gathering state
  IceGatheringState get iceGatheringState => _iceGatheringState;

  // ============================================================
  // Event Streams (matching werift SecureTransportManager)
  // ============================================================

  final _connectionStateController =
      StreamController<PeerConnectionState>.broadcast();
  final _iceConnectionStateController =
      StreamController<IceConnectionState>.broadcast();
  final _iceGatheringStateController =
      StreamController<IceGatheringState>.broadcast();

  /// Stream of connection state changes
  Stream<PeerConnectionState> get onConnectionStateChange =>
      _connectionStateController.stream;

  /// Stream of ICE connection state changes
  Stream<IceConnectionState> get onIceConnectionStateChange =>
      _iceConnectionStateController.stream;

  /// Stream of ICE gathering state changes
  Stream<IceGatheringState> get onIceGatheringStateChange =>
      _iceGatheringStateController.stream;

  // ============================================================
  // SRTP Session Management (existing functionality)
  // ============================================================

  /// Primary SRTP session for bundled media
  SrtpSession? _srtpSession;

  /// Per-transport SRTP sessions for bundlePolicy:disable
  final Map<String, SrtpSession> _srtpSessionsByMid = {};

  /// Get primary SRTP session
  SrtpSession? get srtpSession => _srtpSession;

  /// Get SRTP session for a specific MID
  SrtpSession? getSrtpSessionForMid(String mid) {
    return _srtpSessionsByMid[mid] ?? _srtpSession;
  }

  /// Check if SRTP session exists for a MID
  bool hasSrtpSessionForMid(String mid) {
    return _srtpSessionsByMid.containsKey(mid);
  }

  /// Set up SRTP sessions for all RTP sessions once DTLS is connected (bundled mode).
  ///
  /// [transport] - The integrated transport with DTLS socket
  /// [rtpSessions] - Map of MID to RTP session
  void setupSrtpSessions(
    IntegratedTransport? transport,
    Map<String, RtpSession> rtpSessions,
  ) {
    _log.fine('setupSrtpSessions called, rtpSessions.length=${rtpSessions.length}');

    final dtlsSocket = transport?.dtlsSocket;
    if (dtlsSocket == null) {
      _log.fine('setupSrtpSessions: dtlsSocket is null');
      return;
    }

    final srtpSession = _createSrtpSessionFromDtls(dtlsSocket);
    if (srtpSession == null) {
      return;
    }

    // Store at manager level for use in decryption
    _srtpSession = srtpSession;
    _log.fine('Created SRTP session, applying to ${rtpSessions.length} RTP sessions');

    // Apply SRTP session to all RTP sessions
    for (final entry in rtpSessions.entries) {
      _log.fine('Applying SRTP to RTP session for mid=${entry.key}');
      entry.value.srtpSession = srtpSession;
    }
  }

  /// Set up SRTP sessions for all media transports (bundlePolicy:disable mode).
  ///
  /// [mediaTransports] - Map of MID to MediaTransport
  /// [rtpSessions] - Map of MID to RTP session
  /// [getMidsForTransport] - Callback to get MIDs using a transport
  void setupSrtpSessionsForAllTransports(
    Map<String, MediaTransport> mediaTransports,
    Map<String, RtpSession> rtpSessions,
    List<String> Function(String transportId) getMidsForTransport,
  ) {
    for (final transport in mediaTransports.values) {
      final dtlsSocket = transport.dtlsSocket;
      if (dtlsSocket == null) continue;

      final srtpSession = _createSrtpSessionFromDtls(dtlsSocket);
      if (srtpSession == null) continue;

      // Store SRTP session by transport ID (MID)
      _srtpSessionsByMid[transport.id] = srtpSession;
      _log.fine('SRTP session created for transport ${transport.id}');

      // Find transceivers using this transport and update their SRTP sessions
      final mids = getMidsForTransport(transport.id);
      for (final mid in mids) {
        final rtpSession = rtpSessions[mid];
        if (rtpSession != null) {
          rtpSession.srtpSession = srtpSession;
        }
      }
    }
  }

  /// Set up SRTP session for a single media transport when it becomes connected.
  /// Critical for bundlePolicy:disable where transports connect independently.
  ///
  /// [transport] - The media transport that just connected
  /// [rtpSessions] - Map of MID to RTP session
  /// [getMidsForTransport] - Callback to get MIDs using a transport
  void setupSrtpSessionForTransport(
    MediaTransport transport,
    Map<String, RtpSession> rtpSessions,
    List<String> Function(String transportId) getMidsForTransport,
  ) {
    // Skip if already set up
    if (_srtpSessionsByMid.containsKey(transport.id)) {
      return;
    }

    final dtlsSocket = transport.dtlsSocket;
    if (dtlsSocket == null) return;

    final srtpSession = _createSrtpSessionFromDtls(dtlsSocket);
    if (srtpSession == null) {
      _log.fine('SRTP keys not available for transport ${transport.id}');
      return;
    }

    // Store SRTP session by transport ID (MID)
    _srtpSessionsByMid[transport.id] = srtpSession;
    _log.fine('SRTP session created for transport ${transport.id} (per-transport setup)');

    // Find transceivers using this transport and update their SRTP sessions
    final mids = getMidsForTransport(transport.id);
    for (final mid in mids) {
      final rtpSession = rtpSessions[mid];
      if (rtpSession != null) {
        rtpSession.srtpSession = srtpSession;
        _log.fine('Assigned SRTP session to RTP session for mid=$mid');
      }
    }
  }

  /// Get ICE connection for sending RTP/RTCP packets for a given MID.
  /// For bundlePolicy:disable, returns the transport specific to this MID.
  /// For bundled connections, returns the primary transport.
  ///
  /// [mid] - Media ID
  /// [mediaTransports] - Map of MID to MediaTransport
  /// [primaryTransport] - Fallback transport for bundled case
  IceConnection? getIceConnectionForMid(
    String mid,
    Map<String, MediaTransport> mediaTransports,
    IntegratedTransport? primaryTransport,
  ) {
    // First check for media transport (bundlePolicy:disable case)
    final mediaTransport = mediaTransports[mid];
    if (mediaTransport != null) {
      return mediaTransport.iceConnection;
    }
    // Fall back to primary transport (bundled case)
    return primaryTransport?.iceConnection;
  }

  /// Create SRTP session from DTLS socket context.
  /// Returns null if keying material is not yet available.
  SrtpSession? _createSrtpSessionFromDtls(DtlsSocket dtlsSocket) {
    final srtpContext = dtlsSocket.srtpContext;

    // Check if keying material is available
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      _log.fine(
          'SRTP keys not available - localKey=${srtpContext.localMasterKey != null}, '
          'localSalt=${srtpContext.localMasterSalt != null}, '
          'remoteKey=${srtpContext.remoteMasterKey != null}, '
          'remoteSalt=${srtpContext.remoteMasterSalt != null}, '
          'profile=${srtpContext.profile}');
      return null;
    }

    return SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );
  }

  // ============================================================
  // State Aggregation Methods (matching werift SecureTransportManager)
  // ============================================================

  /// Update ICE gathering state from multiple ICE transports.
  /// Reference: werift SecureTransportManager.updateIceGatheringState
  ///
  /// [gatheringStates] - List of gathering states from all ICE transports
  void updateIceGatheringState(List<IceGathererState> gatheringStates) {
    if (gatheringStates.isEmpty) {
      return;
    }

    IceGatheringState newState;

    // All complete → complete
    if (gatheringStates.every((s) => s == IceGathererState.complete)) {
      newState = IceGatheringState.complete;
    }
    // Any gathering → gathering
    else if (gatheringStates.any((s) => s == IceGathererState.gathering)) {
      newState = IceGatheringState.gathering;
    }
    // Default → new
    else {
      newState = IceGatheringState.new_;
    }

    if (_iceGatheringState != newState) {
      _log.fine('ICE gathering state: $_iceGatheringState -> $newState');
      _iceGatheringState = newState;
      if (!_iceGatheringStateController.isClosed) {
        _iceGatheringStateController.add(newState);
      }
    }
  }

  /// Update ICE connection state from multiple ICE transports.
  /// Reference: werift SecureTransportManager.updateIceConnectionState
  /// https://w3c.github.io/webrtc-pc/#dom-rtciceconnectionstate
  ///
  /// [iceStates] - List of ICE connection states from all transports
  void updateIceConnectionState(List<IceState> iceStates) {
    if (iceStates.isEmpty) {
      return;
    }

    IceConnectionState newState;

    // Helper functions
    bool allMatch(List<IceState> states) {
      return iceStates.every((s) => states.contains(s));
    }

    bool anyMatch(List<IceState> states) {
      return iceStates.any((s) => states.contains(s));
    }

    // Aggregation logic per W3C spec
    if (_connectionState == PeerConnectionState.closed) {
      newState = IceConnectionState.closed;
    } else if (anyMatch([IceState.failed])) {
      newState = IceConnectionState.failed;
    } else if (anyMatch([IceState.disconnected])) {
      newState = IceConnectionState.disconnected;
    } else if (allMatch([IceState.newState, IceState.closed])) {
      newState = IceConnectionState.new_;
    } else if (anyMatch([IceState.newState, IceState.checking])) {
      newState = IceConnectionState.checking;
    } else if (allMatch([IceState.completed, IceState.closed])) {
      newState = IceConnectionState.completed;
    } else if (allMatch([IceState.connected, IceState.completed, IceState.closed])) {
      newState = IceConnectionState.connected;
    } else {
      newState = IceConnectionState.new_;
    }

    if (_iceConnectionState != newState) {
      _log.fine('ICE connection state: $_iceConnectionState -> $newState');
      _iceConnectionState = newState;
      if (!_iceConnectionStateController.isClosed) {
        _iceConnectionStateController.add(newState);
      }
    }
  }

  /// Update connection state from multiple transport states.
  /// Reference: werift SecureTransportManager.setConnectionState
  ///
  /// [transportStates] - List of transport states from all transports
  void updateConnectionState(List<TransportState> transportStates) {
    if (transportStates.isEmpty) {
      return;
    }

    PeerConnectionState newState;

    // Aggregation logic
    if (transportStates.any((s) => s == TransportState.failed)) {
      newState = PeerConnectionState.failed;
    } else if (transportStates.any((s) => s == TransportState.disconnected)) {
      newState = PeerConnectionState.disconnected;
    } else if (transportStates.any((s) => s == TransportState.connected)) {
      newState = PeerConnectionState.connected;
    } else if (transportStates.any((s) => s == TransportState.connecting)) {
      newState = PeerConnectionState.connecting;
    } else if (transportStates.every((s) => s == TransportState.closed)) {
      newState = PeerConnectionState.closed;
    } else {
      newState = PeerConnectionState.new_;
    }

    if (_connectionState != newState) {
      _log.fine('Connection state: $_connectionState -> $newState');
      _connectionState = newState;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(newState);
      }
    }
  }

  /// Set connection state directly (e.g., when closing).
  /// Reference: werift SecureTransportManager.setConnectionState
  void setConnectionState(PeerConnectionState state) {
    if (_connectionState != state) {
      _log.fine('Connection state (direct): $_connectionState -> $state');
      _connectionState = state;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
      }
    }
  }

  /// Set ICE connection state directly (for single transport case).
  void setIceConnectionState(IceConnectionState state) {
    if (_iceConnectionState != state) {
      _log.fine('ICE connection state (direct): $_iceConnectionState -> $state');
      _iceConnectionState = state;
      if (!_iceConnectionStateController.isClosed) {
        _iceConnectionStateController.add(state);
      }
    }
  }

  /// Set ICE gathering state directly (for single transport case).
  void setIceGatheringState(IceGatheringState state) {
    if (_iceGatheringState != state) {
      _log.fine('ICE gathering state (direct): $_iceGatheringState -> $state');
      _iceGatheringState = state;
      if (!_iceGatheringStateController.isClosed) {
        _iceGatheringStateController.add(state);
      }
    }
  }

  // ============================================================
  // Cleanup
  // ============================================================

  /// Close the manager and release resources.
  Future<void> close() async {
    setConnectionState(PeerConnectionState.closed);

    _srtpSession = null;
    _srtpSessionsByMid.clear();

    await _connectionStateController.close();
    await _iceConnectionStateController.close();
    await _iceGatheringStateController.close();
  }
}
