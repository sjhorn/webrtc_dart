import 'dart:async';

import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/codec/vp9.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/svc_manager.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

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
    // Always emit raw RTP packet for forwarding/relaying use cases
    targetTrack.receiveRtp(packet);

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
