import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/codec/opus.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

/// RTP Sender
/// Sends RTP packets for an outgoing media track
/// Supports simulcast with multiple encoding layers
class RtpSender {
  /// Media track being sent (null if no track)
  MediaStreamTrack? _track;

  /// Nonstandard track for pre-encoded RTP (like TypeScript werift)
  nonstandard.MediaStreamTrack? _nonstandardTrack;

  /// RTP session for sending
  final RtpSession rtpSession;

  /// Codec parameters (can be updated from SDP negotiation)
  RtpCodecParameters codec;

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

  /// Absolute Send Time header extension ID (set from SDP negotiation)
  int? absSendTimeExtensionId;

  /// Transport-Wide CC header extension ID (set from SDP negotiation)
  int? transportWideCCExtensionId;

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

  /// Get nonstandard track (for pre-encoded RTP like werift)
  nonstandard.MediaStreamTrack? get nonstandardTrack => _nonstandardTrack;

  /// Register a nonstandard track for pre-encoded RTP
  ///
  /// This matches the TypeScript werift registerTrack() behavior:
  /// subscribes to track.onReceiveRtp and forwards packets through sendRtp.
  /// Used for forwarding pre-encoded RTP (e.g., from Ring cameras, FFmpeg).
  ///
  /// Example:
  /// ```dart
  /// final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
  /// sender.registerNonstandardTrack(track);
  /// // Later, from Ring camera:
  /// ringCamera.onVideoRtp.listen((rtp) => track.writeRtp(rtp));
  /// ```
  void registerNonstandardTrack(nonstandard.MediaStreamTrack track) {
    if (track.stopped) {
      throw StateError('Track is already stopped');
    }

    // Detach any existing track
    _detachTrack();
    _track = null;
    _nonstandardTrack = track;

    // Attach the nonstandard track
    _attachNonstandardTrack(track);
  }

  /// Register a track for RTP forwarding (echo/loopback)
  ///
  /// This matches the TypeScript werift registerTrack() behavior exactly:
  /// subscribes to track.onReceiveRtp and forwards packets through sendRtp.
  /// Used for echo/loopback scenarios where you want to forward received RTP
  /// back to the sender.
  ///
  /// This is different from replaceTrack which subscribes to audio/video frames.
  /// This method subscribes to raw RTP packets for forwarding.
  ///
  /// Example (echo server):
  /// ```dart
  /// pc.onTrack.listen((transceiver) {
  ///   final receivedTrack = transceiver.receiver.track;
  ///   transceiver.sender.registerTrackForForward(receivedTrack);
  /// });
  /// ```
  void registerTrackForForward(MediaStreamTrack track) {
    if (track.state == MediaStreamTrackState.ended) {
      throw StateError('Track is already ended');
    }

    // Detach any existing track
    _detachTrack();
    _nonstandardTrack = null;
    _track = track;

    // Subscribe to onReceiveRtp and forward packets (like werift registerTrack)
    _trackSubscription = track.onReceiveRtp.listen((rtpPacket) async {
      if (_stopped) return;

      // Build header extension config at SEND TIME
      final extensionConfig = HeaderExtensionConfig(
        sdesMidId: midExtensionId,
        mid: mid,
        absSendTimeId: absSendTimeExtensionId,
        transportWideCCId: transportWideCCExtensionId,
      );

      // Forward the RTP packet
      await rtpSession.sendRawRtpPacket(
        rtpPacket,
        replaceSsrc: true,
        payloadType: codec.payloadType,
        extensionConfig: extensionConfig,
      );
    });
  }

  /// Forward a list of cached RTP packets (e.g., cached keyframe)
  ///
  /// This is useful for sending cached keyframes to new subscribers
  /// before starting live forwarding. Each packet is sent with:
  /// - SSRC replaced with sender's SSRC
  /// - Header extensions regenerated (MID, abs-send-time, transport-cc)
  Future<void> forwardCachedPackets(List<RtpPacket> packets) async {
    if (_stopped) return;

    final extensionConfig = HeaderExtensionConfig(
      sdesMidId: midExtensionId,
      mid: mid,
      absSendTimeId: absSendTimeExtensionId,
      transportWideCCId: transportWideCCExtensionId,
    );

    for (final packet in packets) {
      await rtpSession.sendRawRtpPacket(
        packet,
        replaceSsrc: true,
        payloadType: codec.payloadType,
        extensionConfig: extensionConfig,
      );
    }
  }

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
  ///
  /// Matches TypeScript werift registerTrack() behavior:
  /// - For nonstandard tracks: subscribes to onReceiveRtp and forwards to sendRtp
  /// - For standard tracks: subscribes to onAudioFrame/onVideoFrame
  void _attachTrack(MediaStreamTrack track) {
    if (track is AudioStreamTrack) {
      _trackSubscription = track.onAudioFrame.listen(_handleAudioFrame);
    } else if (track is VideoStreamTrack) {
      _trackSubscription = track.onVideoFrame.listen(_handleVideoFrame);
    }
  }

