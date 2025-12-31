import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/dtls_transport.dart' show DtlsRole;
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/ice/mdns.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/rtp_router.dart';
import 'package:webrtc_dart/src/media/rtp_transceiver.dart';
import 'package:webrtc_dart/src/media/transceiver_manager.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;
import 'package:webrtc_dart/src/sctp/sctp_transport_manager.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/sdp/sdp_manager.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';
import 'package:webrtc_dart/src/transport/secure_transport_manager.dart';
import 'package:webrtc_dart/src/transport/transport.dart';

final _log = WebRtcLogging.pc;

/// RTCPeerConnection State
enum PeerConnectionState {
  new_,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// RTCSignalingState
enum SignalingState {
  stable,
  haveLocalOffer,
  haveRemoteOffer,
  haveLocalPranswer,
  haveRemotePranswer,
  closed,
}

/// RTCIceConnectionState
enum IceConnectionState {
  new_,
  checking,
  connected,
  completed,
  failed,
  disconnected,
  closed,
}

/// RTCIceGatheringState
enum IceGatheringState { new_, gathering, complete }

/// Codec configuration for RTCPeerConnection
/// Matches TypeScript werift's Partial<{ audio: RTCRtpCodecParameters[]; video: RTCRtpCodecParameters[]; }>
class RtcCodecs {
  /// Audio codecs to use
  final List<RtpCodecParameters>? audio;

  /// Video codecs to use
  final List<RtpCodecParameters>? video;

  const RtcCodecs({this.audio, this.video});
}

/// Default ICE servers (matching TypeScript werift)
const _defaultIceServers = [
  IceServer(urls: ['stun:stun.l.google.com:19302']),
];

/// RTCConfiguration
class RtcConfiguration {
  /// ICE servers
  final List<IceServer> iceServers;

  /// ICE transport policy
  final IceTransportPolicy iceTransportPolicy;

  /// Bundle policy - controls how media is bundled over transports
  final BundlePolicy bundlePolicy;

  /// Codecs to use for audio/video (matching TypeScript werift)
  final RtcCodecs codecs;

  const RtcConfiguration({
    this.iceServers = _defaultIceServers,
    this.iceTransportPolicy = IceTransportPolicy.all,
    this.bundlePolicy = BundlePolicy.maxCompat,
    this.codecs = const RtcCodecs(),
  });
}

/// ICE Server
class IceServer {
  final List<String> urls;
  final String? username;
  final String? credential;

  const IceServer({required this.urls, this.username, this.credential});
}

/// ICE Transport Policy
enum IceTransportPolicy { relay, all }

/// Bundle Policy
/// Controls how media is bundled over the same transport
enum BundlePolicy {
  /// All media will be bundled on a single transport
  maxBundle,

  /// Media will be bundled if possible, but each media section has its own transport
  maxCompat,

  /// Each media section will have its own transport (no BUNDLE group in SDP)
  disable,
}

/// Options for createOffer
class RtcOfferOptions {
  /// If true, triggers an ICE restart by generating new credentials
  final bool iceRestart;

  const RtcOfferOptions({this.iceRestart = false});
}

/// RTCPeerConnection
/// WebRTC Peer Connection API
/// Based on W3C WebRTC 1.0 specification
class RtcPeerConnection {
  /// Configuration (mutable via setConfiguration)
  RtcConfiguration _configuration;

  /// Current signaling state
  SignalingState _signalingState = SignalingState.stable;

  /// Current connection state
  PeerConnectionState _connectionState = PeerConnectionState.new_;

  /// Current ICE connection state
  IceConnectionState _iceConnectionState = IceConnectionState.new_;

  /// Current ICE gathering state
  IceGatheringState _iceGatheringState = IceGatheringState.new_;

  /// Track if we've started ICE connectivity checks
  bool _iceConnectCalled = false;

  /// Flag indicating ICE restart is needed
  bool _needsIceRestart = false;

  /// Previous remote ICE credentials (for detecting remote ICE restart)
  String? _previousRemoteIceUfrag;
  String? _previousRemoteIcePwd;

  /// Local description
  SessionDescription? _localDescription;

  /// Remote description
  SessionDescription? _remoteDescription;

  /// ICE connection (primary, for bundled media)
  late final IceConnection _iceConnection;

  /// SDP manager for description state and SDP building
  late final SdpManager _sdpManager;

  /// ICE controlling role (true if this peer created the offer)
  bool _iceControlling = false;

  /// Integrated transport (ICE + DTLS + SCTP) - for bundled media and DataChannel
  IntegratedTransport? _transport;

  /// Media transports (for bundlePolicy: disable, one per media line)
  final Map<String, MediaTransport> _mediaTransports = {};

  /// Whether remote SDP uses bundling
  bool _remoteIsBundled = false;

  /// Server certificate for DTLS
  CertificateKeyPair? _certificate;

  /// ICE candidate stream controller
  final StreamController<Candidate> _iceCandidateController =
      StreamController.broadcast();

  /// Connection state change stream controller
  final StreamController<PeerConnectionState> _connectionStateController =
      StreamController.broadcast();

  /// ICE connection state change stream controller
  final StreamController<IceConnectionState> _iceConnectionStateController =
      StreamController.broadcast();

  /// ICE gathering state change stream controller
  final StreamController<IceGatheringState> _iceGatheringStateController =
      StreamController.broadcast();

  /// SCTP transport manager for DataChannel lifecycle
  final SctpTransportManager _sctpManager = SctpTransportManager();

  /// Track event stream controller
  final StreamController<RtpTransceiver> _trackController =
      StreamController.broadcast();

  /// Negotiation needed event stream controller
  /// Fires when the session needs renegotiation (transceiver added, track changed, etc.)
  final StreamController<void> _negotiationNeededController =
      StreamController.broadcast();

  /// Flag to prevent multiple negotiation needed events during batch operations
  bool _negotiationNeededPending = false;

  /// Transceiver manager for RTP transceiver lifecycle
  final TransceiverManager _transceiverManager = TransceiverManager();

  /// List of RTP transceivers (delegating to TransceiverManager)
  List<RtpTransceiver> get _transceivers => _transceiverManager.transceivers;

  /// Established m-line order (MIDs) after first negotiation.
  /// Used to preserve m-line order in subsequent offers per RFC 3264.
  List<String>? _establishedMlineOrder;

  /// RTP sessions by MID
  final Map<String, RtpSession> _rtpSessions = {};

  /// RTP router for SSRC-based packet routing (matching werift: packages/webrtc/src/media/router.ts)
  final RtpRouter _rtpRouter = RtpRouter();

  /// RTX SSRC mapping by MID (original SSRC -> RTX SSRC)
  final Map<String, int> _rtxSsrcByMid = {};

  /// Secure transport manager for SRTP session lifecycle
  final SecureTransportManager _secureManager = SecureTransportManager();

  /// Random number generator for SSRC
  final Random _random = Random.secure();

  /// Next MID counter
  /// Starts at 1 because MID 0 is reserved for DataChannel (SCTP)
  int _nextMid = 1;

  /// Default extension ID for sdes:mid header extension
  /// Standard browsers typically use ID 1 for mid
  static const int _midExtensionId = 1;

  /// Default extension ID for abs-send-time header extension
  /// Chrome typically uses ID 2 for abs-send-time
  static const int _absSendTimeExtensionId = 2;

  /// Default extension ID for transport-wide-cc header extension
  /// Chrome typically uses ID 4 for transport-wide-cc
  static const int _twccExtensionId = 4;

  /// Debug label for this peer connection
  static int _instanceCounter = 0;
  late final String _debugLabel;

  /// Future that completes when async initialization is done
  late final Future<void> _initializationComplete;

  /// Wait for the peer connection to complete async initialization.
  /// Call this before createDataChannel if you need to create channels
  /// immediately after constructing the PeerConnection.
  Future<void> waitForReady() => _initializationComplete;

