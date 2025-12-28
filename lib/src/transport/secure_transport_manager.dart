import 'package:logging/logging.dart';

import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/transport/transport.dart';

/// SecureTransportManager handles ICE/DTLS/SRTP transport lifecycle.
///
/// This class matches the architecture of werift-webrtc's SecureTransportManager,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Managing SRTP sessions (bundled and per-transport)
/// - Aggregate connection state from multiple transports
/// - ICE connection lookup by MID
/// - Transport state callbacks
///
/// Reference: werift-webrtc/packages/webrtc/src/secureTransportManager.ts
class SecureTransportManager {
  final Logger _log = Logger('SecureTransportManager');

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

  /// Close the manager and release resources.
  void close() {
    _srtpSession = null;
    _srtpSessionsByMid.clear();
  }
}
