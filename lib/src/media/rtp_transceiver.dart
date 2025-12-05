import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/svc_manager.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/codec/opus.dart';
import 'package:webrtc_dart/src/codec/vp9.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

/// RTP Transceiver Direction
enum RtpTransceiverDirection { sendrecv, sendonly, recvonly, inactive }

/// RTP Transceiver
/// Manages sending and receiving RTP for a media track
/// Combines RtpSender and RtpReceiver
class RtpTransceiver {
  /// Media type (audio or video)
  final MediaStreamTrackKind kind;

  /// Media ID (mid) - unique identifier in SDP
  final String mid;

  /// RTP sender
  final RtpSender sender;

  /// RTP receiver
  final RtpReceiver receiver;

  /// Current direction
  RtpTransceiverDirection _direction;

  /// Stopped flag
  bool _stopped = false;

  /// Simulcast parameters (for sending/receiving multiple layers)
  final List<RTCRtpSimulcastParameters> _simulcast = [];

  /// Callback when a new track is received (including simulcast layers)
  void Function(MediaStreamTrack track)? onTrack;

  RtpTransceiver({
    required this.kind,
    required this.mid,
    required this.sender,
    required this.receiver,
    RtpTransceiverDirection? direction,
    List<RTCRtpSimulcastParameters>? simulcast,
  }) : _direction = direction ?? RtpTransceiverDirection.sendrecv {
    if (simulcast != null) {
      _simulcast.addAll(simulcast);
    }
  }

  /// Get simulcast parameters
  List<RTCRtpSimulcastParameters> get simulcast =>
      List.unmodifiable(_simulcast);

  /// Add a simulcast layer
  void addSimulcastLayer(RTCRtpSimulcastParameters params) {
    _simulcast.add(params);
  }

  /// Get current direction
  // ignore: unnecessary_getters_setters
  RtpTransceiverDirection get direction => _direction;

  /// Set direction
  set direction(RtpTransceiverDirection value) {
    _direction = value;
  }

  /// Get current direction for negotiation
  RtpTransceiverDirection get currentDirection => _direction;

  /// Check if stopped
  bool get stopped => _stopped;

  /// Stop the transceiver
  void stop() {
    if (!_stopped) {
      _stopped = true;
      sender.stop();
      receiver.stop();
    }
  }

  /// Set negotiated direction (called after SDP negotiation)
  void setNegotiatedDirection(RtpTransceiverDirection negotiated) {
    _direction = negotiated;
  }

  @override
  String toString() {
    return 'RtpTransceiver(mid=$mid, kind=$kind, direction=$direction)';
  }
}

/// RTP Sender
/// Sends RTP packets for an outgoing media track
/// Supports simulcast with multiple encoding layers
class RtpSender {
  /// Media track being sent (null if no track)
  MediaStreamTrack? _track;

  /// RTP session for sending
  final RtpSession rtpSession;

  /// Codec parameters
  final RtpCodecParameters codec;

  /// Stream subscription for track frames
  StreamSubscription? _trackSubscription;

  /// Stopped flag
  bool _stopped = false;

  /// Send encoding parameters (for simulcast)
  final List<RTCRtpEncodingParameters> _encodings = [];

  /// Current transaction ID for parameter changes
  String _transactionId = '';

  /// Transaction ID counter
  static int _transactionCounter = 0;

  /// SSRC counter for generating unique SSRCs
  static int _ssrcCounter = 0;

  /// RID header extension ID (set from SDP negotiation)
  int? ridExtensionId;

  /// MID header extension ID (set from SDP negotiation)
  int? midExtensionId;

  /// Media ID (mid) for this sender
  String? mid;

  RtpSender({
    MediaStreamTrack? track,
    required this.rtpSession,
    required this.codec,
    List<RTCRtpEncodingParameters>? sendEncodings,
  }) : _track = track {
    // Initialize encodings
    if (sendEncodings != null && sendEncodings.isNotEmpty) {
      for (final encoding in sendEncodings) {
        _encodings.add(_initializeEncoding(encoding));
      }
    } else {
      // Default single encoding without RID
      _encodings.add(_initializeEncoding(RTCRtpEncodingParameters()));
    }

    // Generate initial transaction ID
    _transactionId = _generateTransactionId();

    if (_track != null) {
      _attachTrack(_track!);
    }
  }