  RtcPeerConnection([RtcConfiguration configuration = const RtcConfiguration()])
      : _configuration = configuration {
    _debugLabel = 'PC${++_instanceCounter}';

    // Convert configuration to IceOptions
    final iceOptions = _configToIceOptions(_configuration);

    _iceConnection = IceConnectionImpl(
      iceControlling: _iceControlling,
      options: iceOptions,
    );

    // Initialize SDP manager with ICE ufrag as cname
    _sdpManager = SdpManager(
      cname: _iceConnection.localUsername,
      bundlePolicy: _configuration.bundlePolicy,
    );

    // Setup ICE candidate listener
    _iceConnection.onIceCandidate.listen((candidate) {
      _iceCandidateController.add(candidate);
    });

    // Setup ICE state change listener
    _iceConnection.onStateChanged.listen(_handleIceStateChange);

    // Initialize asynchronously and store the future
    _initializationComplete = _initializeAsync();
  }

  /// Initialize async components (certificate generation, transport setup)
  Future<void> _initializeAsync() async {
    // Generate DTLS certificate
    _certificate = await generateSelfSignedCertificate(
      info: CertificateInfo(commonName: 'WebRTC'),
    );

    // Create integrated transport
    _transport = IntegratedTransport(
      iceConnection: _iceConnection,
      serverCertificate: _certificate,
      debugLabel: _debugLabel,
    );

    // Forward transport state changes to connection state
    _transport!.onStateChange.listen((state) {
      switch (state) {
        case TransportState.new_:
          // Keep current state
          break;
        case TransportState.connecting:
          _setConnectionState(PeerConnectionState.connecting);
          break;
        case TransportState.connected:
          // Set up SRTP for all RTP sessions BEFORE notifying connected state
          // This ensures SRTP is ready when onConnectionStateChange fires
          _setupSrtpSessions();
          _setConnectionState(PeerConnectionState.connected);
          break;
        case TransportState.disconnected:
          _setConnectionState(PeerConnectionState.disconnected);
          break;
        case TransportState.failed:
          _setConnectionState(PeerConnectionState.failed);
          break;
        case TransportState.closed:
          _setConnectionState(PeerConnectionState.closed);
          break;
      }
    });

    // Forward incoming data channels to SCTP manager
    _transport!.onDataChannel.listen((channel) {
      _sctpManager.registerRemoteChannel(channel);
    });

    // Handle incoming RTP/RTCP packets (already decrypted by transport)
    _transport!.onRtp.listen((packet) {
      _routeDecryptedRtp(packet);
    });
    _transport!.onRtcp.listen((data) {
      _routeDecryptedRtcp(data);
    });
  }

  /// Convert RtcConfiguration to IceOptions
  static IceOptions _configToIceOptions(RtcConfiguration config) {
    (String, int)? stunServer;
    (String, int)? turnServer;
    String? turnUsername;
    String? turnPassword;

    for (final server in config.iceServers) {
      for (final url in server.urls) {
        // Parse ICE URLs: stun:host:port or turn:host:port
        // Add // after scheme for Uri.parse() compatibility
        final normalized =
            url.contains('://') ? url : url.replaceFirst(':', '://');
        final uri = Uri.tryParse(normalized.split('?').first);
        if (uri == null || uri.host.isEmpty) continue;

        final scheme = uri.scheme;
        final host = uri.host;
        final port = uri.hasPort ? uri.port : null;

        if (scheme == 'stun' && stunServer == null) {
          stunServer = (host, port ?? 3478);
        } else if ((scheme == 'turn' || scheme == 'turns') &&
            turnServer == null) {
          turnServer = (host, port ?? (scheme == 'turns' ? 443 : 3478));
          turnUsername = server.username;
          turnPassword = server.credential;
        }
      }
    }

    return IceOptions(
      stunServer: stunServer,
      turnServer: turnServer,
      turnUsername: turnUsername,
      turnPassword: turnPassword,
      relayOnly: config.iceTransportPolicy == IceTransportPolicy.relay,
    );
  }

  /// Get signaling state
  SignalingState get signalingState => _signalingState;

  /// Get connection state
  PeerConnectionState get connectionState => _connectionState;

  /// Get ICE connection state
  IceConnectionState get iceConnectionState => _iceConnectionState;

  /// Get ICE gathering state
  IceGatheringState get iceGatheringState => _iceGatheringState;

  /// Get local description
  SessionDescription? get localDescription => _localDescription;

  /// Get remote description
  SessionDescription? get remoteDescription => _remoteDescription;

  /// Stream of ICE candidates
  Stream<Candidate> get onIceCandidate => _iceCandidateController.stream;

  /// Stream of connection state changes
  Stream<PeerConnectionState> get onConnectionStateChange =>
      _connectionStateController.stream;

  /// Stream of ICE connection state changes
  Stream<IceConnectionState> get onIceConnectionStateChange =>
      _iceConnectionStateController.stream;

  /// Stream of ICE gathering state changes
  Stream<IceGatheringState> get onIceGatheringStateChange =>
      _iceGatheringStateController.stream;

  /// Stream of data channels
  Stream<DataChannel> get onDataChannel => _sctpManager.onDataChannel;

  /// Stream of negotiation needed events
  ///
  /// Fires when the session needs renegotiation, such as when:
  /// - A transceiver is added via addTransceiver()
  /// - A track is added via addTrack()
  /// - A transceiver's direction is changed
  /// - ICE restart is needed
  ///
  /// Applications should respond by calling createOffer() and starting
  /// a new offer/answer exchange.
  Stream<void> get onNegotiationNeeded => _negotiationNeededController.stream;

  /// Get the current configuration
  ///
  /// Returns a copy of the current RTCConfiguration.
  RtcConfiguration getConfiguration() => _configuration;

  /// Update the configuration
  ///
  /// Allows updating ICE servers and other configuration options after
  /// the PeerConnection has been created. This is useful for:
  /// - Updating TURN server credentials that may have expired
  /// - Switching to different ICE servers
  /// - Changing ICE transport policy
  ///
  /// Note: Changes to ICE servers will only take effect on the next
  /// ICE restart. Call restartIce() after setConfiguration() to apply
  /// new ICE server changes immediately.
  ///
  /// [config] - The new configuration to apply. Fields not specified
  ///            will retain their current values.
  void setConfiguration(RtcConfiguration config) {
    _configuration = config;

    // Update ICE connection with new configuration
    final iceOptions = _configToIceOptions(_configuration);
    _iceConnection.updateOptions(iceOptions);
  }

  /// Create an offer
  ///
  /// [options] - Optional configuration for the offer:
  ///   - iceRestart: If true, generates new ICE credentials for ICE restart
  Future<SessionDescription> createOffer([RtcOfferOptions? options]) async {
    // Wait for async initialization (certificate generation) to complete
    await _initializationComplete;

    if (_signalingState != SignalingState.stable &&
        _signalingState != SignalingState.haveLocalOffer) {
      throw StateError('Cannot create offer in state $_signalingState');
    }

    // Handle ICE restart
    if (options?.iceRestart == true || _needsIceRestart) {
      _needsIceRestart = false;
      await _iceConnection.restart();
      _iceConnectCalled = false;
      _setIceGatheringState(IceGatheringState.new_);
      _log.fine('[$_debugLabel] ICE restart: new credentials generated');
    }

    // Set ICE controlling role (offerer is controlling)
    _iceControlling = true;
    _iceConnection.iceControlling = true;

    // Generate DTLS fingerprint from certificate
    final dtlsFingerprint = _certificate != null
        ? computeCertificateFingerprint(_certificate!.certificate)
        : 'sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00'; // fallback for tests

    // Build offer SDP using SdpManager
    return _sdpManager.buildOfferSdp(
      transceivers: _transceivers,
      iceUfrag: _iceConnection.localUsername,
      icePwd: _iceConnection.localPassword,
      dtlsFingerprint: dtlsFingerprint,
      rtxSsrcByMid: _rtxSsrcByMid,
      generateSsrc: _generateSsrc,
      midExtensionId: _midExtensionId,
    );
  }

