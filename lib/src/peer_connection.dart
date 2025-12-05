import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';
import 'package:webrtc_dart/src/transport/transport.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/dtls_transport.dart' show DtlsRole;
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/rtp_transceiver.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';

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

/// RTCConfiguration
class RtcConfiguration {
  /// ICE servers
  final List<IceServer> iceServers;

  /// ICE transport policy
  final IceTransportPolicy iceTransportPolicy;

  const RtcConfiguration({
    this.iceServers = const [],
    this.iceTransportPolicy = IceTransportPolicy.all,
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

  /// ICE connection
  late final IceConnection _iceConnection;

  /// ICE controlling role (true if this peer created the offer)
  bool _iceControlling = false;

  /// Integrated transport (ICE + DTLS + SCTP)
  IntegratedTransport? _transport;

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

  /// RTX SSRC mapping by MID (original SSRC -> RTX SSRC)
  final Map<String, int> _rtxSsrcByMid = {};

  /// Random number generator for SSRC
  final Random _random = Random.secure();

  /// Next MID counter
  /// Starts at 1 because MID 0 is reserved for DataChannel (SCTP)
  int _nextMid = 1;

  /// Counter for data channels opened (for stats)
  int _dataChannelsOpened = 0;

  /// Counter for data channels closed (for stats)
  final int _dataChannelsClosed = 0;

  /// Debug label for this peer connection
  static int _instanceCounter = 0;
  late final String _debugLabel;

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

    // Initialize asynchronously
    _initializeAsync();
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
          _setConnectionState(PeerConnectionState.connected);
          // Set up SRTP for all RTP sessions when DTLS is connected
          _setupSrtpSessions();
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
        final uri = Uri.parse(url);
        if (uri.scheme == 'stun') {
          stunServer = (uri.host, uri.port != 0 ? uri.port : 3478);
        } else if (uri.scheme == 'turn') {
          turnServer = (uri.host, uri.port != 0 ? uri.port : 3478);
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
      print('[$_debugLabel] ICE restart: new credentials generated');
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
      final attributes = <SdpAttribute>[
        SdpAttribute(key: 'ice-ufrag', value: iceUfrag),
        SdpAttribute(key: 'ice-pwd', value: icePwd),
        SdpAttribute(key: 'fingerprint', value: dtlsFingerprint),
        SdpAttribute(key: 'setup', value: 'actpass'),
        SdpAttribute(key: 'mid', value: mid),
        SdpAttribute(key: 'sendrecv'),
        SdpAttribute(key: 'rtcp-mux'),
        SdpAttribute(
          key: 'rtpmap',
          value:
              '$payloadType ${codec.codecName}/${codec.clockRate}${codec.channels != null && codec.channels! > 1 ? '/${codec.channels}' : ''}',
        ),
        if (codec.parameters != null)
          SdpAttribute(key: 'fmtp', value: '$payloadType ${codec.parameters}'),
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
      attributes: [
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
        SdpAttribute(key: 'ice-options', value: 'trickle'),
      ],
      mediaDescriptions: mediaDescriptions,
    );

    final sdp = sdpMessage.serialize();
    return SessionDescription(type: 'offer', sdp: sdp);
  }

  /// Create an answer
  Future<SessionDescription> createAnswer() async {
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
        final transceiver = _transceivers
            .where((t) => t.mid == mid)
            .firstOrNull;
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
      attributes: [
        SdpAttribute(key: 'group', value: 'BUNDLE ${bundleMids.join(' ')}'),
        SdpAttribute(key: 'ice-options', value: 'trickle'),
      ],
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
        print('[$_debugLabel] ICE connect error: $e');
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
    if (sdpMessage.mediaDescriptions.isNotEmpty) {
      final media = sdpMessage.mediaDescriptions[0];
      final iceUfrag = media.getAttributeValue('ice-ufrag');
      final icePwd = media.getAttributeValue('ice-pwd');

      if (iceUfrag != null && icePwd != null) {
        // Detect remote ICE restart by checking if credentials changed
        final isRemoteIceRestart =
            _previousRemoteIceUfrag != null &&
            _previousRemoteIcePwd != null &&
            (_previousRemoteIceUfrag != iceUfrag ||
                _previousRemoteIcePwd != icePwd);

        if (isRemoteIceRestart) {
          print(
            '[$_debugLabel] Remote ICE restart detected - credentials changed',
          );
          // Perform local ICE restart to match
          await _iceConnection.restart();
          _iceConnectCalled = false;
          _setIceGatheringState(IceGatheringState.new_);
        }

        // Store credentials for future comparison
        _previousRemoteIceUfrag = iceUfrag;
        _previousRemoteIcePwd = icePwd;

        final isIceLite = sdpMessage.isIceLite;
        print(
          '[$_debugLabel] Setting remote ICE params: ufrag=$iceUfrag, pwd=${icePwd.substring(0, 8)}...${isIceLite ? ' (ice-lite)' : ''}',
        );
        _iceConnection.setRemoteParams(
          iceLite: isIceLite,
          usernameFragment: iceUfrag,
          password: icePwd,
        );
      }

      // Extract DTLS setup role from remote SDP
      // Per RFC 5763:
      // - If remote is 'active', we are the DTLS server (passive)
      // - If remote is 'passive', we are the DTLS client (active)
      // - If remote is 'actpass', we choose to be active (client)
      final setup = media.getAttributeValue('setup');
      if (setup != null && _transport != null) {
        print('[$_debugLabel] Remote DTLS setup: $setup');
        if (setup == 'active') {
          // Remote is client, we are server
          _transport!.dtlsRole = DtlsRole.server;
          print(
            '[$_debugLabel] Setting DTLS role to server (remote is active)',
          );
        } else if (setup == 'passive') {
          // Remote is server, we are client
          _transport!.dtlsRole = DtlsRole.client;
          print(
            '[$_debugLabel] Setting DTLS role to client (remote is passive)',
          );
        } else if (setup == 'actpass') {
          // Remote can be either, we choose to be client
          _transport!.dtlsRole = DtlsRole.client;
          print(
            '[$_debugLabel] Setting DTLS role to client (remote is actpass)',
          );
        }
      }
    }

    // Process remote media descriptions to create transceivers for incoming tracks
    await _processRemoteMediaDescriptions(sdpMessage);

    // If we have both local and remote descriptions, start connecting
    // Note: ICE connect runs asynchronously - don't await it here
    // This allows the signaling to complete while ICE runs in background
    if (_localDescription != null &&
        _remoteDescription != null &&
        !_iceConnectCalled) {
      _setConnectionState(PeerConnectionState.connecting);
      _iceConnectCalled = true;
      // Start ICE connectivity checks in background
      _iceConnection.connect().catchError((e) {
        print('[$_debugLabel] ICE connect error: $e');
      });
    }
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
      final existingTransceiver = _transceivers
          .where((t) => t.mid == mid)
          .firstOrNull;
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
      final clockRate = codecInfo.length > 1
          ? int.tryParse(codecInfo[1])
          : null;
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
      final rtpSession = RtpSession(
        localSsrc: ssrc,
        srtpSession: null,
        onSendRtp: (packet) async {
          if (_transport?.dtlsSocket != null) {
            await _transport!.dtlsSocket!.send(packet);
          }
        },
        onSendRtcp: (packet) async {
          if (_transport?.dtlsSocket != null) {
            await _transport!.dtlsSocket!.send(packet);
          }
        },
        onReceiveRtp: (packet) {
          if (transceiver != null) {
            transceiver.receiver.handleRtpPacket(packet);
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
    await _iceConnection.addRemoteCandidate(candidate);
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
    print('[$_debugLabel] ICE restart requested');
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

    final rtpSession = RtpSession(
      localSsrc: ssrc,
      srtpSession: null, // Will be set when DTLS keys are available
      onSendRtp: (packet) async {
        // Send RTP through DTLS
        if (_transport?.dtlsSocket != null) {
          await _transport!.dtlsSocket!.send(packet);
        }
      },
      onSendRtcp: (packet) async {
        // Send RTCP through DTLS
        if (_transport?.dtlsSocket != null) {
          await _transport!.dtlsSocket!.send(packet);
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

  /// Generate random SSRC
  int _generateSsrc() {
    return _random.nextInt(0xFFFFFFFF);
  }

  /// Set up SRTP sessions for all RTP sessions once DTLS is connected
  void _setupSrtpSessions() {
    final dtlsSocket = _transport?.dtlsSocket;
    if (dtlsSocket == null) {
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

    // Apply SRTP session to all RTP sessions
    for (final rtpSession in _rtpSessions.values) {
      rtpSession.srtpSession = srtpSession;
    }
  }

  /// Handle incoming RTP/RTCP data from transport
  void _handleIncomingRtpData(Uint8List data) {
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
          _routeRtcpPacket(ssrc, data);
        }
      } else {
        // RTP packet - parse to get SSRC
        // RTP header has SSRC at bytes 8-11
        if (data.length >= 12) {
          final ssrc =
              (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
          _routeRtpPacket(ssrc, data);
        }
      }
    } catch (e) {
      // Ignore malformed packets
    }
  }

  /// Route RTP packet to appropriate session
  void _routeRtpPacket(int ssrc, Uint8List data) async {
    // Find RTP session by SSRC or by any active receiver
    // For now, we'll route to the first available session since we need
    // proper SSRC mapping from SDP negotiation
    for (final session in _rtpSessions.values) {
      // TODO: Match by remote SSRC when we have proper SDP negotiation
      // For now, deliver to all sessions (will be filtered by RtpSession)
      await session.receiveRtp(data);
    }
  }

  /// Route RTCP packet to appropriate session
  void _routeRtcpPacket(int ssrc, Uint8List data) async {
    // Similar to RTP routing
    for (final session in _rtpSessions.values) {
      await session.receiveRtcp(data);
    }
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
      final includeTransceiverStats =
          selector == null ||
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