  /// Initialize an encoding with SSRC if not set
  RTCRtpEncodingParameters _initializeEncoding(RTCRtpEncodingParameters enc) {
    final ssrc = enc.ssrc ?? _generateSsrc();
    final rtxSsrc = enc.rtxSsrc ?? _generateSsrc();
    return enc.copyWith(ssrc: ssrc, rtxSsrc: rtxSsrc);
  }

  /// Generate a unique SSRC
  static int _generateSsrc() {
    _ssrcCounter++;
    // Generate random SSRC in valid range (avoid 0 and very high values)
    return (DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF) + _ssrcCounter;
  }

  /// Generate a unique transaction ID
  static String _generateTransactionId() {
    _transactionCounter++;
    return 'tx_${DateTime.now().millisecondsSinceEpoch}_$_transactionCounter';
  }

  /// Get current send parameters
  ///
  /// Returns the current parameters including all encoding layers.
  /// The returned object includes a transactionId that must be
  /// unchanged when calling setParameters().
  RTCRtpSendParameters getParameters() {
    // Generate new transaction ID for this get/set cycle
    _transactionId = _generateTransactionId();

    return RTCRtpSendParameters(
      transactionId: _transactionId,
      encodings: _encodings.map((e) => e.copyWith()).toList(),
      codecs: [
        RTCRtpCodecParameters(
          payloadType: codec.payloadType ?? 96,
          mimeType: codec.mimeType,
          clockRate: codec.clockRate,
          channels: codec.channels,
        ),
      ],
    );
  }

  /// Set send parameters
  ///
  /// Updates the encoding parameters. The transactionId must match
  /// the one from the last getParameters() call.
  ///
  /// Throws [StateError] if:
  /// - Transaction ID doesn't match
  /// - Number of encodings changed
  /// - RIDs changed
  Future<void> setParameters(RTCRtpSendParameters params) async {
    // Validate transaction ID
    if (params.transactionId != _transactionId) {
      throw StateError(
        'Invalid transactionId: expected $_transactionId, got ${params.transactionId}',
      );
    }

    // Validate encoding count
    if (params.encodings.length != _encodings.length) {
      throw StateError(
        'Cannot change number of encodings: was ${_encodings.length}, got ${params.encodings.length}',
      );
    }

    // Validate RIDs haven't changed
    for (var i = 0; i < _encodings.length; i++) {
      if (params.encodings[i].rid != _encodings[i].rid) {
        throw StateError(
          'Cannot change RID at index $i: was ${_encodings[i].rid}, got ${params.encodings[i].rid}',
        );
      }
    }

    // Apply changes to mutable properties
    for (var i = 0; i < _encodings.length; i++) {
      final newEnc = params.encodings[i];
      _encodings[i].active = newEnc.active;
      _encodings[i].maxBitrate = newEnc.maxBitrate;
      _encodings[i].maxFramerate = newEnc.maxFramerate;
      _encodings[i].scaleResolutionDownBy = newEnc.scaleResolutionDownBy;
      _encodings[i].priority = newEnc.priority;
      _encodings[i].networkPriority = newEnc.networkPriority;
      _encodings[i].scalabilityMode = newEnc.scalabilityMode;
    }

    // Invalidate transaction ID (must call getParameters again)
    _transactionId = '';
  }

  /// Get active encodings (encodings where active == true)
  List<RTCRtpEncodingParameters> get activeEncodings =>
      _encodings.where((e) => e.active).toList();

  /// Get all encodings
  List<RTCRtpEncodingParameters> get encodings => List.unmodifiable(_encodings);

  /// Check if simulcast is enabled (more than one encoding)
  bool get isSimulcast => _encodings.length > 1;

  /// Get encoding by RID
  RTCRtpEncodingParameters? getEncodingByRid(String rid) {
    for (final enc in _encodings) {
      if (enc.rid == rid) return enc;
    }
    return null;
  }

  /// Set encoding active state by RID
  void setEncodingActive(String rid, bool active) {
    final enc = getEncodingByRid(rid);
    if (enc != null) {
      enc.active = active;
    }
  }

  /// Select a single encoding layer by RID
  ///
  /// Disables all other encodings and enables only the specified one.
  /// Useful for bandwidth-limited scenarios where only one layer should be sent.
  ///
  /// Returns true if the layer was found and selected, false otherwise.
  bool selectLayer(String rid) {
    bool found = false;
    for (final enc in _encodings) {
      if (enc.rid == rid) {
        enc.active = true;
        found = true;
      } else {
        enc.active = false;
      }
    }
    return found;
  }