  /// Create an answer
  Future<SessionDescription> createAnswer() async {
    // Wait for async initialization (certificate generation) to complete
    await _initializationComplete;

    if (_signalingState != SignalingState.haveRemoteOffer &&
        _signalingState != SignalingState.haveLocalPranswer) {
      throw StateError('Cannot create answer in state $_signalingState');
    }

    if (_remoteDescription == null) {
      throw StateError('No remote description set');
    }

    // Parse remote SDP
    final remoteSdp = _remoteDescription!.parse();

    // Generate DTLS fingerprint from certificate
    final dtlsFingerprint = _certificate != null
        ? computeCertificateFingerprint(_certificate!.certificate)
        : 'sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00'; // fallback for tests

    // Build answer SDP using SdpManager
    return _sdpManager.buildAnswerSdp(
      remoteSdp: remoteSdp,
      transceivers: _transceivers,
      iceUfrag: _iceConnection.localUsername,
      icePwd: _iceConnection.localPassword,
      dtlsFingerprint: dtlsFingerprint,
      rtxSsrcByMid: _rtxSsrcByMid,
      generateSsrc: _generateSsrc,
    );
  }

  /// Set local description
  Future<void> setLocalDescription(SessionDescription description) async {
    // Validate state transition
    _sdpManager.validateSetLocalDescription(description.type, _signalingState);

    _localDescription = description;

    // Update signaling state
    switch (description.type) {
      case 'offer':
        _setSignalingState(SignalingState.haveLocalOffer);
        break;
      case 'answer':
        _setSignalingState(SignalingState.stable);
        break;
      case 'pranswer':
        _setSignalingState(SignalingState.haveLocalPranswer);
        break;
      case 'rollback':
        _setSignalingState(SignalingState.stable);
        _localDescription = null;
        return;
    }

    // ICE credentials are already set during construction
    // SDP parsing can be added here if needed in the future

    // Start ICE gathering on primary connection (but NOT for bundlePolicy:disable)
    // For bundlePolicy:disable, MediaTransports gather below
    if (_iceGatheringState == IceGatheringState.new_ &&
        _configuration.bundlePolicy != BundlePolicy.disable) {
      _setIceGatheringState(IceGatheringState.gathering);
      await _iceConnection.gatherCandidates();
      _setIceGatheringState(IceGatheringState.complete);
    }

    // For bundlePolicy:disable offerer case, create MediaTransports from local SDP
    // This handles: createOffer, setLocalDescription(offer) - before receiving answer
    if (_configuration.bundlePolicy == BundlePolicy.disable &&
        description.type == 'offer' &&
        _mediaTransports.isEmpty) {
      // Parse the local offer to extract media line info
      final sdpLines = description.sdp.split('\n');
      var mLineIndex = 0;
      for (final line in sdpLines) {
        if (line.startsWith('m=audio') || line.startsWith('m=video')) {
          // Find the MID for this media line
          final midIndex = sdpLines.indexOf(line);
          String? mid;
          for (var i = midIndex + 1; i < sdpLines.length; i++) {
            if (sdpLines[i].startsWith('m=')) break;
            if (sdpLines[i].startsWith('a=mid:')) {
              mid = sdpLines[i].substring(6).trim();
              break;
            }
          }
          if (mid != null) {
            _log.fine(
                '[$_debugLabel] Creating MediaTransport for offerer: mid=$mid, mLineIndex=$mLineIndex');
            await _findOrCreateMediaTransport(mid, mLineIndex);
          }
          mLineIndex++;
        }
      }

      // Start gathering on all MediaTransports for the offerer
      if (_mediaTransports.isNotEmpty) {
        _setIceGatheringState(IceGatheringState.gathering);
        await Future.wait(_mediaTransports.values.map((transport) async {
          try {
            await transport.iceConnection.gatherCandidates();
          } catch (e) {
            _log.fine(
                '[$_debugLabel] Transport ${transport.id} gather error: $e');
          }
        }));
        _setIceGatheringState(IceGatheringState.complete);
      }
    }

    // For bundlePolicy:disable answerer case, start MediaTransport ICE
    // This handles: setRemoteDescription, createAnswer, setLocalDescription(answer)
    if (_configuration.bundlePolicy == BundlePolicy.disable &&
        _remoteDescription != null &&
        _mediaTransports.isNotEmpty &&
        !_iceConnectCalled) {
      _setConnectionState(PeerConnectionState.connecting);
      _iceConnectCalled = true;
      _log.fine(
          '[$_debugLabel] Starting ${_mediaTransports.length} media transports (from setLocalDescription)');
      // Start all media transports in parallel (don't await - run in background)
      Future.wait(_mediaTransports.values.map((transport) async {
        try {
          await transport.iceConnection.gatherCandidates();
          await transport.iceConnection.connect();
        } catch (e) {
          _log.fine(
              '[$_debugLabel] Transport ${transport.id} connect error: $e');
        }
      }));
    }

    // If we now have both local and remote descriptions, start connecting
    // Note: ICE connect runs asynchronously - don't await it here
    // This allows the signaling to complete while ICE runs in background
    // Skip for bundlePolicy:disable - MediaTransports connect separately
    if (_localDescription != null &&
        _remoteDescription != null &&
        !_iceConnectCalled &&
        _configuration.bundlePolicy != BundlePolicy.disable) {
      _iceConnectCalled = true;
      // Start ICE connectivity checks in background
      _iceConnection.connect().catchError((e) {
        _log.fine('[$_debugLabel] ICE connect error: $e');
      });
    }
  }

