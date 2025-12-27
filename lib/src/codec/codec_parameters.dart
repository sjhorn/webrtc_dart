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

/// RED (Redundant Audio Data) codec parameters
/// RFC 2198 - RTP Payload for Redundant Audio Data
///
/// RED provides forward error correction by including redundant copies
/// of previous audio frames in each packet. This allows recovery from
/// packet loss without retransmission delay.
RtpCodecParameters createRedCodec({
  int? payloadType,
  int clockRate = 48000,
  int channels = 2,
}) {
  return RtpCodecParameters(
    mimeType: 'audio/red',
    clockRate: clockRate,
    channels: channels,
    payloadType: payloadType,
  );
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

/// AV1 codec parameters
/// https://aomediacodec.github.io/av1-rtp-spec/
RtpCodecParameters createAv1Codec({
  int? payloadType,
  List<RtcpFeedback>? rtcpFeedback,
}) {
  return RtpCodecParameters(
    mimeType: 'video/AV1',
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

/// RTX (Retransmission) codec parameters
/// RFC 4588 - RTP Retransmission Payload Format
///
/// RTX provides retransmission of lost packets using a separate SSRC
/// and payload type. The associated payload type (apt) links it to
/// the primary codec.
///
/// Example: createRtxCodec(payloadType: 97, apt: 96) for VP8 retransmission
RtpCodecParameters createRtxCodec({
  int? payloadType,
  int clockRate = 90000,
  int? apt,
}) {
  return RtpCodecParameters(
    mimeType: 'video/rtx',
    clockRate: clockRate,
    payloadType: payloadType,
    parameters: apt != null ? 'apt=$apt' : null,
    rtcpFeedback: const [],
  );
}

/// List of supported audio codecs
/// RED is listed first for priority in codec negotiation when available
final List<RtpCodecParameters> supportedAudioCodecs = [
  createRedCodec(),
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

/// Assign payload types to a list of codecs for SDP generation.
/// - Static codecs (PCMU=0) keep their assigned PT
/// - RED gets PT 63 with fmtp linking to the primary audio codec (Opus)
/// - Dynamic codecs get sequential PTs starting at 96
List<RtpCodecParameters> assignPayloadTypes(List<RtpCodecParameters> codecs) {
  int nextPt = 96;
  final result = <RtpCodecParameters>[];

  // First pass: find what PT Opus will get (for RED's fmtp)
  int primaryAudioPt = 96;
  int tempPt = 96;
  for (final c in codecs) {
    if (c.payloadType != null) continue; // Static codec
    if (c.codecName.toLowerCase() == 'red') continue; // Skip RED
    if (c.codecName.toLowerCase() == 'opus') {
      primaryAudioPt = tempPt;
      break;
    }
    tempPt++;
  }

  for (final codec in codecs) {
    // Static codecs keep their PT (e.g., PCMU=0)
    if (codec.payloadType != null) {
      result.add(codec);
      continue;
    }

    // RED special case: PT 63, fmtp links to primary audio codec
    if (codec.codecName.toLowerCase() == 'red') {
      result.add(RtpCodecParameters(
        mimeType: codec.mimeType,
        clockRate: codec.clockRate,
        channels: codec.channels,
        payloadType: 63,
        parameters: '$primaryAudioPt/$primaryAudioPt',
        rtcpFeedback: codec.rtcpFeedback,
      ));
      continue;
    }

    // Regular dynamic codec: assign next PT
    result.add(RtpCodecParameters(
      mimeType: codec.mimeType,
      clockRate: codec.clockRate,
      channels: codec.channels,
      payloadType: nextPt++,
      parameters: codec.parameters,
      rtcpFeedback: codec.rtcpFeedback,
    ));
  }
  return result;
}