  /// Enable all encoding layers
  ///
  /// Useful when bandwidth improves and all layers should be sent.
  void enableAllLayers() {
    for (final enc in _encodings) {
      enc.active = true;
    }
  }

  /// Disable all encoding layers
  ///
  /// Effectively pauses sending without removing the track.
  void disableAllLayers() {
    for (final enc in _encodings) {
      enc.active = false;
    }
  }

  /// Select layers up to a maximum bitrate
  ///
  /// Enables encoding layers whose maxBitrate is at or below the specified
  /// limit, and disables layers above it. Useful for adaptive bitrate control.
  ///
  /// Example: selectLayersByMaxBitrate(500000) would enable layers with
  /// maxBitrate <= 500kbps and disable higher bitrate layers.
  ///
  /// Returns the number of layers enabled.
  int selectLayersByMaxBitrate(int maxBitrateBps) {
    int enabled = 0;
    for (final enc in _encodings) {
      if (enc.maxBitrate == null || enc.maxBitrate! <= maxBitrateBps) {
        enc.active = true;
        enabled++;
      } else {
        enc.active = false;
      }
    }
    return enabled;
  }

  /// Select layers by resolution scale factor
  ///
  /// Enables layers whose scaleResolutionDownBy is at or above the specified
  /// minimum scale (lower resolution = higher scale factor = less bandwidth).
  ///
  /// Example: selectLayersByMinScale(2.0) enables only half-resolution or lower.
  ///
  /// Returns the number of layers enabled.
  int selectLayersByMinScale(double minScale) {
    int enabled = 0;
    for (final enc in _encodings) {
      final scale = enc.scaleResolutionDownBy ?? 1.0;
      if (scale >= minScale) {
        enc.active = true;
        enabled++;
      } else {
        enc.active = false;
      }
    }
    return enabled;
  }

  /// Get summary of layer states
  ///
  /// Returns a map of RID to active state for debugging/UI display.
  Map<String?, bool> get layerStates {
    return {for (final enc in _encodings) enc.rid: enc.active};
  }

  /// Get current track
  MediaStreamTrack? get track => _track;

  /// Replace track
  /// Replaces the current track with a new one without renegotiation.
  /// The new track must be of the same kind (audio/video) as the original.
  /// Pass null to stop sending without removing the sender.
  Future<void> replaceTrack(MediaStreamTrack? newTrack) async {
    // Check if sender is stopped
    if (_stopped) {
      throw StateError('Cannot replace track on stopped sender');
    }

    // Validate track kind compatibility
    if (newTrack != null && _track != null && newTrack.kind != _track!.kind) {
      throw ArgumentError(
        'New track kind (${newTrack.kind}) must match original kind (${_track!.kind})',
      );
    }

    // Validate track is not stopped
    if (newTrack != null && newTrack.state == MediaStreamTrackState.ended) {
      throw ArgumentError('Cannot replace with an ended track');
    }

    // Detach old track if present
    if (_track != null) {
      await _detachTrack();
    }

    _track = newTrack;

    // Attach new track if present
    if (_track != null) {
      _attachTrack(_track!);
    }
  }

  /// Attach track and start sending
  void _attachTrack(MediaStreamTrack track) {
    if (track is AudioStreamTrack) {
      _trackSubscription = track.onAudioFrame.listen(_handleAudioFrame);
    } else if (track is VideoStreamTrack) {
      _trackSubscription = track.onVideoFrame.listen(_handleVideoFrame);
    }
  }

  /// Detach track and stop sending
  Future<void> _detachTrack() async {
    await _trackSubscription?.cancel();
    _trackSubscription = null;
  }

  /// Handle audio frame from track
  void _handleAudioFrame(AudioFrame frame) async {
    if (_stopped || !track!.enabled) return;

    // For Opus: Create RTP payload without actual encoding
    // In production, this would call an Opus encoder
    // For testing, we create a dummy Opus frame (20ms @ 48kHz = 960 samples)
    final dummyOpusFrame = Uint8List(20); // Typical Opus frame size

    final opusPayload = OpusRtpPayload(payload: dummyOpusFrame);
    final payload = opusPayload.serialize();

    await rtpSession.sendRtp(
      payloadType: codec.payloadType ?? 111, // Opus typically uses PT 111
      payload: payload,
      timestampIncrement: (frame.durationUs * codec.clockRate) ~/ 1000000,
    );
  }