  /// Set remote description
  Future<void> setRemoteDescription(SessionDescription description) async {
    // Validate state transition
    _sdpManager.validateSetRemoteDescription(description.type, _signalingState);

    _remoteDescription = description;

    // Update signaling state
    switch (description.type) {
      case 'offer':
        _setSignalingState(SignalingState.haveRemoteOffer);
        break;
      case 'answer':
        _setSignalingState(SignalingState.stable);
        // Capture m-line order from our local offer for future offers (RFC 3264)
        if (_establishedMlineOrder == null && _localDescription != null) {
          final localSdp = _localDescription!.parse();
          _establishedMlineOrder = localSdp.mediaDescriptions
              .map((m) => m.getAttributeValue('mid') ?? '')
              .where((mid) => mid.isNotEmpty)
              .toList();
          _log.fine(
              '[$_debugLabel] Captured m-line order: $_establishedMlineOrder');
        }
        break;
      case 'pranswer':
        _setSignalingState(SignalingState.haveRemotePranswer);
        break;
      case 'rollback':
        _setSignalingState(SignalingState.stable);
        _remoteDescription = null;
        return;
    }

    // Parse SDP to extract ICE credentials
    final sdpMessage = description.parse();

    // Check if remote uses BUNDLE
    _remoteIsBundled = sdpMessage.attributes.any(
      (a) =>
          a.key == 'group' && a.value != null && a.value!.startsWith('BUNDLE'),
    );
    _log.fine(
        '[$_debugLabel] Remote is bundled: $_remoteIsBundled, bundlePolicy: ${_configuration.bundlePolicy}');

    final isIceLite = sdpMessage.isIceLite;

    // Process each media line
    // When bundlePolicy is disable, each media line has its own ICE/DTLS transport
    for (var i = 0; i < sdpMessage.mediaDescriptions.length; i++) {
      final media = sdpMessage.mediaDescriptions[i];
      final mid = media.getAttributeValue('mid') ?? '$i';
      final iceUfrag = media.getAttributeValue('ice-ufrag');
      final icePwd = media.getAttributeValue('ice-pwd');
      final setup = media.getAttributeValue('setup');

      _log.fine(
          '[$_debugLabel] Media[$i] mid=$mid type=${media.type} ufrag=${iceUfrag != null && iceUfrag.length > 8 ? '${iceUfrag.substring(0, 8)}...' : iceUfrag}');

      // Determine which transport to use
      // When bundlePolicy is disable, ALWAYS use per-media transports
      // (regardless of whether remote is bundled) - matches werift behavior
      if (_configuration.bundlePolicy == BundlePolicy.disable) {
        // Each media line gets its own transport
        if (media.type == 'audio' || media.type == 'video') {
          final transport = await _findOrCreateMediaTransport(mid, i);

          // Set ICE params for this transport
          if (iceUfrag != null && icePwd != null) {
            _log.fine(
                '[$_debugLabel] Setting ICE params for transport $mid: ufrag=${iceUfrag.length > 8 ? '${iceUfrag.substring(0, 8)}...' : iceUfrag}');
            transport.iceConnection.setRemoteParams(
              iceLite: isIceLite,
              usernameFragment: iceUfrag,
              password: icePwd,
            );
          }

          // Set DTLS role
          if (setup != null) {
            _log.fine('[$_debugLabel] Remote DTLS setup for $mid: $setup');
            if (setup == 'active') {
              transport.dtlsRole = DtlsRole.server;
            } else if (setup == 'passive') {
              transport.dtlsRole = DtlsRole.client;
            } else if (setup == 'actpass') {
              transport.dtlsRole = DtlsRole.client;
            }
          }

          // Add candidates for this media line
          final candidateAttrs = media.attributes
              .where((attr) => attr.key == 'candidate')
              .toList();
          for (final attr in candidateAttrs) {
            if (attr.value != null) {
              try {
                var candidate =
                    await _resolveCandidate(Candidate.fromSdp(attr.value!));
                if (candidate != null) {
                  await transport.iceConnection.addRemoteCandidate(candidate);
                }
              } catch (e) {
                // Silently ignore malformed candidates
              }
            }
          }
        }
      } else {
        // Bundled - use primary transport for first media line
        if (i == 0) {
          if (iceUfrag != null && icePwd != null) {
            // Detect remote ICE restart
            final isRemoteIceRestart = _previousRemoteIceUfrag != null &&
                _previousRemoteIcePwd != null &&
                (_previousRemoteIceUfrag != iceUfrag ||
                    _previousRemoteIcePwd != icePwd);

            if (isRemoteIceRestart) {
              _log.fine('[$_debugLabel] Remote ICE restart detected');
              await _iceConnection.restart();
              _iceConnectCalled = false;
              _setIceGatheringState(IceGatheringState.new_);
            }

            _previousRemoteIceUfrag = iceUfrag;
            _previousRemoteIcePwd = icePwd;

            _log.fine(
                '[$_debugLabel] Setting remote ICE params: ufrag=${iceUfrag.length > 8 ? '${iceUfrag.substring(0, 8)}...' : iceUfrag}${isIceLite ? ' (ice-lite)' : ''}');
            _iceConnection.setRemoteParams(
              iceLite: isIceLite,
              usernameFragment: iceUfrag,
              password: icePwd,
            );
          }

          // Set DTLS role on primary transport
          if (setup != null && _transport != null) {
            _log.fine('[$_debugLabel] Remote DTLS setup: $setup');
            if (setup == 'active') {
              _transport!.dtlsRole = DtlsRole.server;
            } else if (setup == 'passive') {
              _transport!.dtlsRole = DtlsRole.client;
            } else if (setup == 'actpass') {
              _transport!.dtlsRole = DtlsRole.client;
            }
          }
        }
      }
    }

    // Extract bundled ICE candidates from all media lines (for bundled case)
    if (_remoteIsBundled ||
        _configuration.bundlePolicy != BundlePolicy.disable) {
      for (final media in sdpMessage.mediaDescriptions) {
        for (final attr
            in media.attributes.where((attr) => attr.key == 'candidate')) {
          if (attr.value != null) {
            try {
              var candidate =
                  await _resolveCandidate(Candidate.fromSdp(attr.value!));
              if (candidate != null) {
                await _iceConnection.addRemoteCandidate(candidate);
              }
            } catch (e) {
              // Silently ignore malformed candidates
            }
          }
        }
      }
    }

    // Process remote media descriptions to create transceivers for incoming tracks
    await _processRemoteMediaDescriptions(sdpMessage);

    // Start ICE connectivity checks
    if (_localDescription != null &&
        _remoteDescription != null &&
        !_iceConnectCalled) {
      _setConnectionState(PeerConnectionState.connecting);
      _iceConnectCalled = true;

      if (_configuration.bundlePolicy == BundlePolicy.disable) {
        // bundlePolicy: disable - start all media transports in parallel
        // Note: For offerer, candidates were already gathered in setLocalDescription
        _log.fine(
            '[$_debugLabel] Starting ${_mediaTransports.length} media transports (connect only)');
        await Future.wait(_mediaTransports.values.map((transport) async {
          try {
            // Only gather if not already done (for offerer case)
            if (transport.iceConnection.localCandidates.isEmpty) {
              await transport.iceConnection.gatherCandidates();
            }
            await transport.iceConnection.connect();
          } catch (e) {
            _log.fine(
                '[$_debugLabel] Transport ${transport.id} connect error: $e');
          }
        }));
      } else {
        // Single bundled connection
        _iceConnection.connect().catchError((e) {
          _log.fine('[$_debugLabel] ICE connect error: $e');
        });
      }
    }
  }

  /// Resolve mDNS candidate if needed
  Future<Candidate?> _resolveCandidate(Candidate candidate) async {
    if (!candidate.host.endsWith('.local')) {
      return candidate;
    }

    _log.fine('[$_debugLabel] Resolving mDNS candidate: ${candidate.host}');
    if (!mdnsService.isRunning) {
      await mdnsService.start();
    }
    final resolvedIp = await mdnsService.resolve(candidate.host);
    if (resolvedIp == null) {
      _log.fine(
          '[$_debugLabel] Failed to resolve mDNS candidate: ${candidate.host}');
      return null;
    }
    _log.fine('[$_debugLabel] Resolved ${candidate.host} to $resolvedIp');
    return Candidate(
      foundation: candidate.foundation,
      component: candidate.component,
      transport: candidate.transport,
      priority: candidate.priority,
      host: resolvedIp,
      port: candidate.port,
      type: candidate.type,
      relatedAddress: candidate.relatedAddress,
      relatedPort: candidate.relatedPort,
      generation: candidate.generation,
      tcpType: candidate.tcpType,
    );
  }

