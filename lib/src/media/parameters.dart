/// RTP Media Parameters
/// Based on werift-webrtc parameters.ts
library;

/// Direction for simulcast layer
enum SimulcastDirection {
  send,
  recv,
}

/// RTCRtpSimulcastParameters - Represents a single simulcast layer
///
/// Each simulcast layer has a Restriction Identifier (RID) and direction.
/// Used in SDP to negotiate multiple encoding layers.
class RTCRtpSimulcastParameters {
  /// Restriction Identifier (e.g., "high", "low", "mid")
  final String rid;

  /// Direction: send or recv
  final SimulcastDirection direction;

  const RTCRtpSimulcastParameters({
    required this.rid,
    required this.direction,
  });

  /// Parse from SDP RID attribute value
  /// Format: "rid direction" (e.g., "high send")
  factory RTCRtpSimulcastParameters.fromSdpRid(String ridValue) {
    final parts = ridValue.split(' ');
    if (parts.length < 2) {
      throw FormatException('Invalid RID format: $ridValue');
    }

    final rid = parts[0];
    final dirStr = parts[1].toLowerCase();
    final direction =
        dirStr == 'send' ? SimulcastDirection.send : SimulcastDirection.recv;

    return RTCRtpSimulcastParameters(rid: rid, direction: direction);
  }

  /// Serialize to SDP RID attribute value
  String toSdpRid() {
    final dirStr = direction == SimulcastDirection.send ? 'send' : 'recv';
    return '$rid $dirStr';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RTCRtpSimulcastParameters &&
          rid == other.rid &&
          direction == other.direction;

  @override
  int get hashCode => rid.hashCode ^ direction.hashCode;

  @override
  String toString() =>
      'RTCRtpSimulcastParameters(rid: $rid, direction: $direction)';
}

/// RTCP Feedback configuration
class RTCRtcpFeedback {
  final String type;
  final String? parameter;