  /// Attach a nonstandard track (for pre-encoded RTP)
  ///
  /// This matches the TypeScript werift registerTrack() behavior:
  /// subscribes to track.onReceiveRtp and forwards packets through sendRtp.
  /// Used for forwarding pre-encoded RTP (e.g., from Ring cameras, FFmpeg).
  ///
  /// Like TypeScript werift, we rewrite the payload type to match the negotiated
  /// codec. This is essential because the source (e.g., Ring camera) may use
  /// a different payload type than what was negotiated with the browser.
  ///
  /// Header extensions (mid, abs-send-time, transport-cc) are regenerated using
  /// HeaderExtensionConfig, matching werift rtpSender.ts:sendRtp behavior.
  int? _primarySsrc; // Track the primary SSRC to filter RTX/probing packets
  int?
      _actualPayloadType; // Track the actual PT used by the remote (may differ from codec.payloadType)

  void _attachNonstandardTrack(nonstandard.MediaStreamTrack track) {
    _trackSubscription = track.onReceiveRtp.listen((event) async {
      if (_stopped) return;

      final (rtp, _) = event;

      // Filter RTX and probing packets:
      // - RTX packets use a different payload type (marked in SDP with rtx attribute)
      // - Probing packets often have ts=0 and come early in stream
      // - We want to forward the primary video stream only
      //
      // RTX payload types are typically the main codec PT + 1 (e.g., VP8=96, VP8-RTX=97)
      // Also skip padding probes (ts=0, small payload)
      final isProbing = rtp.timestamp == 0 && rtp.payload.length < 300;
      final isLikelyRtx = rtp.payloadType == (codec.payloadType ?? 96) + 1;

      if (isProbing || isLikelyRtx) {
        return;
      }

      // Lock onto the first non-RTX, non-probing SSRC as primary.
      // This ensures we forward a consistent video stream and ignore
      // packets from other SSRCs (RTX retransmissions, simulcast layers, etc.)
      if (_primarySsrc == null) {
        _primarySsrc = rtp.ssrc;
        // Capture the actual payload type being used by the remote.
        // Chrome may choose a different codec than our default (e.g., AV1 vs VP8).
        _actualPayloadType = rtp.payloadType;
      } else if (rtp.ssrc != _primarySsrc) {
        // Skip packets from non-primary SSRCs
        return;
      }

      // Build header extension config at SEND TIME, not at attachment time
      // This is critical for the answerer pattern where MID is migrated after attachment
      // If we capture mid at attachment time, we'd use the pre-migration MID
      final extensionConfig = HeaderExtensionConfig(
        sdesMidId: midExtensionId,
        mid: mid,
        absSendTimeId: absSendTimeExtensionId,
        transportWideCCId: transportWideCCExtensionId,
      );

      // Forward the RTP packet through the session with extension regeneration
      // sendRawRtpPacket will:
      // - Rewrite SSRC to sender's SSRC
      // - Regenerate header extensions (mid, abs-send-time, transport-cc)
      //
      // For echo scenarios: preserve the incoming payload type since Chrome may
      // choose a different codec than our default (e.g., AV1 instead of VP8).
      // For transcoding scenarios (Ring camera): use codec.payloadType to rewrite.
      //
      // We detect echo scenario by checking if _actualPayloadType was captured.
      final effectivePayloadType = _actualPayloadType ?? codec.payloadType;

      await rtpSession.sendRawRtpPacket(
        rtp,
        replaceSsrc: true,
        payloadType: effectivePayloadType,
        extensionConfig: extensionConfig,
      );
    });
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