  /// Handle video frame from track
  /// Note: This method handles raw VideoFrame data, which requires video encoding
  /// (VP8, H264, VP9, AV1, etc.) before it can be sent as RTP.
  ///
  /// werift-webrtc does not implement video encoding - it expects pre-encoded RTP
  /// packets via track.writeRtp() (using FFmpeg or other external encoders).
  /// See: werift-webrtc/examples/mediachannel/sendonly/ffmpeg.ts
  ///
  /// For sending pre-encoded video, use the nonstandard MediaStreamTrack.writeRtp()
  /// method with RTP packets from an external encoder (FFmpeg, GStreamer, etc.).
  /// See: examples/ffmpeg_video_send.dart
  void _handleVideoFrame(VideoFrame frame) async {
    if (_stopped || !track!.enabled) return;

    // Raw video frame encoding is not implemented (matching werift behavior).
    // Use track.writeRtp() with pre-encoded RTP packets instead.
    // This placeholder sends empty payload which receivers will drop.

    final payload = Uint8List(0);

    await rtpSession.sendRtp(
      payloadType: codec.payloadType ?? 96,
      payload: payload,
      timestampIncrement: 3000, // ~30fps at 90kHz clock
    );
  }

  /// Stop sending
  void stop() {
    if (!_stopped) {
      _stopped = true;
      _detachTrack();
    }
  }

  @override
  String toString() {
    final encStr = _encodings.map((e) => e.rid ?? 'default').join(',');
    return 'RtpSender(track=${track?.id}, codec=${codec.codecName}, encodings=[$encStr])';
  }
}

/// RTP Receiver
/// Receives RTP packets for an incoming media track
/// Supports simulcast by managing multiple tracks by RID
class RtpReceiver {
  /// Primary media track for received data (non-simulcast)
  final MediaStreamTrack track;

  /// RTP session for receiving
  final RtpSession rtpSession;

  /// Codec parameters
  final RtpCodecParameters codec;

  /// Tracks by RID (for simulcast)
  final Map<String, MediaStreamTrack> _trackByRid = {};

  /// Tracks by SSRC
  final Map<int, MediaStreamTrack> _trackBySsrc = {};

  /// Stream subscription for RTP packets
  StreamSubscription? _rtpSubscription;

  /// Stopped flag
  bool _stopped = false;

  /// Latest RID received (for simulcast)
  String? latestRid;

  /// Latest repaired RID (for RTX in simulcast)
  String? latestRepairedRid;

  /// SDES MID from RTP header extension
  String? sdesMid;

  /// SVC filter for VP9 layer filtering
  Vp9SvcFilter? _svcFilter;

  /// Scalability mode (from SDP or encoding parameters)
  ScalabilityMode? _scalabilityMode;

  /// Callback when a new track is created for a simulcast layer
  void Function(MediaStreamTrack track)? onTrack;

  RtpReceiver({
    required this.track,
    required this.rtpSession,
    required this.codec,
  }) {
    // Set up callback for incoming RTP packets
    // Note: We can't use onReceiveRtp stream since it's a callback, not a stream
    // The RtpSession will need to be created with our handler, or we need
    // to expose a stream from RtpSession
    // For now, this is a placeholder - the actual wiring happens in PeerConnection
  }

  /// Get track by RID (for simulcast)
  MediaStreamTrack? getTrackByRid(String rid) => _trackByRid[rid];

  /// Get track by SSRC
  MediaStreamTrack? getTrackBySsrc(int ssrc) => _trackBySsrc[ssrc];

  /// Get all tracks (including simulcast layers)
  List<MediaStreamTrack> get allTracks {
    final tracks = <MediaStreamTrack>[track];
    tracks.addAll(_trackByRid.values);
    return tracks;
  }

  /// Add a track for a simulcast layer
  void addTrackForRid(String rid, MediaStreamTrack track) {
    _trackByRid[rid] = track;
  }

  /// Associate an SSRC with a track
  void associateSsrcWithTrack(int ssrc, MediaStreamTrack track) {
    _trackBySsrc[ssrc] = track;
  }

  /// Handle received RTP packet (package-private)
  void handleRtpPacket(RtpPacket packet) {
    if (_stopped) return;
    _processPacket(packet, track);
  }