  const RTCRtcpFeedback({
    required this.type,
    this.parameter,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RTCRtcpFeedback &&
          type == other.type &&
          parameter == other.parameter;

  @override
  int get hashCode => type.hashCode ^ parameter.hashCode;
}

/// RTX (Retransmission) parameters
class RTCRtpRtxParameters {
  final int ssrc;

  const RTCRtpRtxParameters({required this.ssrc});
}

/// RTP Coding parameters (for encodings)
class RTCRtpCodingParameters {
  /// SSRC for this encoding
  final int ssrc;

  /// Payload type
  final int payloadType;

  /// RTX parameters (if retransmission is enabled)
  final RTCRtpRtxParameters? rtx;

  /// RID for simulcast
  final String? rid;

  /// Max bitrate in bps
  final int? maxBitrate;

  /// Scale resolution down by this factor
  final double? scaleResolutionDownBy;

  const RTCRtpCodingParameters({
    required this.ssrc,
    required this.payloadType,
    this.rtx,
    this.rid,
    this.maxBitrate,
    this.scaleResolutionDownBy,
  });
}

/// Media direction
enum MediaDirection {
  sendrecv,
  sendonly,
  recvonly,
  inactive,
}

/// RTP Codec parameters
class RTCRtpCodecParameters {
  /// Payload type (dynamic: 96-127, static: varies)
  final int payloadType;

  /// MIME type (e.g., "video/VP8", "audio/opus")
  final String mimeType;

  /// Clock rate in Hz
  final int clockRate;

  /// Number of channels (for audio)
  final int? channels;

  /// RTCP feedback mechanisms
  final List<RTCRtcpFeedback> rtcpFeedback;

  /// Format-specific parameters (fmtp)
  final String? parameters;

  /// Direction constraint
  final MediaDirection? direction;

  const RTCRtpCodecParameters({
    required this.payloadType,
    required this.mimeType,
    required this.clockRate,
    this.channels,
    this.rtcpFeedback = const [],
    this.parameters,
    this.direction,
  });

  /// Get codec name (e.g., "VP8" from "video/VP8")
  String get name => mimeType.split('/').last;

  /// Get content type (e.g., "video" from "video/VP8")
  String get contentType => mimeType.split('/').first;

  /// Get string representation for SDP
  String get str {
    var s = '$name/$clockRate';
    if (channels == 2) s += '/2';
    return s;
  }
}

/// RTP Header Extension parameters
class RTCRtpHeaderExtensionParameters {
  /// Extension ID (1-14 for one-byte, 1-255 for two-byte)
  final int id;

  /// Extension URI
  final String uri;

  const RTCRtpHeaderExtensionParameters({
    required this.id,
    required this.uri,
  });
}

/// RTCP parameters
class RTCRtcpParameters {
  /// Canonical name
  final String? cname;

  /// Multiplexed with RTP
  final bool mux;

  /// SSRC for RTCP
  final int? ssrc;

  const RTCRtcpParameters({
    this.cname,
    this.mux = false,
    this.ssrc,
  });
}

/// RTP Parameters
class RTCRtpParameters {
  final List<RTCRtpCodecParameters> codecs;
  final List<RTCRtpHeaderExtensionParameters> headerExtensions;
  final String? muxId;
  final String? rtpStreamId;
  final String? repairedRtpStreamId;
  final RTCRtcpParameters? rtcp;

  const RTCRtpParameters({
    this.codecs = const [],
    this.headerExtensions = const [],
    this.muxId,
    this.rtpStreamId,
    this.repairedRtpStreamId,
    this.rtcp,
  });
}

/// RTP Receive parameters (extends RTCRtpParameters with encodings)
class RTCRtpReceiveParameters extends RTCRtpParameters {
  final List<RTCRtpCodingParameters> encodings;

  const RTCRtpReceiveParameters({
    super.codecs,
    super.headerExtensions,
    super.muxId,
    super.rtpStreamId,
    super.repairedRtpStreamId,
    super.rtcp,
    this.encodings = const [],
  });
}

/// RTP Encoding Parameters for send-side simulcast
///
/// Each encoding represents a single layer in simulcast.
/// Based on RTCRtpEncodingParameters from W3C WebRTC spec.
class RTCRtpEncodingParameters {
  /// RID (Restriction Identifier) for this encoding layer
  /// Used in SDP and RTP header extensions to identify the layer
  final String? rid;

  /// Whether this encoding is currently active
  /// When false, no RTP packets are sent for this encoding
  bool active;

  /// SSRC for this encoding (assigned automatically if not specified)
  int? ssrc;

  /// RTX SSRC for retransmission (assigned automatically if not specified)
  int? rtxSsrc;

  /// Maximum bitrate in bits per second
  /// If not specified, no bitrate limit is applied
  int? maxBitrate;

  /// Maximum framerate in frames per second (video only)
  double? maxFramerate;

  /// Scale resolution down by this factor (video only)
  /// 1.0 = full resolution, 2.0 = half resolution, etc.
  double? scaleResolutionDownBy;

  /// Scalability mode (e.g., "L1T2", "L2T3_KEY")
  /// Used for SVC (Scalable Video Coding)
  String? scalabilityMode;

  /// Priority relative to other encodings (1 = lowest, higher = more important)
  int priority;

  /// Network priority for congestion control
  NetworkPriority networkPriority;

  RTCRtpEncodingParameters({
    this.rid,
    this.active = true,
    this.ssrc,
    this.rtxSsrc,
    this.maxBitrate,
    this.maxFramerate,
    this.scaleResolutionDownBy,
    this.scalabilityMode,
    this.priority = 1,
    this.networkPriority = NetworkPriority.low,
  });

  /// Create a copy with optional overrides
  RTCRtpEncodingParameters copyWith({
    String? rid,
    bool? active,
    int? ssrc,
    int? rtxSsrc,
    int? maxBitrate,
    double? maxFramerate,
    double? scaleResolutionDownBy,
    String? scalabilityMode,
    int? priority,
    NetworkPriority? networkPriority,
  }) {
    return RTCRtpEncodingParameters(
      rid: rid ?? this.rid,
      active: active ?? this.active,
      ssrc: ssrc ?? this.ssrc,
      rtxSsrc: rtxSsrc ?? this.rtxSsrc,
      maxBitrate: maxBitrate ?? this.maxBitrate,
      maxFramerate: maxFramerate ?? this.maxFramerate,
      scaleResolutionDownBy:
          scaleResolutionDownBy ?? this.scaleResolutionDownBy,
      scalabilityMode: scalabilityMode ?? this.scalabilityMode,
      priority: priority ?? this.priority,
      networkPriority: networkPriority ?? this.networkPriority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RTCRtpEncodingParameters &&
          rid == other.rid &&
          active == other.active &&
          ssrc == other.ssrc &&
          rtxSsrc == other.rtxSsrc &&
          maxBitrate == other.maxBitrate &&
          maxFramerate == other.maxFramerate &&
          scaleResolutionDownBy == other.scaleResolutionDownBy &&
          scalabilityMode == other.scalabilityMode &&
          priority == other.priority &&
          networkPriority == other.networkPriority;

  @override
  int get hashCode => Object.hash(
        rid,
        active,
        ssrc,
        rtxSsrc,
        maxBitrate,
        maxFramerate,
        scaleResolutionDownBy,
        scalabilityMode,
        priority,
        networkPriority,
      );

  @override
  String toString() =>
      'RTCRtpEncodingParameters(rid: $rid, active: $active, ssrc: $ssrc, maxBitrate: $maxBitrate, scaleResolutionDownBy: $scaleResolutionDownBy)';
}

/// Network priority levels for congestion control
enum NetworkPriority {
  veryLow,
  low,
  medium,
  high,
}

/// RTP Send Parameters
///
/// Contains the parameters for sending RTP, including multiple encodings
/// for simulcast. Use getParameters()/setParameters() on RtpSender.
class RTCRtpSendParameters extends RTCRtpParameters {
  /// Transaction ID for parameter changes
  /// Must be unchanged when calling setParameters()
  final String transactionId;

  /// Encoding parameters for each simulcast layer
  /// For non-simulcast, this contains a single encoding
  final List<RTCRtpEncodingParameters> encodings;

  /// Degradation preference when bandwidth is limited
  DegradationPreference degradationPreference;

  RTCRtpSendParameters({
    required this.transactionId,
    required this.encodings,
    this.degradationPreference = DegradationPreference.balanced,
    super.codecs = const [],
    super.headerExtensions = const [],
    super.muxId,
    super.rtpStreamId,
    super.repairedRtpStreamId,
    super.rtcp,
  });

  /// Create a copy with the same transaction ID
  RTCRtpSendParameters copyWith({
    List<RTCRtpEncodingParameters>? encodings,
    DegradationPreference? degradationPreference,
    List<RTCRtpCodecParameters>? codecs,
    List<RTCRtpHeaderExtensionParameters>? headerExtensions,
  }) {
    return RTCRtpSendParameters(
      transactionId: transactionId,
      encodings: encodings ?? this.encodings,
      degradationPreference:
          degradationPreference ?? this.degradationPreference,
      codecs: codecs ?? this.codecs,
      headerExtensions: headerExtensions ?? this.headerExtensions,
      muxId: muxId,
      rtpStreamId: rtpStreamId,
      repairedRtpStreamId: repairedRtpStreamId,
      rtcp: rtcp,
    );
  }

  @override
  String toString() =>
      'RTCRtpSendParameters(transactionId: $transactionId, encodings: ${encodings.length})';
}

/// Degradation preference when bandwidth is limited
enum DegradationPreference {
  /// Maintain framerate, reduce resolution
  maintainFramerate,

  /// Maintain resolution, reduce framerate
  maintainResolution,

  /// Balance between framerate and resolution
  balanced,
}
