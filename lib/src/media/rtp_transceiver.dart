import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/codec/opus.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

/// RTP Transceiver Direction
enum RtpTransceiverDirection {
  sendrecv,
  sendonly,
  recvonly,
  inactive,
}

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

  /// Desired direction (for negotiation)
  RtpTransceiverDirection _desiredDirection;

  /// Stopped flag
  bool _stopped = false;

  RtpTransceiver({
    required this.kind,
    required this.mid,
    required this.sender,
    required this.receiver,
    RtpTransceiverDirection? direction,
  })  : _direction = direction ?? RtpTransceiverDirection.sendrecv,
        _desiredDirection = direction ?? RtpTransceiverDirection.sendrecv;

  /// Get current direction
  RtpTransceiverDirection get direction => _direction;

  /// Set direction
  set direction(RtpTransceiverDirection value) {
    _desiredDirection = value;
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

  RtpSender({
    MediaStreamTrack? track,
    required this.rtpSession,
    required this.codec,
  }) : _track = track {
    if (_track != null) {
      _attachTrack(_track!);
    }
  }

  /// Get current track
  MediaStreamTrack? get track => _track;

  /// Replace track
  Future<void> replaceTrack(MediaStreamTrack? newTrack) async {
    if (_track != null) {
      await _detachTrack();
    }

    _track = newTrack;

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
  void _handleVideoFrame(VideoFrame frame) async {
    if (_stopped || !track!.enabled) return;

    // TODO: Encode video frame to codec format (VP8, H264, etc.)
    // For now, placeholder implementation

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
    return 'RtpSender(track=${track?.id}, codec=${codec.codecName})';
  }
}

/// RTP Receiver
/// Receives RTP packets for an incoming media track
class RtpReceiver {
  /// Media track for received data
  final MediaStreamTrack track;

  /// RTP session for receiving
  final RtpSession rtpSession;

  /// Codec parameters
  final RtpCodecParameters codec;

  /// Stream subscription for RTP packets
  StreamSubscription? _rtpSubscription;

  /// Stopped flag
  bool _stopped = false;

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

  /// Handle received RTP packet (package-private)
  void handleRtpPacket(RtpPacket packet) {
    if (_stopped) return;

    // Depacketize RTP payload based on codec
    if (track is AudioStreamTrack && codec.codecName.toLowerCase() == 'opus') {
      final audioTrack = track as AudioStreamTrack;

      // Deserialize Opus payload from RTP packet
      final opusPayload = OpusRtpPayload.deserialize(packet.payload);

      // In production, would decode opusPayload.payload with Opus decoder
      // For testing, create empty frame to demonstrate the pipeline works
      final frame = AudioFrame(
        samples: [], // Would contain decoded PCM samples
        sampleRate: codec.clockRate,
        channels: codec.channels ?? 1,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      );
      audioTrack.sendAudioFrame(frame);
    } else if (track is VideoStreamTrack) {
      final videoTrack = track as VideoStreamTrack;
      // TODO: Add VP8/H264 depacketization
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

  /// Stop receiving
  void stop() {
    if (!_stopped) {
      _stopped = true;
      _rtpSubscription?.cancel();
      track.stop();
    }
  }

  @override
  String toString() {
    return 'RtpReceiver(track=${track.id}, codec=${codec.codecName})';
  }
}

/// Create audio transceiver
RtpTransceiver createAudioTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
}) {
  final codec = createOpusCodec(payloadType: 111);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: codec,
  );

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
RtpTransceiver createVideoTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
}) {
  final codec = createVp8Codec(payloadType: 96);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: codec,
  );

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
