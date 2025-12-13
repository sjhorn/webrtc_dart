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
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;
import 'package:webrtc_dart/src/rtp/header_extension.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';
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
  /// Configuration
  final RtcConfiguration configuration;

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

  /// Data channel stream controller
  final StreamController<DataChannel> _dataChannelController =
      StreamController.broadcast();

  /// Track event stream controller
  final StreamController<RtpTransceiver> _trackController =
      StreamController.broadcast();

  /// List of RTP transceivers
  final List<RtpTransceiver> _transceivers = [];

  /// RTP sessions by MID
  final Map<String, RtpSession> _rtpSessions = {};

  /// RTP router for SSRC-based packet routing (matching werift: packages/webrtc/src/media/router.ts)
  final RtpRouter _rtpRouter = RtpRouter();

  /// RTX SSRC mapping by MID (original SSRC -> RTX SSRC)
  final Map<String, int> _rtxSsrcByMid = {};

  /// SRTP session for encryption/decryption of RTP/RTCP packets (shared transport)
  SrtpSession? _srtpSession;

  /// SRTP sessions by MID for bundlePolicy:disable (per-transport SRTP)
  final Map<String, SrtpSession> _srtpSessionsByMid = {};

  /// Random number generator for SSRC
  final Random _random = Random.secure();

  /// Next MID counter
  /// Starts at 1 because MID 0 is reserved for DataChannel (SCTP)
  int _nextMid = 1;

  /// Default extension ID for sdes:mid header extension
  /// Standard browsers typically use ID 1 for mid
  static const int _midExtensionId = 1;

  /// Counter for data channels opened (for stats)
  int _dataChannelsOpened = 0;

  /// Counter for data channels closed (for stats)
  final int _dataChannelsClosed = 0;

  /// Debug label for this peer connection
  static int _instanceCounter = 0;
  late final String _debugLabel;

  /// Future that completes when async initialization is done
  late final Future<void> _initializationComplete;

  RtcPeerConnection([this.configuration = const RtcConfiguration()]) {
    _debugLabel = 'PC${++_instanceCounter}';

    // Convert configuration to IceOptions
    final iceOptions = _configToIceOptions(configuration);

    _iceConnection = IceConnectionImpl(
      iceControlling: _iceControlling,
      options: iceOptions,
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

    // Forward incoming data channels
    _transport!.onDataChannel.listen((channel) {
      _dataChannelController.add(channel);
    });

    // Handle incoming RTP/RTCP packets
    _transport!.onRtpData.listen((data) {
      _handleIncomingRtpData(data);
    });
  }

  /// Convert RtcConfiguration to IceOptions
  static IceOptions _configToIceOptions(RtcConfiguration config) {
    // Extract STUN/TURN servers from configuration
    (String, int)? stunServer;
    (String, int)? turnServer;
    String? turnUsername;
    String? turnPassword;

    for (final server in config.iceServers) {
      for (final url in server.urls) {
        // Parse STUN/TURN URLs which use format: stun:host:port or turn:host:port
        // Dart's Uri parser expects // for host-based URIs, so we parse manually
        final (scheme, host, port) = _parseIceServerUrl(url);
        _log.fine(
            '[PC] Parsed ICE URL $url -> scheme=$scheme, host=$host, port=$port');
        if (scheme == 'stun' && host != null && stunServer == null) {
          stunServer = (host, port ?? 3478);
          _log.fine(' Using STUN server: $stunServer');
        } else if (scheme == 'turn' && host != null) {
          turnServer = (host, port ?? 3478);
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
    );
  }

  /// Parse ICE server URL (stun:host:port or turn:host:port)
  static (String scheme, String? host, int? port) _parseIceServerUrl(
    String url,
  ) {
    // Handle URLs like: stun:stun.l.google.com:19302
    // or: turn:turn.example.com:3478?transport=udp
    final colonIdx = url.indexOf(':');
    if (colonIdx == -1) return (url, null, null);

    final scheme = url.substring(0, colonIdx);
    var rest = url.substring(colonIdx + 1);

    // Remove leading // if present
    if (rest.startsWith('//')) {
      rest = rest.substring(2);
    }

    // Remove query string if present
    final queryIdx = rest.indexOf('?');
    if (queryIdx != -1) {
      rest = rest.substring(0, queryIdx);
    }

    // Parse host:port
    final lastColonIdx = rest.lastIndexOf(':');
    if (lastColonIdx == -1) {
      // No port specified
      return (scheme, rest, null);
    }

    final host = rest.substring(0, lastColonIdx);
    final portStr = rest.substring(lastColonIdx + 1);
    final port = int.tryParse(portStr);

    return (scheme, host, port);
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
  Stream<DataChannel> get onDataChannel => _dataChannelController.stream;

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

    // Generate ICE credentials
    final iceUfrag = _iceConnection.localUsername;
    final icePwd = _iceConnection.localPassword;

    // Generate DTLS fingerprint from certificate
    final dtlsFingerprint = _certificate != null
        ? computeCertificateFingerprint(_certificate!.certificate)
        : 'sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00'; // fallback for tests

    // Build media descriptions for transceivers
    final mediaDescriptions = <SdpMedia>[];
    final bundleMids = <String>[];

    // Add media lines for transceivers (audio/video)
    for (final transceiver in _transceivers) {
      final mid = transceiver.mid;
      bundleMids.add(mid);

      final codec = transceiver.sender.codec;
      final payloadType = codec.payloadType ?? 96;
      final ssrc = transceiver.sender.rtpSession.localSsrc;
      final cname = _iceConnection.localUsername;

      // Build format list (payload types)
      final formats = <String>['$payloadType'];

      // Build attributes list
      final directionStr = transceiver.direction.name;
      final attributes = <SdpAttribute>[
        SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
        SdpAttribute(key: 'ice-pwd', value: icePwd),
        SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
        SdpAttribute(key: 'setup', value: 'actpass'),
        SdpAttribute(key: 'mid', value: mid),
        SdpAttribute(key: directionStr),
        SdpAttribute(key: 'rtcp-mux'),
        // Add sdes:mid header extension for media identification
        SdpAttribute(
          key: 'extmap',
          value: '$_midExtensionId ${RtpExtensionUri.sdesMid}',
        ),
        SdpAttribute(
          key: 'rtpmap',
          value:
              '$payloadType ${codec.codecName}/${codec.clockRate}${codec.channels != null && codec.channels! > 1 ? '/${codec.channels}' : ''}',
        ),
        if (codec.parameters != null)
          SdpAttribute(key: 'fmtp', value: '$payloadType ${codec.parameters}'),
        // Add RTCP feedback attributes from codec
        for (final fb in codec.rtcpFeedback)
          SdpAttribute(
            key: 'rtcp-fb',
            value: fb.parameter != null
                ? '$payloadType ${fb.type} ${fb.parameter}'
                : '$payloadType ${fb.type}',
          ),
      ];

      // Add RTX for video only
      if (transceiver.kind == MediaStreamTrackKind.video) {
        // Generate or retrieve RTX SSRC
        final rtxSsrc = _rtxSsrcByMid[mid] ?? _generateSsrc();
        _rtxSsrcByMid[mid] = rtxSsrc;

        // RTX payload type is typically original + 1 (97 for VP8's 96)
        final rtxPayloadType = payloadType + 1;
        formats.add('$rtxPayloadType');

        // Add RTX attributes using RtxSdpBuilder
        attributes.addAll([
          RtxSdpBuilder.createRtxRtpMap(
            rtxPayloadType,
            clockRate: codec.clockRate,
          ),
          RtxSdpBuilder.createRtxFmtp(rtxPayloadType, payloadType),
          RtxSdpBuilder.createSsrcGroupFid(ssrc, rtxSsrc),
        ]);

        // Add SSRC attributes for original
        attributes.add(SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'));

        // Add SSRC attributes for RTX
        attributes.add(RtxSdpBuilder.createSsrcCname(rtxSsrc, cname));
      } else {
        // Audio: just add SSRC cname
        attributes.add(SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'));
      }

      mediaDescriptions.add(
        SdpMedia(
          type: transceiver.kind == MediaStreamTrackKind.audio
              ? 'audio'
              : 'video',
          port: 9,
          protocol: 'UDP/TLS/RTP/SAVPF',
          formats: formats,
          // c= line is required at media level by Firefox (RFC 4566)
          connection: const SdpConnection(connectionAddress: '0.0.0.0'),
          attributes: attributes,
        ),
      );
    }

    // Add application media for data channel (always included for compatibility)
    // DataChannel always uses MID 0
    const dataChannelMid = '0';
    if (!bundleMids.contains(dataChannelMid)) {
      bundleMids.add(dataChannelMid);
    }
    mediaDescriptions.add(
      SdpMedia(
        type: 'application',
        port: 9,
        protocol: 'UDP/DTLS/SCTP',
        formats: ['webrtc-datachannel'],
        // c= line is required at media level by Firefox (RFC 4566)
        connection: const SdpConnection(connectionAddress: '0.0.0.0'),
        attributes: [
          SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
          SdpAttribute(key: 'ice-pwd', value: icePwd),
          SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
          SdpAttribute(key: 'setup', value: 'actpass'),
          SdpAttribute(key: 'mid', value: dataChannelMid),
          SdpAttribute(key: 'sctp-port', value: '5000'),
        ],
      ),
    );

    // Build session-level attributes
    final sessionAttributes = <SdpAttribute>[
      SdpAttribute(key: 'ice-options', value: 'trickle'),
    ];

    // Add BUNDLE group unless bundlePolicy is disable
    if (configuration.bundlePolicy != BundlePolicy.disable &&
        bundleMids.isNotEmpty) {
      sessionAttributes.insert(
        0,
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
      );
    }

    // Build SDP
    final sdpMessage = SdpMessage(
      version: 0,
      origin: SdpOrigin(
        username: '-',
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionVersion: '2',
        unicastAddress: '0.0.0.0',
      ),
      sessionName: '-',
      // c= line at session level for browsers that check there
      connection: const SdpConnection(connectionAddress: '0.0.0.0'),
      timing: [SdpTiming(startTime: 0, stopTime: 0)],
      attributes: sessionAttributes,
      mediaDescriptions: mediaDescriptions,
    );

    final sdp = sdpMessage.serialize();
    return SessionDescription(type: 'offer', sdp: sdp);
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

    // Generate ICE credentials
    final iceUfrag = _iceConnection.localUsername;
    final icePwd = _iceConnection.localPassword;

    // Generate DTLS fingerprint from certificate
    final dtlsFingerprint = _certificate != null
        ? computeCertificateFingerprint(_certificate!.certificate)
        : 'sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00'; // fallback for tests

    // Build answer SDP matching remote offer
    final mediaDescriptions = <SdpMedia>[];
    final bundleMids = <String>[];
    for (final remoteMedia in remoteSdp.mediaDescriptions) {
      final mid = remoteMedia.getAttributeValue('mid') ?? '0';
      bundleMids.add(mid);

      // Build attributes based on media type
      final attributes = <SdpAttribute>[
        SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
        SdpAttribute(key: 'ice-pwd', value: icePwd),
        SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
        SdpAttribute(key: 'setup', value: 'active'),
        SdpAttribute(key: 'mid', value: mid),
      ];

      if (remoteMedia.type == 'application') {
        // DataChannel media line
        attributes.add(SdpAttribute(key: 'sctp-port', value: '5000'));
      } else if (remoteMedia.type == 'audio' || remoteMedia.type == 'video') {
        // Audio/video media line
        attributes.addAll([
          SdpAttribute(key: 'sendrecv'),
          SdpAttribute(key: 'rtcp-mux'),
        ]);

        // Copy rtpmap and fmtp from remote offer
        for (final attr in remoteMedia.getAttributes('rtpmap')) {
          attributes.add(attr);
        }
        for (final attr in remoteMedia.getAttributes('fmtp')) {
          attributes.add(attr);
        }

        // Add local SSRC if we have a transceiver for this media
        final transceiver =
            _transceivers.where((t) => t.mid == mid).firstOrNull;
        if (transceiver != null) {
          final ssrc = transceiver.sender.rtpSession.localSsrc;
          final cname = _iceConnection.localUsername;

          // Check if remote offer includes RTX for video
          if (remoteMedia.type == 'video') {
            final rtxCodecs = remoteMedia.getRtxCodecs();
            if (rtxCodecs.isNotEmpty) {
              // Remote supports RTX, generate our RTX SSRC
              final rtxSsrc = _rtxSsrcByMid[mid] ?? _generateSsrc();
              _rtxSsrcByMid[mid] = rtxSsrc;

              // Add ssrc-group FID (original, rtx)
              attributes.add(RtxSdpBuilder.createSsrcGroupFid(ssrc, rtxSsrc));

              // Add SSRC cname for original
              attributes.add(
                SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
              );

              // Add SSRC cname for RTX
              attributes.add(RtxSdpBuilder.createSsrcCname(rtxSsrc, cname));
            } else {
              // No RTX, just add SSRC cname
              attributes.add(
                SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
              );
            }
          } else {
            // Audio: just add SSRC cname
            attributes.add(
              SdpAttribute(key: 'ssrc', value: '$ssrc cname:$cname'),
            );
          }
        }
      }

      mediaDescriptions.add(
        SdpMedia(
          type: remoteMedia.type,
          port: 9,
          protocol: remoteMedia.protocol,
          formats: remoteMedia.formats,
          // c= line is required at media level by Firefox (RFC 4566)
          connection: const SdpConnection(connectionAddress: '0.0.0.0'),
          attributes: attributes,
        ),
      );
    }

    // Build session-level attributes
    final sessionAttributes = <SdpAttribute>[
      SdpAttribute(key: 'ice-options', value: 'trickle'),
    ];

    // Add BUNDLE group unless bundlePolicy is disable
    if (configuration.bundlePolicy != BundlePolicy.disable &&
        bundleMids.isNotEmpty) {
      sessionAttributes.insert(
        0,
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
      );
    }

    final sdpMessage = SdpMessage(
      version: 0,
      origin: SdpOrigin(
        username: '-',
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionVersion: '2',
        unicastAddress: '0.0.0.0',
      ),
      sessionName: '-',
      // c= line at session level for browsers that check there
      connection: const SdpConnection(connectionAddress: '0.0.0.0'),
      timing: [SdpTiming(startTime: 0, stopTime: 0)],
      attributes: sessionAttributes,
      mediaDescriptions: mediaDescriptions,
    );

    final sdp = sdpMessage.serialize();
    return SessionDescription(type: 'answer', sdp: sdp);
  }

  /// Set local description
  Future<void> setLocalDescription(SessionDescription description) async {
    // Validate state transition
    _validateSetLocalDescription(description.type);

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

    // Start ICE gathering
    if (_iceGatheringState == IceGatheringState.new_) {
      _setIceGatheringState(IceGatheringState.gathering);
      await _iceConnection.gatherCandidates();
      _setIceGatheringState(IceGatheringState.complete);
    }

    // If we now have both local and remote descriptions, start connecting
    // Note: ICE connect runs asynchronously - don't await it here
    // This allows the signaling to complete while ICE runs in background
    if (_localDescription != null &&
        _remoteDescription != null &&
        !_iceConnectCalled) {
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
    _validateSetRemoteDescription(description.type);

    _remoteDescription = description;

    // Update signaling state
    switch (description.type) {
      case 'offer':
        _setSignalingState(SignalingState.haveRemoteOffer);
        break;
      case 'answer':
        _setSignalingState(SignalingState.stable);
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
        '[$_debugLabel] Remote is bundled: $_remoteIsBundled, bundlePolicy: ${configuration.bundlePolicy}');

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
      if (configuration.bundlePolicy == BundlePolicy.disable &&
          !_remoteIsBundled) {
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
          _log.fine(
              '[$_debugLabel] Found ${candidateAttrs.length} candidates for $mid');
          for (final attr in candidateAttrs) {
            if (attr.value != null) {
              try {
                var candidate =
                    await _resolveCandidate(Candidate.fromSdp(attr.value!));
                if (candidate != null) {
                  _log.fine(
                      '[$_debugLabel] Adding candidate to transport $mid: ${candidate.host}:${candidate.port}');
                  await transport.iceConnection.addRemoteCandidate(candidate);
                }
              } catch (e) {
                _log.fine(
                    '[$_debugLabel] Failed to parse candidate for $mid: $e');
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
        configuration.bundlePolicy != BundlePolicy.disable) {
      var bundledCandidateCount = 0;
      for (final media in sdpMessage.mediaDescriptions) {
        final candidateAttrs =
            media.attributes.where((attr) => attr.key == 'candidate').toList();
        _log.fine(
            '[$_debugLabel] Found ${candidateAttrs.length} bundled candidates in ${media.type} media');
        for (final attr in candidateAttrs) {
          if (attr.value != null) {
            try {
              var candidate =
                  await _resolveCandidate(Candidate.fromSdp(attr.value!));
              if (candidate != null) {
                _log.fine(
                    '[$_debugLabel] Adding remote candidate: ${candidate.type} ${candidate.transport} ${candidate.host}:${candidate.port}');
                await _iceConnection.addRemoteCandidate(candidate);
                bundledCandidateCount++;
              }
            } catch (e) {
              _log.fine('[$_debugLabel] Failed to parse bundled candidate: $e');
            }
          }
        }
      }
      _log.fine(
          '[$_debugLabel] Added $bundledCandidateCount bundled remote candidates');
    }

    // Process remote media descriptions to create transceivers for incoming tracks
    await _processRemoteMediaDescriptions(sdpMessage);

    // Start ICE connectivity checks
    if (_localDescription != null &&
        _remoteDescription != null &&
        !_iceConnectCalled) {
      _setConnectionState(PeerConnectionState.connecting);
      _iceConnectCalled = true;

      if (configuration.bundlePolicy == BundlePolicy.disable &&
          !_remoteIsBundled) {
        // Start all media transports in parallel
        _log.fine(
            '[$_debugLabel] Starting ${_mediaTransports.length} media transports');
        await Future.wait(_mediaTransports.values.map((transport) async {
          try {
            await transport.iceConnection.gatherCandidates();
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
  Future<void> _processRemoteMediaDescriptions(SdpMessage sdpMessage) async {
    for (final media in sdpMessage.mediaDescriptions) {
      // Skip non-audio/video media (e.g., application/datachannel)
      if (media.type != 'audio' && media.type != 'video') {
        continue;
      }

      final mid = media.getAttributeValue('mid');
      if (mid == null) {
        continue;
      }

      // Check if we already have a transceiver for this MID
      final existingTransceiver =
          _transceivers.where((t) => t.mid == mid).firstOrNull;
      if (existingTransceiver != null) {
        // Transceiver already exists (we created it when adding a local track)
        // This is a sendrecv transceiver - it sends our local track and receives the remote track
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
      // Capture mid for use in closures (for bundlePolicy: disable routing)
      final transceiverMid = mid;
      RtpTransceiver? transceiver;
      final rtpSession = RtpSession(
        localSsrc: ssrc,
        srtpSession: null,
        onSendRtp: (packet) async {
          // SRTP packets go directly over ICE/UDP, not wrapped in DTLS
          // Use the MID-specific transport for bundlePolicy: disable
          final iceConnection = _getIceConnectionForMid(transceiverMid);
          if (iceConnection != null) {
            _log.fine('[PC:$transceiverMid] ICE send ${packet.length} bytes');
            await iceConnection.send(packet);
          } else {
            _log.fine(
                '[PC:$transceiverMid] ICE null, _transport=${_transport != null}, _mediaTransports=${_mediaTransports.keys}');
          }
        },
        onSendRtcp: (packet) async {
          // SRTCP packets go directly over ICE/UDP, not wrapped in DTLS
          // Use the MID-specific transport for bundlePolicy: disable
          final iceConnection = _getIceConnectionForMid(transceiverMid);
          if (iceConnection != null) {
            try {
              await iceConnection.send(packet);
            } on StateError catch (_) {
              // ICE not yet nominated, silently drop RTCP
              // This can happen when RTCP timer fires before ICE completes
            }
          }
        },
        onReceiveRtp: (packet) {
          if (transceiver != null) {
            transceiver.receiver.handleRtpPacket(packet);
          } else {
            _log.fine(
                '[$_debugLabel] WARN: onReceiveRtp for mid=$mid but transceiver is null!');
          }
        },
      );

      rtpSession.start();
      _rtpSessions[mid] = rtpSession;

      // Create receive-only transceiver
      if (media.type == 'audio') {
        transceiver = createAudioTransceiver(
          mid: mid,
          rtpSession: rtpSession,
          sendTrack: null, // Receive-only
          direction: RtpTransceiverDirection.recvonly,
        );
      } else {
        transceiver = createVideoTransceiver(
          mid: mid,
          rtpSession: rtpSession,
          sendTrack: null, // Receive-only
          direction: RtpTransceiverDirection.recvonly,
        );
      }

      _transceivers.add(transceiver);

      // Emit the transceiver via onTrack stream
      _trackController.add(transceiver);
    }
  }

  /// Add ICE candidate
  Future<void> addIceCandidate(Candidate candidate) async {
    var resolvedCandidate = candidate;
    // Resolve mDNS candidates (.local addresses) to real IPs
    if (candidate.host.endsWith('.local')) {
      _log.fine(
        '[$_debugLabel] Resolving mDNS candidate: ${candidate.host}',
      );
      // Start mDNS service if not running
      if (!mdnsService.isRunning) {
        await mdnsService.start();
      }
      final resolvedIp = await mdnsService.resolve(candidate.host);
      if (resolvedIp == null) {
        _log.fine(
          '[$_debugLabel] Failed to resolve mDNS candidate: ${candidate.host}',
        );
        return;
      }
      _log.fine('[$_debugLabel] Resolved ${candidate.host} to $resolvedIp');
      // Create new candidate with resolved IP
      resolvedCandidate = Candidate(
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

    _dataChannelsOpened++;
    final channel = _transport!.createDataChannel(
      label: label,
      protocol: protocol,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
      maxPacketLifeTime: maxPacketLifeTime,
      priority: priority,
    );
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

  /// Validate setLocalDescription
  void _validateSetLocalDescription(String type) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (_signalingState) {
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

  /// Update local description SDP with gathered ICE candidates
  /// This adds candidate lines to each media section so the full SDP
  /// can be sent to the remote peer (non-trickle ICE style)
  void _updateLocalDescriptionWithCandidates() {
    if (_localDescription == null) return;

    // Get all gathered candidates from the ICE connection
    final candidates = _iceConnection.localCandidates;
    if (candidates.isEmpty) return;

    // Parse the current SDP
    final sdp = _localDescription!.sdp;
    // Filter out empty lines and trim whitespace
    final lines = sdp.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final newLines = <String>[];

    // Helper to format a candidate line (RFC 5245 format)
    String formatCandidate(Candidate candidate) {
      var line = 'a=candidate:${candidate.foundation} ${candidate.component} '
          '${candidate.transport} ${candidate.priority} ${candidate.host} '
          '${candidate.port} typ ${candidate.type}';
      // Add raddr/rport for reflexive and relay candidates (required by RFC 5245)
      if (candidate.relatedAddress != null && candidate.relatedPort != null) {
        line +=
            ' raddr ${candidate.relatedAddress} rport ${candidate.relatedPort}';
      }
      // Add generation (Chrome requires this)
      line += ' generation ${candidate.generation ?? 0}';
      return line;
    }

    bool inMediaSection = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check if this starts a new media section
      if (line.startsWith('m=')) {
        // If we were in a media section, add candidates before starting new one
        if (inMediaSection) {
          for (final candidate in candidates) {
            newLines.add(formatCandidate(candidate));
          }
        }
        inMediaSection = true;
      }

      newLines.add(line);
    }

    // Add candidates to the last media section
    if (inMediaSection) {
      for (final candidate in candidates) {
        newLines.add(formatCandidate(candidate));
      }
    }

    // Update local description with new SDP
    _localDescription = SessionDescription(
      type: _localDescription!.type,
      sdp: newLines.join('\n'),
    );
  }

  /// Validate setRemoteDescription
  void _validateSetRemoteDescription(String type) {
    // Rollback is always allowed
    if (type == 'rollback') {
      return;
    }

    switch (_signalingState) {
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

    // Create transceiver first to get receiver
    // Then create RTP session with receiver callback
    RtpTransceiver? transceiver;

    // Create RTP session with receiver callback
    // Store the transceiver so the callback can access it
    RtpTransceiver? transceiverRef;
    // Capture mid for use in closures (for bundlePolicy: disable routing)
    final transceiverMid = mid;

    final rtpSession = RtpSession(
      localSsrc: ssrc,
      srtpSession: null, // Will be set when DTLS keys are available
      onSendRtp: (packet) async {
        // SRTP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          _log.fine('[PC:$transceiverMid] ICE send ${packet.length} bytes');
          await iceConnection.send(packet);
        } else {
          _log.fine(
              '[PC:$transceiverMid] ICE null, _transport=${_transport != null}, _mediaTransports=${_mediaTransports.keys}');
        }
      },
      onSendRtcp: (packet) async {
        // SRTCP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          try {
            await iceConnection.send(packet);
          } on StateError catch (_) {
            // ICE not yet nominated, silently drop RTCP
            // This can happen when RTCP timer fires before ICE completes
          }
        }
      },
      onReceiveRtp: (packet) {
        // Route to receiver when available
        if (transceiverRef != null) {
          transceiverRef.receiver.handleRtpPacket(packet);
        }
      },
    );

    // Start the RTP session
    rtpSession.start();

    // Store session
    _rtpSessions[mid] = rtpSession;

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

    // Wire up the transceiver reference for the receive callback
    transceiverRef = transceiver;

    _transceivers.add(transceiver);

    return transceiver.sender;
  }

  /// Add a transceiver with specific codec
  ///
  /// This allows specifying the codec to use for the track, which is useful
  /// when the remote peer requires a specific codec (e.g., H264 for Ring cameras).
  ///
  /// [kind] - The type of media (audio or video)
  /// [codec] - The codec parameters to use (e.g., createH264Codec())
  /// [direction] - The transceiver direction (default: recvonly)
  RtpTransceiver addTransceiver(
    MediaStreamTrackKind kind, {
    RtpCodecParameters? codec,
    RtpTransceiverDirection direction = RtpTransceiverDirection.recvonly,
  }) {
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }

    // Create new transceiver
    final mid = '${_nextMid++}';
    final ssrc = _generateSsrc();

    RtpTransceiver? transceiverRef;
    // Capture mid for use in closures (for bundlePolicy: disable routing)
    final transceiverMid = mid;

    final rtpSession = RtpSession(
      localSsrc: ssrc,
      srtpSession: null,
      onSendRtp: (packet) async {
        // SRTP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          _log.fine('[PC:$transceiverMid] ICE send ${packet.length} bytes');
          await iceConnection.send(packet);
        } else {
          _log.fine(
              '[PC:$transceiverMid] ICE null, _transport=${_transport != null}, _mediaTransports=${_mediaTransports.keys}');
        }
      },
      onSendRtcp: (packet) async {
        // SRTCP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          try {
            await iceConnection.send(packet);
          } on StateError catch (_) {
            // ICE not yet nominated, silently drop RTCP
            // This can happen when RTCP timer fires before ICE completes
          }
        }
      },
      onReceiveRtp: (packet) {
        if (transceiverRef != null) {
          transceiverRef.receiver.handleRtpPacket(packet);
        }
      },
    );

    rtpSession.start();
    _rtpSessions[mid] = rtpSession;

    // Use configured codecs if no explicit codec provided
    final effectiveCodec = codec ??
        (kind == MediaStreamTrackKind.audio
            ? configuration.codecs.audio?.firstOrNull
            : configuration.codecs.video?.firstOrNull);

    RtpTransceiver transceiver;
    if (kind == MediaStreamTrackKind.audio) {
      transceiver = createAudioTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: direction,
        codec: effectiveCodec,
      );
    } else {
      transceiver = createVideoTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: direction,
        codec: effectiveCodec,
      );
    }

    transceiverRef = transceiver;
    _transceivers.add(transceiver);

    // Set sender.mid and midExtensionId for RTP header extension
    transceiver.sender.mid = mid;
    transceiver.sender.midExtensionId = _midExtensionId;

    return transceiver;
  }

  /// Add a transceiver with a nonstandard track for pre-encoded RTP
  ///
  /// This matches the TypeScript werift addTransceiver(track, options) API.
  /// The track's onReceiveRtp stream is wired to the sender's sendRtp,
  /// so calling track.writeRtp() will forward packets to the remote peer.
  ///
  /// Used for forwarding pre-encoded RTP (e.g., from Ring cameras, FFmpeg).
  ///
  /// Example:
  /// ```dart
  /// final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
  /// final transceiver = pc.addTransceiverWithTrack(track, direction: sendonly);
  /// // Later, from Ring camera:
  /// ringCamera.onVideoRtp.listen((rtp) => track.writeRtp(rtp));
  /// ```
  RtpTransceiver addTransceiverWithTrack(
    nonstandard.MediaStreamTrack track, {
    RtpCodecParameters? codec,
    RtpTransceiverDirection direction = RtpTransceiverDirection.sendonly,
  }) {
    if (_connectionState == PeerConnectionState.closed) {
      throw StateError('PeerConnection is closed');
    }

    // Create new transceiver
    final mid = '${_nextMid++}';
    final ssrc = _generateSsrc();

    RtpTransceiver? transceiverRef;
    // Capture mid for use in closures (for bundlePolicy: disable routing)
    final transceiverMid = mid;

    final rtpSession = RtpSession(
      localSsrc: ssrc,
      srtpSession: null,
      onSendRtp: (packet) async {
        // SRTP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          _log.fine('[PC:$transceiverMid] ICE send ${packet.length} bytes');
          await iceConnection.send(packet);
        } else {
          _log.fine(
              '[PC:$transceiverMid] ICE null, _transport=${_transport != null}, _mediaTransports=${_mediaTransports.keys}');
        }
      },
      onSendRtcp: (packet) async {
        // SRTCP packets go directly over ICE/UDP, not wrapped in DTLS
        // Use the MID-specific transport for bundlePolicy: disable
        final iceConnection = _getIceConnectionForMid(transceiverMid);
        if (iceConnection != null) {
          try {
            await iceConnection.send(packet);
          } on StateError catch (_) {
            // ICE not yet nominated, silently drop RTCP
            // This can happen when RTCP timer fires before ICE completes
          }
        }
      },
      onReceiveRtp: (packet) {
        if (transceiverRef != null) {
          transceiverRef.receiver.handleRtpPacket(packet);
        }
      },
    );

    rtpSession.start();
    _rtpSessions[mid] = rtpSession;

    // If SRTP session already exists (DTLS completed before this transceiver was added),
    // assign it now so RTP packets will be encrypted
    if (_srtpSession != null) {
      rtpSession.srtpSession = _srtpSession;
    }

    // Determine kind from track
    final kind = track.kind == nonstandard.MediaKind.audio
        ? MediaStreamTrackKind.audio
        : MediaStreamTrackKind.video;

    // Use configured codecs if no explicit codec provided
    final effectiveCodec = codec ??
        (kind == MediaStreamTrackKind.audio
            ? configuration.codecs.audio?.firstOrNull
            : configuration.codecs.video?.firstOrNull);

    RtpTransceiver transceiver;
    if (kind == MediaStreamTrackKind.audio) {
      transceiver = createAudioTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: direction,
        codec: effectiveCodec,
      );
    } else {
      transceiver = createVideoTransceiver(
        mid: mid,
        rtpSession: rtpSession,
        sendTrack: null,
        direction: direction,
        codec: effectiveCodec,
      );
    }

    // Set sender.mid and midExtensionId for RTP header extension
    // MUST be set BEFORE registerNonstandardTrack, since that function captures mid
    transceiver.sender.mid = mid;
    transceiver.sender.midExtensionId = _midExtensionId;

    // Register the nonstandard track with the sender (like TypeScript registerTrack)
    transceiver.sender.registerNonstandardTrack(track);

    transceiverRef = transceiver;
    _transceivers.add(transceiver);

    return transceiver;
  }

  /// Generate random SSRC
  int _generateSsrc() {
    return _random.nextInt(0xFFFFFFFF);
  }

  /// Find or create a transport for a media line
  /// When bundlePolicy is disable, creates a new transport per media line.
  /// When bundled, reuses the primary transport.
  Future<MediaTransport> _findOrCreateMediaTransport(
    String mid,
    int mLineIndex,
  ) async {
    // If bundled or bundlePolicy is not disable, use primary transport
    if (_remoteIsBundled ||
        configuration.bundlePolicy != BundlePolicy.disable) {
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
    final iceOptions = _configToIceOptions(configuration);
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

    // Handle incoming RTP/RTCP packets for this media transport
    transport.onRtpData.listen((data) {
      _handleIncomingRtpData(data, mid: mid);
    });

    _mediaTransports[mid] = transport;
    return transport;
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
    for (final transport in _mediaTransports.values) {
      final dtlsSocket = transport.dtlsSocket;
      if (dtlsSocket == null) continue;

      final srtpContext = dtlsSocket.srtpContext;
      if (srtpContext.localMasterKey == null ||
          srtpContext.localMasterSalt == null ||
          srtpContext.remoteMasterKey == null ||
          srtpContext.remoteMasterSalt == null ||
          srtpContext.profile == null) {
        continue;
      }

      final srtpSession = SrtpSession(
        profile: srtpContext.profile!,
        localMasterKey: srtpContext.localMasterKey!,
        localMasterSalt: srtpContext.localMasterSalt!,
        remoteMasterKey: srtpContext.remoteMasterKey!,
        remoteMasterSalt: srtpContext.remoteMasterSalt!,
      );

      // Store SRTP session by transport ID (MID)
      _srtpSessionsByMid[transport.id] = srtpSession;
      _log.fine(
          '[$_debugLabel] SRTP session created for transport ${transport.id}');

      // Find transceivers using this transport and update their SRTP sessions
      // For bundlePolicy:disable, transport.id == mid, so match by mid directly
      for (final transceiver in _transceivers) {
        if (transceiver.mid == transport.id) {
          final rtpSession = _rtpSessions[transceiver.mid];
          if (rtpSession != null) {
            rtpSession.srtpSession = srtpSession;
          }
        }
      }
    }
  }

  /// Set up SRTP session for a single media transport when it becomes connected
  /// This is called immediately when an individual transport's DTLS completes
  /// Critical for bundlePolicy: disable where transports connect independently
  void _setupSrtpSessionForTransport(MediaTransport transport) {
    // Skip if already set up
    if (_srtpSessionsByMid.containsKey(transport.id)) {
      return;
    }

    final dtlsSocket = transport.dtlsSocket;
    if (dtlsSocket == null) return;

    final srtpContext = dtlsSocket.srtpContext;
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      _log.fine(
          '[$_debugLabel] SRTP keys not available for transport ${transport.id}');
      return;
    }

    final srtpSession = SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );

    // Store SRTP session by transport ID (MID)
    _srtpSessionsByMid[transport.id] = srtpSession;
    _log.fine(
        '[$_debugLabel] SRTP session created for transport ${transport.id} (per-transport setup)');

    // Find transceivers using this transport and update their SRTP sessions
    // For bundlePolicy:disable, transport.id == mid, so match by mid directly
    for (final transceiver in _transceivers) {
      // Match by MID since transport.id is the MID for bundlePolicy:disable
      if (transceiver.mid == transport.id) {
        final rtpSession = _rtpSessions[transceiver.mid];
        if (rtpSession != null) {
          rtpSession.srtpSession = srtpSession;
          _log.fine(
              '[$_debugLabel] Assigned SRTP session to RTP session for mid=${transceiver.mid}');
        }
      }
    }
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
    _log.fine(
        ' _setupSrtpSessions called, _rtpSessions.length=${_rtpSessions.length}');
    final dtlsSocket = _transport?.dtlsSocket;
    if (dtlsSocket == null) {
      _log.fine(' _setupSrtpSessions: dtlsSocket is null');
      return;
    }

    // Get SRTP context from DTLS
    final srtpContext = dtlsSocket.srtpContext;

    // Check if keying material is available
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      // Keys not yet available, will be set up later
      _log.fine(
          ' _setupSrtpSessions: SRTP keys not available - localKey=${srtpContext.localMasterKey != null}, localSalt=${srtpContext.localMasterSalt != null}, remoteKey=${srtpContext.remoteMasterKey != null}, remoteSalt=${srtpContext.remoteMasterSalt != null}, profile=${srtpContext.profile}');
      return;
    }

    // Create SRTP session from DTLS keying material
    final srtpSession = SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );

    // Store at PeerConnection level for use in decryption
    _srtpSession = srtpSession;
    _log.fine(
        ' Created SRTP session, applying to ${_rtpSessions.length} RTP sessions');

    // Apply SRTP session to all RTP sessions
    for (final entry in _rtpSessions.entries) {
      _log.fine(' Applying SRTP to RTP session for mid=${entry.key}');
      entry.value.srtpSession = srtpSession;
    }
  }

  /// Handle incoming RTP/RTCP data from transport
  /// [mid] is optional - when provided (bundlePolicy:disable), uses per-transport SRTP session
  void _handleIncomingRtpData(Uint8List data, {String? mid}) {
    if (data.length < 12) {
      // Too short to be valid RTP/RTCP
      return;
    }

    try {
      final secondByte = data[1];
      final isRtcp = secondByte >= 192 && secondByte <= 208;

      if (isRtcp) {
        // RTCP packet - parse to get SSRC
        // RTCP header: VV PT(8) length(16) SSRC(32)
        // SSRC is at bytes 4-7
        if (data.length >= 8) {
          final ssrc =
              (data[4] << 24) | (data[5] << 16) | (data[6] << 8) | data[7];
          _routeRtcpPacket(ssrc, data, mid: mid);
        }
      } else {
        // RTP packet - parse to get SSRC
        // RTP header has SSRC at bytes 8-11
        if (data.length >= 12) {
          final ssrc =
              (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
          _routeRtpPacket(ssrc, data, mid: mid);
        }
      }
    } catch (e) {
      // Ignore malformed packets
    }
  }

  /// Route RTP packet to appropriate session using RtpRouter
  /// (matching werift: packages/webrtc/src/peerConnection.ts - router.routeRtp)
  /// [mid] is optional - when provided (bundlePolicy:disable), uses per-transport SRTP session
  void _routeRtpPacket(int ssrc, Uint8List data, {String? mid}) async {
    try {
      // Get SRTP session - prefer per-MID session for bundlePolicy:disable
      SrtpSession? srtpSession;
      if (mid != null && _srtpSessionsByMid.containsKey(mid)) {
        srtpSession = _srtpSessionsByMid[mid];
      } else {
        srtpSession = _srtpSession;
      }

      // Decrypt SRTP to RTP first
      RtpPacket packet;
      if (srtpSession != null) {
        packet = await srtpSession.decryptSrtp(data);
      } else {
        // No SRTP session yet (before DTLS handshake), parse as plain RTP
        packet = RtpPacket.parse(data);
      }

      // Use RtpRouter if we have registered handlers
      if (_rtpRouter.registeredSsrcs.isNotEmpty ||
          _rtpRouter.registeredRids.isNotEmpty) {
        _rtpRouter.routeRtp(packet);
        return;
      }

      // Route by MID if available (bundlePolicy:disable or separate transports)
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
      // Decryption or parse error - could be replay attack, corrupted packet, etc.
      // Silently ignore to avoid log spam
    }
  }

  /// Route RTCP packet to appropriate session
  /// [mid] is optional - when provided (bundlePolicy:disable), uses per-transport SRTP session
  void _routeRtcpPacket(int ssrc, Uint8List data, {String? mid}) async {
    // Get SRTP session for decryption - prefer per-MID session for bundlePolicy:disable
    SrtpSession? srtpSession;
    if (mid != null && _srtpSessionsByMid.containsKey(mid)) {
      srtpSession = _srtpSessionsByMid[mid];
    } else {
      srtpSession = _srtpSession;
    }

    // Route RTCP by SSRC to the appropriate session
    final session = _findSessionBySsrc(ssrc);
    if (session != null) {
      await session.receiveRtcp(data, srtpSession: srtpSession);
      return;
    }

    // Fallback: deliver to all sessions
    for (final session in _rtpSessions.values) {
      await session.receiveRtcp(data, srtpSession: srtpSession);
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

    // Find transceiver with this sender
    final transceiver = _transceivers.firstWhere(
      (t) => t.sender == sender,
      orElse: () => throw ArgumentError('Sender not found'),
    );

    // Stop the transceiver
    transceiver.stop();

    // Note: Don't remove from list to maintain MID mapping
    // Mark direction as inactive instead
    transceiver.direction = RtpTransceiverDirection.inactive;
  }

  /// Get all transceivers
  List<RtpTransceiver> getTransceivers() {
    return List.unmodifiable(_transceivers);
  }

  /// Get all transceivers (getter form)
  List<RtpTransceiver> get transceivers => List.unmodifiable(_transceivers);

  /// Get senders
  List<RtpSender> getSenders() {
    return _transceivers.map((t) => t.sender).toList();
  }

  /// Get receivers
  List<RtpReceiver> getReceivers() {
    return _transceivers.map((t) => t.receiver).toList();
  }

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
        dataChannelsOpened: _dataChannelsOpened,
        dataChannelsClosed: _dataChannelsClosed,
      ),
    );

    // Track which MIDs have been processed
    final processedMids = <String>{};

    // Collect RTP stats from transceivers with track selector filtering
    for (final transceiver in _transceivers) {
      // Check if this transceiver matches the selector
      final includeTransceiverStats = selector == null ||
          transceiver.sender.track == selector ||
          transceiver.receiver.track == selector;

      // Get RTP session by MID
      final session = _rtpSessions[transceiver.mid];
      if (session != null) {
        processedMids.add(transceiver.mid);
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
    await _dataChannelController.close();
    await _trackController.close();
  }

  @override
  String toString() {
    return 'RtcPeerConnection(state=$_connectionState, signaling=$_signalingState)';
  }
}