  /// Handle RTP packet by RID (for simulcast)
  void handleRtpByRid(
    RtpPacket packet,
    String rid,
    Map<String, dynamic> extensions,
  ) {
    if (_stopped) return;

    latestRid = rid;

    // Get or create track for this RID
    var ridTrack = _trackByRid[rid];
    if (ridTrack == null) {
      // Create new track for this simulcast layer
      ridTrack = _createTrackForRid(rid);
      _trackByRid[rid] = ridTrack;
      _trackBySsrc[packet.ssrc] = ridTrack;
      onTrack?.call(ridTrack);
    }

    _processPacket(packet, ridTrack);
  }

  /// Handle RTP packet by SSRC
  void handleRtpBySsrc(RtpPacket packet, Map<String, dynamic> extensions) {
    if (_stopped) return;

    final ssrc = packet.ssrc;
    var ssrcTrack = _trackBySsrc[ssrc];

    if (ssrcTrack == null) {
      // Unknown SSRC - use primary track
      ssrcTrack = track;
      _trackBySsrc[ssrc] = ssrcTrack;
    }

    _processPacket(packet, ssrcTrack);
  }

  /// Create a track for a simulcast layer
  MediaStreamTrack _createTrackForRid(String rid) {
    if (track.kind == MediaStreamTrackKind.audio) {
      return AudioStreamTrack(
        id: '${track.id}_$rid',
        label: '${track.label} ($rid)',
        rid: rid,
      );
    } else {
      return VideoStreamTrack(
        id: '${track.id}_$rid',
        label: '${track.label} ($rid)',
        rid: rid,
      );
    }
  }

  /// Process an RTP packet and deliver to track
  void _processPacket(RtpPacket packet, MediaStreamTrack targetTrack) {
    // Depacketize RTP payload based on codec
    if (targetTrack is AudioStreamTrack &&
        codec.codecName.toLowerCase() == 'opus') {
      final audioTrack = targetTrack;

      // Deserialize Opus payload from RTP packet
      // In production, would decode the payload with Opus decoder:
      // final opusPayload = OpusRtpPayload.deserialize(packet.payload);
      // For testing, create empty frame to demonstrate the pipeline works
      final frame = AudioFrame(
        samples: [], // Would contain decoded PCM samples
        sampleRate: codec.clockRate,
        channels: codec.channels ?? 1,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      );
      audioTrack.sendAudioFrame(frame);
    } else if (targetTrack is VideoStreamTrack) {
      final videoTrack = targetTrack;

      // For VP9 with SVC, apply layer filtering
      if (isVp9Svc && _svcFilter != null) {
        final vp9Payload = Vp9RtpPayload.deserialize(packet.payload);

        // Check if this packet should be forwarded based on layer selection
        if (!_svcFilter!.filter(vp9Payload)) {
          // Packet filtered out - don't forward to track
          return;
        }

        // VP9 depacketization would happen here
        final frame = VideoFrame(
          data: vp9Payload.payload.toList(),
          width: 640, // Would be from header
          height: 480, // Would be from header
          timestamp: DateTime.now().microsecondsSinceEpoch,
          format: codec.codecName,
          keyframe: vp9Payload.isKeyframe,
          spatialId: vp9Payload.sid,
          temporalId: vp9Payload.tid,
        );
        videoTrack.sendVideoFrame(frame);
      } else {
        // Non-VP9 or no SVC filter - forward all packets
        final frame = VideoFrame(
          data: [],
          width: 640,
          height: 480,
          timestamp: DateTime.now().microsecondsSinceEpoch,
          format: codec.codecName,
        );
        videoTrack.sendVideoFrame(frame);
      }
    }
  }

  // ==========================================================================
  // VP9 SVC Layer Selection API
  // ==========================================================================

  /// Check if this receiver is receiving VP9 with SVC
  bool get isVp9Svc => codec.codecName.toLowerCase() == 'vp9';

  /// Get the SVC filter (creates it on first access for VP9)
  Vp9SvcFilter? get svcFilter {
    if (!isVp9Svc) return null;
    _svcFilter ??= Vp9SvcFilter();
    return _svcFilter;
  }

  /// Set scalability mode (typically from SDP a=scalability-mode)
  void setScalabilityMode(String mode) {
    _scalabilityMode = ScalabilityMode.parse(mode);
  }

  /// Get current scalability mode
  ScalabilityMode? get scalabilityMode => _scalabilityMode;