  /// Process remote media descriptions to create transceivers for incoming tracks
  ///
  /// This method matches remote m-lines with existing transceivers, following
  /// the WebRTC spec's transceiver matching algorithm (RFC 8829):
  /// 1. First try to match by MID (for transceivers already negotiated)
  /// 2. Then try to match by kind for pre-created transceivers with null or unmatched MID
  /// 3. If no match, create a new transceiver
  ///
  /// The kind-based matching is critical for the "pre-create transceiver as answerer"
  /// pattern used by werift, where addTransceiver() is called BEFORE receiving the offer.
  Future<void> _processRemoteMediaDescriptions(SdpMessage sdpMessage) async {
    // Track which transceivers have been matched in this negotiation
    final matchedTransceivers = <RtpTransceiver>{};

    for (final media in sdpMessage.mediaDescriptions) {
      // Skip non-audio/video media (e.g., application/datachannel)
      if (media.type != 'audio' && media.type != 'video') {
        continue;
      }

      final mid = media.getAttributeValue('mid');
      if (mid == null) {
        continue;
      }

      final mediaKind = media.type == 'audio'
          ? MediaStreamTrackKind.audio
          : MediaStreamTrackKind.video;

      // First, try to match by MID (exact match)
      var existingTransceiver = _transceiverManager.getTransceiverByMid(mid);

      // If no MID match, try to match by kind for pre-created transceivers
      // This matches werift's behavior where pre-created transceivers have mid=undefined
      // and are matched by kind when processing the remote offer
      if (existingTransceiver == null) {
        existingTransceiver = _transceiverManager.findTransceiver((t) =>
            t.kind == mediaKind &&
            !matchedTransceivers.contains(t) &&
            // Match if MID is null OR if MID doesn't match any remote m-line
            // (meaning it was assigned locally but not yet negotiated)
            (t.mid == null ||
                !sdpMessage.mediaDescriptions.any(
                    (m) => m.getAttributeValue('mid') == t.mid)));

        if (existingTransceiver != null) {
          // Found a pre-created transceiver by kind - migrate it to the new MID
          _log.fine(
              '[$_debugLabel] Migrating transceiver from mid=${existingTransceiver.mid} to mid=$mid');

          final oldMid = existingTransceiver.mid;

          // Update the _rtpSessions map key
          if (oldMid != null && _rtpSessions.containsKey(oldMid)) {
            final rtpSession = _rtpSessions.remove(oldMid);
            if (rtpSession != null) {
              _rtpSessions[mid] = rtpSession;
            }
          }

          // Update the _mediaTransports map key (for bundlePolicy:disable)
          if (oldMid != null && _mediaTransports.containsKey(oldMid)) {
            final mediaTransport = _mediaTransports.remove(oldMid);
            if (mediaTransport != null) {
              _mediaTransports[mid] = mediaTransport;
            }
          }

          // Update transceiver's MID (this also updates sender.mid via the setter)
          existingTransceiver.mid = mid;
        }
      }

      if (existingTransceiver != null) {
        // Mark as matched to avoid reusing in later iterations
        matchedTransceivers.add(existingTransceiver);

        // Configure transceiver with header extensions and simulcast from remote SDP
        _transceiverManager.setRemoteRTP(existingTransceiver, media, _rtpRouter);

        // Emit the transceiver so the application can listen to the received track
        _trackController.add(existingTransceiver);
        continue;
      }

      // Parse codec information from remote SDP
      final rtpmapAttr = media.getAttributeValue('rtpmap');
      if (rtpmapAttr == null) {
        continue;
      }

      // Parse rtpmap: "111 opus/48000/2"
      final rtpmapParts = rtpmapAttr.split(' ');
      if (rtpmapParts.length < 2) {
        continue;
      }

      final payloadType = int.tryParse(rtpmapParts[0]);
      final codecInfo = rtpmapParts[1].split('/');
      if (payloadType == null || codecInfo.isEmpty) {
        continue;
      }

      final codecName = codecInfo[0].toLowerCase();
      final clockRate =
          codecInfo.length > 1 ? int.tryParse(codecInfo[1]) : null;
      final channels = codecInfo.length > 2 ? int.tryParse(codecInfo[2]) : null;

      // Get fmtp parameters if available
      String? parameters;
      final fmtpAttr = media.getAttributeValue('fmtp');
      if (fmtpAttr != null && fmtpAttr.startsWith('$payloadType ')) {
        parameters = fmtpAttr.substring('$payloadType '.length);
      }

      // Create codec parameters
      final mediaType = media.type == 'audio' ? 'audio' : 'video';
      final _ = RtpCodecParameters(
        mimeType: '$mediaType/$codecName',
        payloadType: payloadType,
        clockRate: clockRate ?? 48000,
        channels: channels,
        parameters: parameters,
      );

      // Generate SSRC for our receiver
      final ssrc = _random.nextInt(0xFFFFFFFF);

      // Create RTP session for this remote track
      RtpTransceiver? transceiver;
      final rtpSession = _createRtpSession(
        mid: mid,
        ssrc: ssrc,
        getTransceiver: () => transceiver,
      );

      // Determine direction based on remote offer
      // If remote is sendrecv, we should also be sendrecv to allow echo/bidirectional
      // If remote is sendonly, we should be recvonly
      // If remote is recvonly, we should be sendonly (though unusual for incoming offer)
      var direction = RtpTransceiverDirection.recvonly;
      if (media.hasAttribute('sendrecv')) {
        direction = RtpTransceiverDirection.sendrecv;
      } else if (media.hasAttribute('sendonly')) {
        direction = RtpTransceiverDirection.recvonly;
      } else if (media.hasAttribute('recvonly')) {
        direction = RtpTransceiverDirection.sendonly;
      }

      // Create transceiver with appropriate direction
      if (media.type == 'audio') {
        transceiver = createAudioTransceiver(
          mid: mid,
          rtpSession: rtpSession,
          sendTrack: null,
          direction: direction,
        );
      } else {
        transceiver = createVideoTransceiver(
          mid: mid,
          rtpSession: rtpSession,
          sendTrack: null,
          direction: direction,
        );
      }

      _transceiverManager.addTransceiver(transceiver);

      // Set sender.mid for new transceiver and configure from remote SDP
      transceiver.sender.mid = mid;
      _transceiverManager.setRemoteRTP(transceiver, media, _rtpRouter);

      // Set receiver's TWCC callback for congestion control feedback
      transceiver.receiver.rtcpSsrc = ssrc;
      transceiver.receiver.onSendRtcp = (packet) async {
        final iceConnection = _getIceConnectionForMid(mid);
        if (iceConnection != null) {
          try {
            await iceConnection.send(packet);
          } on StateError catch (_) {
            // ICE not yet nominated, silently drop RTCP
          }
        }
      };

      // Emit the transceiver via onTrack stream
      _trackController.add(transceiver);
    }
  }

  /// Add ICE candidate
  Future<void> addIceCandidate(Candidate candidate) async {
    // Resolve mDNS candidates (.local addresses) to real IPs using shared helper
    final resolvedCandidate = await _resolveCandidate(candidate);
    if (resolvedCandidate == null) return;

    // For bundlePolicy:disable, route candidate to the correct MediaTransport
    if (_configuration.bundlePolicy == BundlePolicy.disable) {
      // First try to route by sdpMid
      if (candidate.sdpMid != null) {
        final transport = _mediaTransports[candidate.sdpMid];
        if (transport != null) {
          _log.fine(
              '[$_debugLabel] Adding ICE candidate to transport ${candidate.sdpMid}');
          await transport.iceConnection.addRemoteCandidate(resolvedCandidate);
          return;
        }
      }
      // Fall back to sdpMLineIndex
      if (candidate.sdpMLineIndex != null) {
        // Find transport by mLineIndex
        for (final transport in _mediaTransports.values) {
          if (transport.mLineIndex == candidate.sdpMLineIndex) {
            _log.fine(
                '[$_debugLabel] Adding ICE candidate to transport by mLineIndex ${candidate.sdpMLineIndex}');
            await transport.iceConnection.addRemoteCandidate(resolvedCandidate);
            return;
          }
        }
      }
      // No matching transport found - log warning
      _log.fine(
          '[$_debugLabel] No transport found for ICE candidate (sdpMid=${candidate.sdpMid}, mLineIndex=${candidate.sdpMLineIndex})');
      return;
    }

    // For bundled connections, add to primary ICE connection
    await _iceConnection.addRemoteCandidate(resolvedCandidate);
  }

  /// Create data channel
  /// Returns a DataChannel or ProxyDataChannel (which has the same API).
  /// If called before SCTP is ready, returns a ProxyDataChannel that will
  /// be wired up to a real DataChannel once the connection is established.
  dynamic createDataChannel(
    String label, {
    String protocol = '',
    bool ordered = true,
    int? maxRetransmits,
    int? maxPacketLifeTime,
    int priority = 0,
  }) {
    if (_transport == null) {
      throw StateError(
        'Transport not initialized. Wait for initialization to complete.',
      );
    }

    // Check if this is the first data channel (before incrementing counter)
    final isFirstChannel = _sctpManager.dataChannelsOpened == 0;

    final channel = _transport!.createDataChannel(
      label: label,
      protocol: protocol,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
      maxPacketLifeTime: maxPacketLifeTime,
      priority: priority,
    );

    // Register with SCTP manager
    _sctpManager.registerLocalChannel(channel);

    // Trigger negotiation needed if this is the first data channel
    // and we haven't negotiated SCTP yet
    if (isFirstChannel) {
      _triggerNegotiationNeeded();
    }

    return channel;
  }

  /// Handle ICE state change
  void _handleIceStateChange(IceState state) {
    switch (state) {
      case IceState.newState:
        _setIceConnectionState(IceConnectionState.new_);
        break;
      case IceState.gathering:
        // Gathering state is tracked separately
        break;
      case IceState.checking:
        _setIceConnectionState(IceConnectionState.checking);
        break;
      case IceState.connected:
        _setIceConnectionState(IceConnectionState.connected);
        // Connection state is now managed by transport
        break;
      case IceState.completed:
        _setIceConnectionState(IceConnectionState.completed);
        break;
      case IceState.failed:
        _setIceConnectionState(IceConnectionState.failed);
        // Connection state is now managed by transport
        break;
      case IceState.disconnected:
        _setIceConnectionState(IceConnectionState.disconnected);
        // Connection state is now managed by transport
        break;
      case IceState.closed:
        _setIceConnectionState(IceConnectionState.closed);
        break;
    }
  }

