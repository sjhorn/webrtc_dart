/// RTP Codec Parameters
/// RFC 8829 - JavaScript Session Establishment Protocol (JSEP)
class RtpCodecParameters {
  /// MIME type (e.g., "audio/opus", "video/VP8")
  final String mimeType;

  /// Clock rate in Hz
  final int clockRate;

  /// Number of audio channels (for audio codecs only)
  final int? channels;

  /// Payload type (dynamic range 96-127, or static for PCMU/PCMA)
  final int? payloadType;

  /// Codec-specific parameters (e.g., "profile-level-id=42e01f")
  final String? parameters;

  /// RTCP feedback mechanisms
  final List<RtcpFeedback> rtcpFeedback;

  const RtpCodecParameters({
    required this.mimeType,
    required this.clockRate,
    this.channels,
    this.payloadType,
    this.parameters,
    this.rtcpFeedback = const [],
  });

  /// Get codec name from MIME type
  String get codecName {
    final parts = mimeType.split('/');
    return parts.length == 2 ? parts[1] : mimeType;
  }

  /// Check if this is an audio codec
  bool get isAudio => mimeType.toLowerCase().startsWith('audio/');

  /// Check if this is a video codec
  bool get isVideo => mimeType.toLowerCase().startsWith('video/');

  @override
  String toString() {
    return 'RtpCodecParameters(mimeType=$mimeType, clockRate=$clockRate${channels != null ? ', channels=$channels' : ''})';
  }
}

/// RTCP Feedback mechanism
class RtcpFeedback {
  /// Feedback type (e.g., "nack", "pli", "goog-remb")
  final String type;

  /// Feedback parameter (optional)
  final String? parameter;

  const RtcpFeedback({
    required this.type,
    this.parameter,
  });

  @override
  String toString() {
    return parameter != null ? '$type $parameter' : type;
  }
}

/// Common RTCP feedback types
class RtcpFeedbackTypes {
  /// Negative Acknowledgement
  static const nack = RtcpFeedback(type: 'nack');

  /// Picture Loss Indication
  static const pli = RtcpFeedback(type: 'nack', parameter: 'pli');

  /// Google Receiver Estimated Maximum Bitrate
  static const remb = RtcpFeedback(type: 'goog-remb');

  /// Transport-wide Congestion Control
  static const transportCC = RtcpFeedback(type: 'transport-cc');
}

/// Opus codec parameters
/// RFC 7587 - RTP Payload Format for the Opus Speech and Audio Codec
RtpCodecParameters createOpusCodec({
  int? payloadType,
  int clockRate = 48000,
  int channels = 2,
  List<RtcpFeedback> rtcpFeedback = const [],
}) {
  return RtpCodecParameters(
    mimeType: 'audio/opus',
    clockRate: clockRate,
    channels: channels,
    payloadType: payloadType,
    rtcpFeedback: rtcpFeedback,
  );
}

/// PCMU (G.711 μ-law) codec parameters
/// RFC 3551 - RTP Profile for Audio and Video Conferences
RtpCodecParameters createPcmuCodec({
  List<RtcpFeedback> rtcpFeedback = const [],
}) {
  return RtpCodecParameters(
    mimeType: 'audio/PCMU',
    clockRate: 8000,
    channels: 1,
    payloadType: 0, // Static payload type
    rtcpFeedback: rtcpFeedback,
  );
}

/// VP8 codec parameters
/// RFC 7741 - RTP Payload Format for VP8 Video
RtpCodecParameters createVp8Codec({
  int? payloadType,
  List<RtcpFeedback>? rtcpFeedback,
}) {
  return RtpCodecParameters(
    mimeType: 'video/VP8',
    clockRate: 90000,
    payloadType: payloadType,
    rtcpFeedback: rtcpFeedback ??
        [
          RtcpFeedbackTypes.nack,
          RtcpFeedbackTypes.pli,
          RtcpFeedbackTypes.remb,
        ],
  );
}

/// VP9 codec parameters
/// Draft - RTP Payload Format for VP9 Video
RtpCodecParameters createVp9Codec({
  int? payloadType,
  List<RtcpFeedback>? rtcpFeedback,
}) {
  return RtpCodecParameters(
    mimeType: 'video/VP9',
    clockRate: 90000,
    payloadType: payloadType,
    rtcpFeedback: rtcpFeedback ??
        [
          RtcpFeedbackTypes.nack,
          RtcpFeedbackTypes.pli,
          RtcpFeedbackTypes.remb,
        ],
  );
}

/// H.264 codec parameters
/// RFC 6184 - RTP Payload Format for H.264 Video
RtpCodecParameters createH264Codec({
  int? payloadType,
  String parameters =
      'profile-level-id=42e01f;packetization-mode=1;level-asymmetry-allowed=1',
  List<RtcpFeedback>? rtcpFeedback,
}) {
  return RtpCodecParameters(
    mimeType: 'video/H264',
    clockRate: 90000,
    payloadType: payloadType,
    parameters: parameters,
    rtcpFeedback: rtcpFeedback ??
        [
          RtcpFeedbackTypes.nack,
          RtcpFeedbackTypes.pli,
          RtcpFeedbackTypes.remb,
        ],
  );
}

/// List of supported audio codecs
final List<RtpCodecParameters> supportedAudioCodecs = [
  createOpusCodec(),
  createPcmuCodec(),
];

/// List of supported video codecs
final List<RtpCodecParameters> supportedVideoCodecs = [
  createVp8Codec(),
  createVp9Codec(),
  createH264Codec(),
];

/// List of all supported codecs
final List<RtpCodecParameters> supportedCodecs = [
  ...supportedAudioCodecs,
  ...supportedVideoCodecs,
];