  /// Select maximum spatial layer (0 = base only)
  ///
  /// For VP9 SVC, this controls which spatial layers are forwarded.
  /// Higher spatial layers = higher resolution.
  void selectSpatialLayer(int maxSid, {bool immediate = false}) {
    svcFilter?.selectSpatialLayer(maxSid, immediate: immediate);
  }

  /// Select maximum temporal layer (0 = base only)
  ///
  /// For VP9 SVC, this controls which temporal layers are forwarded.
  /// Higher temporal layers = smoother motion (higher frame rate).
  void selectTemporalLayer(int maxTid, {bool immediate = false}) {
    svcFilter?.selectTemporalLayer(maxTid, immediate: immediate);
  }

  /// Select layers by target bitrate
  ///
  /// Automatically selects appropriate spatial/temporal layers based on
  /// available bandwidth. Requires scalability mode to be set.
  void selectLayersByBitrate(int targetBitrateBps, {bool immediate = false}) {
    if (_scalabilityMode != null && svcFilter != null) {
      svcFilter!.selectByBitrate(
        targetBitrateBps,
        _scalabilityMode!,
        immediate: immediate,
      );
    }
  }

  /// Set layer selection directly
  void setLayerSelection(
    SvcLayerSelection selection, {
    bool immediate = false,
  }) {
    svcFilter?.setSelection(selection, immediate: immediate);
  }

  /// Get current layer selection
  SvcLayerSelection? get layerSelection => svcFilter?.selection;

  /// Check if waiting for keyframe to complete layer switch
  bool get isWaitingForKeyframe => svcFilter?.isWaitingForKeyframe ?? false;

  /// Get SVC filter statistics
  SvcFilterStats? get svcStats => svcFilter?.stats;

  /// Reset SVC filter state
  void resetSvcFilter() {
    svcFilter?.reset();
  }

  /// Stop receiving
  void stop() {
    if (!_stopped) {
      _stopped = true;
      _rtpSubscription?.cancel();
      track.stop();
      for (final ridTrack in _trackByRid.values) {
        ridTrack.stop();
      }
    }
  }

  @override
  String toString() {
    final ridCount = _trackByRid.length;
    final svcInfo = _svcFilter != null ? ', svc=enabled' : '';
    return 'RtpReceiver(track=${track.id}, codec=${codec.codecName}, simulcast=$ridCount$svcInfo)';
  }
}

/// Create audio transceiver
RtpTransceiver createAudioTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
  List<RTCRtpEncodingParameters>? sendEncodings,
}) {
  final codec = createOpusCodec(payloadType: 111);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: codec,
    sendEncodings: sendEncodings,
  );
  sender.mid = mid;

  // Create receive track
  final receiveTrack = AudioStreamTrack(
    id: 'audio_recv_$mid',
    label: 'Audio Receiver',
  );

  final receiver = RtpReceiver(
    track: receiveTrack,
    rtpSession: rtpSession,
    codec: codec,
  );

  return RtpTransceiver(
    kind: MediaStreamTrackKind.audio,
    mid: mid,
    sender: sender,
    receiver: receiver,
    direction: direction,
  );
}

/// Create video transceiver
///
/// For simulcast, pass sendEncodings with multiple RTCRtpEncodingParameters.
/// Each encoding can have a RID and different quality settings.
///
/// Example for simulcast:
/// ```dart
/// createVideoTransceiver(
///   mid: '1',
///   rtpSession: session,
///   sendTrack: videoTrack,
///   sendEncodings: [
///     RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000),
///     RTCRtpEncodingParameters(rid: 'mid', maxBitrate: 500000, scaleResolutionDownBy: 2.0),
///     RTCRtpEncodingParameters(rid: 'low', maxBitrate: 150000, scaleResolutionDownBy: 4.0),
///   ],
/// );
/// ```
RtpTransceiver createVideoTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
  List<RTCRtpEncodingParameters>? sendEncodings,
}) {
  final codec = createVp8Codec(payloadType: 96);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: codec,
    sendEncodings: sendEncodings,
  );
  sender.mid = mid;

  // Create receive track
  final receiveTrack = VideoStreamTrack(
    id: 'video_recv_$mid',
    label: 'Video Receiver',
  );

  final receiver = RtpReceiver(
    track: receiveTrack,
    rtpSession: rtpSession,
    codec: codec,
  );

  return RtpTransceiver(
    kind: MediaStreamTrackKind.video,
    mid: mid,
    sender: sender,
    receiver: receiver,
    direction: direction,
  );
}