  /// Set signaling state
  void _setSignalingState(SignalingState state) {
    _signalingState = state;
  }

  /// Set connection state
  void _setConnectionState(PeerConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      _connectionStateController.add(state);
    }
  }

  /// Set ICE connection state
  void _setIceConnectionState(IceConnectionState state) {
    if (_iceConnectionState != state) {
      _iceConnectionState = state;
      _iceConnectionStateController.add(state);
    }
  }

  /// Set ICE gathering state
  void _setIceGatheringState(IceGatheringState state) {
    if (_iceGatheringState != state) {
      _iceGatheringState = state;
      _iceGatheringStateController.add(state);
    }
  }

  // ========================================================================
  // ICE Restart API
  // ========================================================================

  /// Request an ICE restart
  ///
  /// This sets a flag that will cause the next createOffer() call to
  /// generate new ICE credentials. The actual restart occurs when
  /// createOffer() is called with the new credentials.
  ///
  /// Usage:
  /// ```dart
  /// pc.restartIce();
  /// final offer = await pc.createOffer();
  /// await pc.setLocalDescription(offer);
  /// // Send offer to remote peer
  /// ```
  void restartIce() {
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }
    _needsIceRestart = true;
    _log.fine('[$_debugLabel] ICE restart requested');
  }

  // ========================================================================
  // Media Track API
  // ========================================================================

  /// Stream of incoming tracks
  Stream<RtpTransceiver> get onTrack => _trackController.stream;

  /// Add a track to be sent
  /// Returns the RtpSender for this track
  RtpSender addTrack(MediaStreamTrack track) {
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }

    // Check if track is already added
    for (final transceiver in _transceivers) {
      if (transceiver.sender.track == track) {
        throw StateError('Track already added');
      }
    }

    // Create new transceiver for this track
    final mid = '${_nextMid++}';

    // Generate unique SSRC
    final ssrc = _generateSsrc();

    // Create RTP session with receiver callback
    RtpTransceiver? transceiver;
    final rtpSession = _createRtpSession(
      mid: mid,
      ssrc: ssrc,
      getTransceiver: () => transceiver,
    );

    // Create transceiver based on track kind
    if (track.kind == MediaStreamTrackKind.audio) {
      transceiver = createAudioTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: track,
        direction: RtpTransceiverDirection.sendrecv,
      );
    } else {
      transceiver = createVideoTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: track,
        direction: RtpTransceiverDirection.sendrecv,
      );
    }

    // Populate codec list for SDP generation
    final allCodecs = track.kind == MediaStreamTrackKind.audio
        ? (_configuration.codecs.audio ?? supportedAudioCodecs)
        : (_configuration.codecs.video ?? supportedVideoCodecs);
    transceiver.codecs = assignPayloadTypes(allCodecs);

    _transceiverManager.addTransceiver(transceiver);

    // Set receiver's TWCC callback for congestion control feedback
    transceiver.receiver.rtcpSsrc = ssrc;
    transceiver.receiver.onSendRtcp = (packet) async {
      final iceConnection = _getIceConnectionForMid(mid);
      if (iceConnection != null) {
        try {
          await iceConnection.send(packet);
        } on StateError catch (_) {
          // ICE not yet nominated, silently drop RTCP
        }
      }
    };

    return transceiver.sender;
  }

  /// Add a transceiver with specific codec
  ///
  /// This matches werift's polymorphic addTransceiver(trackOrKind, options) API.
  /// The first argument can be either:
  /// - [MediaStreamTrackKind] - Creates a transceiver for the specified media kind
  /// - [nonstandard.MediaStreamTrack] - Creates a transceiver with a nonstandard track
  ///   for pre-encoded RTP (Ring cameras, FFmpeg forwarding)
  ///
  /// [trackOrKind] - Either MediaStreamTrackKind or nonstandard.MediaStreamTrack
  /// [codec] - The codec parameters to use (e.g., createH264Codec())
  /// [direction] - The transceiver direction (default: recvonly for kind, sendonly for track)
  ///
  /// Example with kind:
  /// ```dart
  /// final transceiver = pc.addTransceiver(MediaStreamTrackKind.video);
  /// ```
  ///
  /// Example with nonstandard track (for Ring cameras):
  /// ```dart
  /// final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
  /// final transceiver = pc.addTransceiver(track, direction: sendonly);
  /// ringCamera.onVideoRtp.listen((rtp) => track.writeRtp(rtp));
  /// ```
  RtpTransceiver addTransceiver(
    Object trackOrKind, {
    RtpCodecParameters? codec,
    RtpTransceiverDirection? direction,
  }) {
    // Handle polymorphic argument like werift
    MediaStreamTrackKind kind;
    nonstandard.MediaStreamTrack? nonstandardTrack;
    RtpTransceiverDirection effectiveDirection;

    if (trackOrKind is MediaStreamTrackKind) {
      kind = trackOrKind;
      effectiveDirection = direction ?? RtpTransceiverDirection.recvonly;
    } else if (trackOrKind is nonstandard.MediaStreamTrack) {
      nonstandardTrack = trackOrKind;
      kind = trackOrKind.kind == nonstandard.MediaKind.audio
          ? MediaStreamTrackKind.audio
          : MediaStreamTrackKind.video;
      effectiveDirection = direction ?? RtpTransceiverDirection.sendonly;
    } else {
      throw ArgumentError(
        'trackOrKind must be MediaStreamTrackKind or nonstandard.MediaStreamTrack, '
        'got ${trackOrKind.runtimeType}',
      );
    }
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }

    // Create new transceiver
    final mid = '${_nextMid++}';
    final ssrc = _generateSsrc();

    // Create RTP session with receiver callback
    RtpTransceiver? transceiver;
    final rtpSession = _createRtpSession(
      mid: mid,
      ssrc: ssrc,
      getTransceiver: () => transceiver,
    );

    // Use configured codecs if no explicit codec provided
    final effectiveCodec = codec ??
        (kind == MediaStreamTrackKind.audio
            ? _configuration.codecs.audio?.firstOrNull
            : _configuration.codecs.video?.firstOrNull);

    if (kind == MediaStreamTrackKind.audio) {
      transceiver = createAudioTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: effectiveDirection,
        codec: effectiveCodec,
      );
    } else {
      transceiver = createVideoTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: effectiveDirection,
        codec: effectiveCodec,
      );
    }

    // Populate codec list for SDP generation with all supported codecs
    final allCodecs = kind == MediaStreamTrackKind.audio
        ? (_configuration.codecs.audio ?? supportedAudioCodecs)
        : (_configuration.codecs.video ?? supportedVideoCodecs);
    transceiver.codecs = assignPayloadTypes(allCodecs);

    _transceiverManager.addTransceiver(transceiver);

    // Set sender.mid and extension IDs for RTP header extension regeneration
    transceiver.sender.mid = mid;
    transceiver.sender.midExtensionId = _midExtensionId;
    transceiver.sender.absSendTimeExtensionId = _absSendTimeExtensionId;
    transceiver.sender.transportWideCCExtensionId = _twccExtensionId;

    // Set receiver's TWCC callback for congestion control feedback
    transceiver.receiver.rtcpSsrc = ssrc;
    transceiver.receiver.onSendRtcp = (packet) async {
      final iceConnection = _getIceConnectionForMid(mid);
      if (iceConnection != null) {
        try {
          await iceConnection.send(packet);
        } on StateError catch (_) {
          // ICE not yet nominated, silently drop RTCP
        }
      }
    };

    // Register nonstandard track with sender if provided (like TypeScript registerTrack)
    if (nonstandardTrack != null) {
      transceiver.sender.registerNonstandardTrack(nonstandardTrack);
    }

    // Trigger negotiation needed per WebRTC spec
    _triggerNegotiationNeeded();

    return transceiver;
  }

  /// Add a transceiver with a nonstandard track for pre-encoded RTP
  ///
  /// @deprecated Use addTransceiver(track) instead. This method is kept for
  /// backwards compatibility but will be removed in a future version.
  ///
  /// werift uses a polymorphic addTransceiver(trackOrKind) - use that instead:
  /// ```dart
  /// final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
  /// final transceiver = pc.addTransceiver(track, direction: sendonly);
  /// ```
  @Deprecated('Use addTransceiver(track) instead - werift uses polymorphic API')
  RtpTransceiver addTransceiverWithTrack(
    nonstandard.MediaStreamTrack track, {
    RtpCodecParameters? codec,
    RtpTransceiverDirection direction = RtpTransceiverDirection.sendonly,
  }) {
    // Delegate to polymorphic addTransceiver
    return addTransceiver(track, codec: codec, direction: direction);
  }

  /// Generate random SSRC
  int _generateSsrc() {
    return _random.nextInt(0xFFFFFFFF);
  }

  /// Create an RTP session for a transceiver with standardized callbacks.
  /// This consolidates the repeated RtpSession creation pattern.
  ///
  /// [mid] - The media ID for this session
  /// [ssrc] - The local SSRC for this session
  /// [getTransceiver] - Callback to get the transceiver (may be null initially)
  RtpSession _createRtpSession({
    required String mid,
    required int ssrc,
    required RtpTransceiver? Function() getTransceiver,
  }) {
    final rtpSession = RtpSession(
      localSsrc: ssrc,
      srtpSession: null,
      onSendRtp: (packet) async {
        // Use transceiver's current MID (may be migrated from initial value)
        final transceiver = getTransceiver();
        final currentMid = transceiver?.mid ?? mid;
        final iceConnection = _getIceConnectionForMid(currentMid);
        if (iceConnection != null) {
          await iceConnection.send(packet);
        }
      },
      onSendRtcp: (packet) async {
        // Use transceiver's current MID (may be migrated from initial value)
        final transceiver = getTransceiver();
        final currentMid = transceiver?.mid ?? mid;
        final iceConnection = _getIceConnectionForMid(currentMid);
        if (iceConnection != null) {
          try {
            await iceConnection.send(packet);
          } on StateError catch (_) {
            // ICE not yet nominated, silently drop RTCP
          }
        }
      },
      onReceiveRtp: (packet) {
        final transceiver = getTransceiver();
        if (transceiver != null) {
          transceiver.receiver.handleRtpPacket(packet);
        }
      },
    );

    rtpSession.start();
    _rtpSessions[mid] = rtpSession;

    // Assign SRTP session if already available
    final srtpSession = _secureManager.getSrtpSessionForMid(mid);
    if (srtpSession != null) {
      rtpSession.srtpSession = srtpSession;
    }

    return rtpSession;
  }

  /// Find or create a transport for a media line
  ///
  /// Matches werift's findOrCreateTransport() logic:
  /// - max-bundle: always reuse single transport
  /// - max-compat: reuse only if remote is bundled
  /// - disable: always create new transport per media line
  ///
  /// Reference: werift-webrtc/packages/webrtc/src/peerConnection.ts:347
  Future<MediaTransport> _findOrCreateMediaTransport(
    String mid,
    int mLineIndex,
  ) async {
    // Match werift's findOrCreateTransport logic exactly:
    // - max-bundle: always reuse (even if remote is not bundled)
    // - max-compat: reuse only if remote IS bundled
    // - disable: always create new
    if (_configuration.bundlePolicy == BundlePolicy.maxBundle ||
        (_configuration.bundlePolicy != BundlePolicy.disable &&
            _remoteIsBundled)) {
      // Return a wrapper around the primary transport
      // For bundled media, we just return the first transport
      if (_mediaTransports.isNotEmpty) {
        return _mediaTransports.values.first;
      }
      // Create primary media transport using the main ICE connection
      final transport = MediaTransport(
        id: mid,
        iceConnection: _iceConnection,
        certificate: _certificate,
        debugLabel: '$_debugLabel-$mid',
        mLineIndex: mLineIndex,
      );
      _mediaTransports[mid] = transport;
      return transport;
    }

    // bundlePolicy: disable - each media line gets its own transport
    if (_mediaTransports.containsKey(mid)) {
      return _mediaTransports[mid]!;
    }

    // Create new ICE connection for this media line
    final iceOptions = _configToIceOptions(_configuration);
    final iceConnection = IceConnectionImpl(
      iceControlling: _iceControlling,
      options: iceOptions,
      debugLabel: '$_debugLabel-$mid',
    );

    // Forward ICE candidates with m-line index set
    iceConnection.onIceCandidate.listen((candidate) {
      // Tag with m-line index and MID for bundlePolicy:disable routing
      final taggedCandidate = candidate.copyWith(
        sdpMLineIndex: mLineIndex,
        sdpMid: mid,
      );
      _log.fine(
          '[$_debugLabel] ICE candidate for $mid (mLineIndex=$mLineIndex): ${taggedCandidate.toSdp()}');
      _iceCandidateController.add(taggedCandidate);
    });

    final transport = MediaTransport(
      id: mid,
      iceConnection: iceConnection,
      certificate: _certificate,
      debugLabel: '$_debugLabel-$mid',
      mLineIndex: mLineIndex,
    );

    // Listen for state changes
    transport.onStateChange.listen((state) {
      // Set up SRTP session for this transport as soon as it's connected
      // This is critical for bundlePolicy: disable where transports connect independently
      if (state == TransportState.connected) {
        _setupSrtpSessionForTransport(transport);
      }
      _updateAggregateConnectionState();
    });

    // Handle incoming RTP/RTCP packets for this media transport (already decrypted)
    transport.onRtp.listen((packet) {
      _routeDecryptedRtp(packet, mid: mid);
    });
    transport.onRtcp.listen((data) {
      _routeDecryptedRtcp(data, mid: mid);
    });

    _mediaTransports[mid] = transport;
    return transport;
  }

  /// Trigger negotiation needed event
  ///
  /// Per WebRTC spec, this should be called when:
  /// - A transceiver is added
  /// - A track is added or removed
  /// - A transceiver's direction changes
  /// - ICE restart is needed
  ///
  /// The event is coalesced - multiple triggers in the same microtask
  /// will only fire once.
  void _triggerNegotiationNeeded() {
    // Only trigger in stable state per WebRTC spec
    if (_signalingState != SignalingState.stable) {
      return;
    }

    // Coalesce multiple triggers
    if (_negotiationNeededPending) {
      return;
    }

    _negotiationNeededPending = true;

    // Schedule the event for the next microtask to coalesce
    Future.microtask(() {
      _negotiationNeededPending = false;
      if (!_negotiationNeededController.isClosed) {
        _negotiationNeededController.add(null);
      }
    });
  }

  /// Update aggregate connection state from all media transports
  /// For bundlePolicy: disable, connected when at least one transport is connected
  void _updateAggregateConnectionState() {
    if (_mediaTransports.isEmpty) {
      return;
    }

    final states = _mediaTransports.values.map((t) => t.state).toList();

    // Any failed = failed
    if (states.any((s) => s == TransportState.failed)) {
      _setConnectionState(PeerConnectionState.failed);
      return;
    }

    // Any disconnected = disconnected (but only if none are connected)
    if (states.any((s) => s == TransportState.disconnected) &&
        !states.any((s) => s == TransportState.connected)) {
      _setConnectionState(PeerConnectionState.disconnected);
      return;
    }

    // For bundlePolicy: disable, connected when ANY transport is connected
    // This allows video to flow even if audio transport is still connecting
    if (states.any((s) => s == TransportState.connected)) {
      _setConnectionState(PeerConnectionState.connected);
      // Set up SRTP for all connected transports
      _setupSrtpSessionsForAllTransports();
      return;
    }

    // Still connecting
    if (states.any((s) => s == TransportState.connecting)) {
      _setConnectionState(PeerConnectionState.connecting);
      return;
    }
  }

  /// Set up SRTP sessions for all media transports
  void _setupSrtpSessionsForAllTransports() {
    _secureManager.setupSrtpSessionsForAllTransports(
      _mediaTransports,
      _rtpSessions,
      _getMidsForTransport,
    );
  }

  /// Get MIDs using a given transport ID (for bundlePolicy:disable)
  List<String> _getMidsForTransport(String transportId) {
    return _transceivers
        .where((t) => t.mid == transportId)
        .map((t) => t.mid!)
        .toList();
  }

  /// Set up SRTP session for a single media transport when it becomes connected
  /// This is called immediately when an individual transport's DTLS completes
  /// Critical for bundlePolicy: disable where transports connect independently
  void _setupSrtpSessionForTransport(MediaTransport transport) {
    _secureManager.setupSrtpSessionForTransport(
      transport,
      _rtpSessions,
      _getMidsForTransport,
    );
  }

  /// Get ICE connection for sending RTP/RTCP packets for a given MID
  /// For bundlePolicy: disable, returns the transport specific to this MID
  /// For bundled connections, returns the primary transport
  IceConnection? _getIceConnectionForMid(String mid) {
    // First check for media transport (bundlePolicy: disable case)
    final mediaTransport = _mediaTransports[mid];
    if (mediaTransport != null) {
      return mediaTransport.iceConnection;
    }
    // Fall back to primary transport (bundled case)
    return _transport?.iceConnection;
  }

  /// Set up SRTP sessions for all RTP sessions once DTLS is connected
  void _setupSrtpSessions() {
    _secureManager.setupSrtpSessions(_transport, _rtpSessions);
  }

  /// Route already-decrypted RTP packet to appropriate session.
  /// This is called by IntegratedTransport which handles SRTP decryption.
  /// [mid] is optional - used for bundlePolicy:disable routing fallback
  /// (matching werift: DtlsTransport.onRtp emits decrypted packets)
  void _routeDecryptedRtp(RtpPacket packet, {String? mid}) {
    try {
      // Use RtpRouter if we have registered handlers
      if (_rtpRouter.registeredSsrcs.isNotEmpty ||
          _rtpRouter.registeredRids.isNotEmpty) {
        _rtpRouter.routeRtp(packet);
        return;
      }

      // Route by MID if available (bundlePolicy:disable)
      if (mid != null && _rtpSessions.containsKey(mid)) {
        final session = _rtpSessions[mid]!;
        if (session.onReceiveRtp != null) {
          session.onReceiveRtp!(packet);
        }
        return;
      }

      // Fallback: deliver to all sessions if no SSRC registration yet
      // This handles the case before SDP negotiation provides SSRC mappings
      for (final session in _rtpSessions.values) {
        if (session.onReceiveRtp != null) {
          session.onReceiveRtp!(packet);
        }
      }
    } catch (e) {
      // Parse error - silently ignore to avoid log spam
    }
  }

  /// Route already-decrypted RTCP packet to appropriate session.
  /// This is called by IntegratedTransport which handles SRTCP decryption.
  /// [mid] is optional - used for bundlePolicy:disable routing fallback
  void _routeDecryptedRtcp(Uint8List data, {String? mid}) async {
    if (data.length < 8) return;

    try {
      // RTCP header: VV PT(8) length(16) SSRC(32)
      // SSRC is at bytes 4-7
      final ssrc =
          (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];

      // Route by SSRC to the appropriate session
      final session = _findSessionBySsrc(ssrc);
      if (session != null) {
        // Deliver already-decrypted RTCP
        await session.receiveRtcp(data);
        return;
      }

      // Route by MID if available (bundlePolicy:disable)
      if (mid != null && _rtpSessions.containsKey(mid)) {
        await _rtpSessions[mid]!.receiveRtcp(data);
        return;
      }

      // Fallback: deliver to all sessions
      for (final session in _rtpSessions.values) {
        await session.receiveRtcp(data);
      }
    } catch (e) {
      // Parse error - silently ignore
    }
  }

  /// Find RTP session by SSRC (local or remote)
  RtpSession? _findSessionBySsrc(int ssrc) {
    for (final entry in _rtpSessions.entries) {
      final session = entry.value;
      // Check local SSRC
      if (session.localSsrc == ssrc) {
        return session;
      }
      // Check if this SSRC is a known receiver SSRC
      if (session.getReceiverStatistics(ssrc) != null) {
        return session;
      }
    }
    return null;
  }

  /// Remove a track
  void removeTrack(RtpSender sender) {
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }
    _transceiverManager.removeTrack(sender);
  }

  /// Get all transceivers
  List<RtpTransceiver> getTransceivers() => _transceiverManager.getTransceivers();

  /// Get all transceivers (getter form)
  List<RtpTransceiver> get transceivers => _transceiverManager.transceivers;

  /// Get senders
  List<RtpSender> getSenders() => _transceiverManager.getSenders();

  /// Get receivers
  List<RtpReceiver> getReceivers() => _transceiverManager.getReceivers();

  /// Get RTC statistics
  /// Returns statistics about the peer connection
  ///
  /// [selector] - Optional MediaStreamTrack to filter stats.
  ///   If null, returns all stats.
  ///   If specified, only returns stats related to that track.
  ///
  /// Implementation includes:
  /// - peer-connection stats (basic connection info)
  /// - RTP stats from all active sessions (inbound/outbound)
  /// - Track selector filtering (filters inbound-rtp and outbound-rtp stats)
  Future<RTCStatsReport> getStats([MediaStreamTrack? selector]) async {
    final stats = <RTCStats>[];
    final timestamp = getStatsTimestamp();

    // Add peer-connection level stats
    final pcId = generateStatsId('peer-connection');
    stats.add(
      RTCPeerConnectionStats(
        timestamp: timestamp,
        id: pcId,
        dataChannelsOpened: _sctpManager.dataChannelsOpened,
        dataChannelsClosed: _sctpManager.dataChannelsClosed,
      ),
    );

    // Add DataChannel stats from SCTP manager
    stats.addAll(_sctpManager.getStats());

    // Track which MIDs have been processed
    final processedMids = <String>{};

    // Collect RTP stats from transceivers with track selector filtering
    for (final transceiver in _transceivers) {
      // Check if this transceiver matches the selector
      final includeTransceiverStats = selector == null ||
          transceiver.sender.track == selector ||
          transceiver.receiver.track == selector;

      // Get RTP session by MID (skip if MID not yet assigned)
      final mid = transceiver.mid;
      if (mid == null) continue;

      final session = _rtpSessions[mid];
      if (session != null) {
        processedMids.add(mid);
        final sessionStats = session.getStats();
        for (final stat in sessionStats.values) {
          // Filter track-specific stats by track selector
          if (stat.type == RTCStatsType.outboundRtp ||
              stat.type == RTCStatsType.mediaSource ||
              stat.type == RTCStatsType.inboundRtp ||
              stat.type == RTCStatsType.remoteOutboundRtp) {
            if (includeTransceiverStats) {
              stats.add(stat);
            }
          } else {
            // Always include non-track-specific stats
            stats.add(stat);
          }
        }
      }
    }

    // Add stats from sessions not associated with transceivers (legacy path)
    for (final entry in _rtpSessions.entries) {
      if (!processedMids.contains(entry.key)) {
        final sessionStats = entry.value.getStats();
        stats.addAll(sessionStats.values);
      }
    }

    return RTCStatsReport(stats);
  }

  /// Close the peer connection
  Future<void> close() async {
    if (_connectionState == PeerConnectionState.closed) {
      return;
    }

    _setSignalingState(SignalingState.closed);
    _setConnectionState(PeerConnectionState.closed);

    // Stop all transceivers
    for (final transceiver in _transceivers) {
      transceiver.stop();
    }

    // Stop all RTP sessions (stops RTCP timers)
    for (final session in _rtpSessions.values) {
      session.stop();
    }
    _rtpSessions.clear();

    // Close integrated transport (handles SCTP, DTLS, ICE)
    await _transport?.close();

    await _iceCandidateController.close();
    await _connectionStateController.close();
    await _iceConnectionStateController.close();
    await _iceGatheringStateController.close();
    await _sctpManager.close();
    await _trackController.close();
    await _negotiationNeededController.close();
  }

  @override
  String toString() {
    return 'RtcPeerConnection(state=$_connectionState, signaling=$_signalingState)';
  }
}
