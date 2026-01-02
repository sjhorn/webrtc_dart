import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_receiver.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_sender.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/transport/transport.dart';

// Re-export RtpSender and RtpReceiver for convenience
export 'package:webrtc_dart/src/media/rtc_rtp_sender.dart';
export 'package:webrtc_dart/src/media/rtc_rtp_receiver.dart';

/// RTP Transceiver Direction
enum RtpTransceiverDirection { sendrecv, sendonly, recvonly, inactive }

/// RTP Transceiver
/// Manages sending and receiving RTP for a media track
/// Combines RtpSender and RtpReceiver
class RTCRtpTransceiver {
  /// Media type (audio or video)
  final MediaStreamTrackKind kind;

  /// Media ID (mid) - unique identifier in SDP
  /// Null until assigned during offer/answer negotiation.
  /// This matches werift behavior where mid is undefined until SDP exchange.
  String? _mid;

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

  /// Associated transport (for bundlePolicy: disable support)
  /// When bundlePolicy is disable, each transceiver has its own transport.
  /// When bundlePolicy is max-bundle, all transceivers share the same transport.
  MediaTransport? _transport;

  /// M-line index in SDP (position in media sections)
  int? mLineIndex;

  /// All codecs for SDP negotiation (RED, Opus, etc.)
  /// The primary sending codec is still sender.codec
  List<RtpCodecParameters> codecs = [];

  RTCRtpTransceiver({
    required this.kind,
    String? mid,
    required this.sender,
    required this.receiver,
    RtpTransceiverDirection? direction,
    List<RTCRtpSimulcastParameters>? simulcast,
    MediaTransport? transport,
    this.mLineIndex,
  })  : _mid = mid,
        _direction = direction ?? RtpTransceiverDirection.sendrecv,
        _transport = transport {
    if (simulcast != null) {
      _simulcast.addAll(simulcast);
    }
  }

  /// Get MID (may be null before SDP negotiation)
  String? get mid => _mid;

  /// Set MID (called during SDP negotiation to assign or update)
  set mid(String? value) {
    _mid = value;
    // Also update sender's mid for RTP header extension
    if (value != null) {
      sender.mid = value;
    }
  }

  /// Get the associated transport
  MediaTransport? get transport => _transport;

  /// Set the associated transport
  void setTransport(MediaTransport transport) {
    _transport = transport;
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

/// Create audio transceiver
RtpTransceiver createAudioTransceiver({
  required String mid,
  required RtpSession rtpSession,
  MediaStreamTrack? sendTrack,
  RtpTransceiverDirection? direction,
  List<RTCRtpEncodingParameters>? sendEncodings,
  RtpCodecParameters? codec,
}) {
  final effectiveCodec = codec ?? createOpusCodec(payloadType: 111);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
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
    codec: effectiveCodec,
  );

  return RTCRtpTransceiver(
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
  RtpCodecParameters? codec,
}) {
  final effectiveCodec = codec ?? createVp8Codec(payloadType: 96);

  final sender = RtpSender(
    track: sendTrack,
    rtpSession: rtpSession,
    codec: effectiveCodec,
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
    codec: effectiveCodec,
  );

  return RTCRtpTransceiver(
    kind: MediaStreamTrackKind.video,
    mid: mid,
    sender: sender,
    receiver: receiver,
    direction: direction,
  );
}

// =============================================================================
// Backward Compatibility TypeDef
// =============================================================================

/// @deprecated Use RTCRtpTransceiver instead
@Deprecated('Use RTCRtpTransceiver instead')
typedef RtpTransceiver = RTCRtpTransceiver;
