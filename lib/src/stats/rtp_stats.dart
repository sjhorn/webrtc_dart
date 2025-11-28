import 'rtc_stats.dart';

/// RTCRtpStreamStats - Base class for RTP stream statistics
/// Common statistics for both inbound and outbound RTP streams
abstract class RTCRtpStreamStats extends RTCStats {
  /// SSRC of the RTP stream
  final int ssrc;

  /// ID of the codec stats object
  final String? codecId;

  /// Type of media (audio/video)
  final String? kind;

  /// ID of the transport stats object
  final String? transportId;

  const RTCRtpStreamStats({
    required super.timestamp,
    required super.type,
    required super.id,
    required this.ssrc,
    this.codecId,
    this.kind,
    this.transportId,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'ssrc': ssrc,
      if (codecId != null) 'codecId': codecId,
      if (kind != null) 'kind': kind,
      if (transportId != null) 'transportId': transportId,
    });
    return json;
  }
}

/// RTCReceivedRtpStreamStats - Statistics for received RTP streams
abstract class RTCReceivedRtpStreamStats extends RTCRtpStreamStats {
  /// Total number of RTP packets received
  final int packetsReceived;

  /// Total number of RTP packets lost
  final int packetsLost;

  /// Packet jitter (seconds)
  final double jitter;

  const RTCReceivedRtpStreamStats({
    required super.timestamp,
    required super.type,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required this.packetsReceived,
    required this.packetsLost,
    required this.jitter,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'packetsReceived': packetsReceived,
      'packetsLost': packetsLost,
      'jitter': jitter,
    });
    return json;
  }
}

/// RTCSentRtpStreamStats - Statistics for sent RTP streams
abstract class RTCSentRtpStreamStats extends RTCRtpStreamStats {
  /// Total number of RTP packets sent
  final int packetsSent;

  /// Total number of bytes sent (including headers)
  final int bytesSent;

  const RTCSentRtpStreamStats({
    required super.timestamp,
    required super.type,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required this.packetsSent,
    required this.bytesSent,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'packetsSent': packetsSent,
      'bytesSent': bytesSent,
    });
    return json;
  }
}

/// RTCInboundRtpStreamStats - Statistics for inbound RTP streams
class RTCInboundRtpStreamStats extends RTCReceivedRtpStreamStats {
  /// ID of the receiver track
  final String? trackIdentifier;

  /// ID of the receiver stats
  final String? receiverId;

  /// ID of the remote outbound stream stats
  final String? remoteId;

  /// Total number of frames received (video only)
  final int? framesReceived;

  /// Total number of frames decoded (video only)
  final int? framesDecoded;

  /// Total number of frames dropped (video only)
  final int? framesDropped;

  /// Total number of key frames decoded (video only)
  final int? keyFramesDecoded;

  /// Total number of audio samples received (audio only)
  final int? totalSamplesReceived;

  /// Total bytes received (payload only)
  final int bytesReceived;

  /// Total number of header bytes received
  final int? headerBytesReceived;

  /// Total number of FEC packets received
  final int? fecPacketsReceived;

  /// Total number of FEC packets discarded
  final int? fecPacketsDiscarded;

  /// Total number of retransmitted packets received
  final int? retransmittedPacketsReceived;

  /// Total number of retransmitted bytes received
  final int? retransmittedBytesReceived;

  /// Timestamp of last packet received
  final double? lastPacketReceivedTimestamp;

  /// Current decoder implementation name
  final String? decoderImplementation;

  /// Total number of NACK requests sent
  final int? nackCount;

  /// Total number of FIR packets sent (video only)
  final int? firCount;

  /// Total number of PLI packets sent (video only)
  final int? pliCount;

  const RTCInboundRtpStreamStats({
    required super.timestamp,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required super.packetsReceived,
    required super.packetsLost,
    required super.jitter,
    this.trackIdentifier,
    this.receiverId,
    this.remoteId,
    this.framesReceived,
    this.framesDecoded,
    this.framesDropped,
    this.keyFramesDecoded,
    this.totalSamplesReceived,
    required this.bytesReceived,
    this.headerBytesReceived,
    this.fecPacketsReceived,
    this.fecPacketsDiscarded,
    this.retransmittedPacketsReceived,
    this.retransmittedBytesReceived,
    this.lastPacketReceivedTimestamp,
    this.decoderImplementation,
    this.nackCount,
    this.firCount,
    this.pliCount,
  }) : super(type: RTCStatsType.inboundRtp);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'bytesReceived': bytesReceived,
      if (trackIdentifier != null) 'trackIdentifier': trackIdentifier,
      if (receiverId != null) 'receiverId': receiverId,
      if (remoteId != null) 'remoteId': remoteId,
      if (framesReceived != null) 'framesReceived': framesReceived,
      if (framesDecoded != null) 'framesDecoded': framesDecoded,
      if (framesDropped != null) 'framesDropped': framesDropped,
      if (keyFramesDecoded != null) 'keyFramesDecoded': keyFramesDecoded,
      if (totalSamplesReceived != null)
        'totalSamplesReceived': totalSamplesReceived,
      if (headerBytesReceived != null) 'headerBytesReceived': headerBytesReceived,
      if (fecPacketsReceived != null) 'fecPacketsReceived': fecPacketsReceived,
      if (fecPacketsDiscarded != null)
        'fecPacketsDiscarded': fecPacketsDiscarded,
      if (retransmittedPacketsReceived != null)
        'retransmittedPacketsReceived': retransmittedPacketsReceived,
      if (retransmittedBytesReceived != null)
        'retransmittedBytesReceived': retransmittedBytesReceived,
      if (lastPacketReceivedTimestamp != null)
        'lastPacketReceivedTimestamp': lastPacketReceivedTimestamp,
      if (decoderImplementation != null)
        'decoderImplementation': decoderImplementation,
      if (nackCount != null) 'nackCount': nackCount,
      if (firCount != null) 'firCount': firCount,
      if (pliCount != null) 'pliCount': pliCount,
    });
    return json;
  }
}

/// RTCOutboundRtpStreamStats - Statistics for outbound RTP streams
class RTCOutboundRtpStreamStats extends RTCSentRtpStreamStats {
  /// ID of the sender track
  final String? trackId;

  /// ID of the sender stats
  final String? senderId;

  /// ID of the remote inbound stream stats
  final String? remoteId;

  /// ID of the media source stats
  final String? mediaSourceId;

  /// Total number of frames sent (video only)
  final int? framesSent;

  /// Total number of frames encoded (video only)
  final int? framesEncoded;

  /// Total number of key frames encoded (video only)
  final int? keyFramesEncoded;

  /// Total number of audio samples sent (audio only)
  final int? totalSamplesSent;

  /// Total number of header bytes sent
  final int? headerBytesSent;

  /// Total number of retransmitted packets sent
  final int? retransmittedPacketsSent;

  /// Total number of retransmitted bytes sent
  final int? retransmittedBytesSent;

  /// Current encoder implementation name
  final String? encoderImplementation;

  /// Total number of NACK requests received
  final int? nackCount;

  /// Total number of FIR packets received (video only)
  final int? firCount;

  /// Total number of PLI packets received (video only)
  final int? pliCount;

  /// Quality limitation reason
  final String? qualityLimitationReason;

  /// Total time spent in each quality limitation state (seconds)
  final Map<String, double>? qualityLimitationDurations;

  /// Total encoding time (seconds, video only)
  final double? totalEncodeTime;

  /// Total time spent paused (seconds, video only)
  final double? totalPacketSendDelay;

  /// Average RTCP interval (seconds)
  final double? averageRtcpInterval;

  const RTCOutboundRtpStreamStats({
    required super.timestamp,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required super.packetsSent,
    required super.bytesSent,
    this.trackId,
    this.senderId,
    this.remoteId,
    this.mediaSourceId,
    this.framesSent,
    this.framesEncoded,
    this.keyFramesEncoded,
    this.totalSamplesSent,
    this.headerBytesSent,
    this.retransmittedPacketsSent,
    this.retransmittedBytesSent,
    this.encoderImplementation,
    this.nackCount,
    this.firCount,
    this.pliCount,
    this.qualityLimitationReason,
    this.qualityLimitationDurations,
    this.totalEncodeTime,
    this.totalPacketSendDelay,
    this.averageRtcpInterval,
  }) : super(type: RTCStatsType.outboundRtp);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (trackId != null) 'trackId': trackId,
      if (senderId != null) 'senderId': senderId,
      if (remoteId != null) 'remoteId': remoteId,
      if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
      if (framesSent != null) 'framesSent': framesSent,
      if (framesEncoded != null) 'framesEncoded': framesEncoded,
      if (keyFramesEncoded != null) 'keyFramesEncoded': keyFramesEncoded,
      if (totalSamplesSent != null) 'totalSamplesSent': totalSamplesSent,
      if (headerBytesSent != null) 'headerBytesSent': headerBytesSent,
      if (retransmittedPacketsSent != null)
        'retransmittedPacketsSent': retransmittedPacketsSent,
      if (retransmittedBytesSent != null)
        'retransmittedBytesSent': retransmittedBytesSent,
      if (encoderImplementation != null)
        'encoderImplementation': encoderImplementation,
      if (nackCount != null) 'nackCount': nackCount,
      if (firCount != null) 'firCount': firCount,
      if (pliCount != null) 'pliCount': pliCount,
      if (qualityLimitationReason != null)
        'qualityLimitationReason': qualityLimitationReason,
      if (qualityLimitationDurations != null)
        'qualityLimitationDurations': qualityLimitationDurations,
      if (totalEncodeTime != null) 'totalEncodeTime': totalEncodeTime,
      if (totalPacketSendDelay != null)
        'totalPacketSendDelay': totalPacketSendDelay,
      if (averageRtcpInterval != null)
        'averageRtcpInterval': averageRtcpInterval,
    });
    return json;
  }
}

/// RTCRemoteInboundRtpStreamStats - Statistics for remote inbound streams
/// (Received in RTCP Receiver Reports)
class RTCRemoteInboundRtpStreamStats extends RTCReceivedRtpStreamStats {
  /// ID of the local outbound stream this corresponds to
  final String? localId;

  /// Round trip time (seconds)
  final double? roundTripTime;

  /// Total round trip time (seconds)
  final double? totalRoundTripTime;

  /// Fraction lost as reported in RTCP RR
  final double? fractionLost;

  /// Number of round trip time measurements
  final int? roundTripTimeMeasurements;

  const RTCRemoteInboundRtpStreamStats({
    required super.timestamp,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required super.packetsReceived,
    required super.packetsLost,
    required super.jitter,
    this.localId,
    this.roundTripTime,
    this.totalRoundTripTime,
    this.fractionLost,
    this.roundTripTimeMeasurements,
  }) : super(type: RTCStatsType.remoteInboundRtp);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (localId != null) 'localId': localId,
      if (roundTripTime != null) 'roundTripTime': roundTripTime,
      if (totalRoundTripTime != null) 'totalRoundTripTime': totalRoundTripTime,
      if (fractionLost != null) 'fractionLost': fractionLost,
      if (roundTripTimeMeasurements != null)
        'roundTripTimeMeasurements': roundTripTimeMeasurements,
    });
    return json;
  }
}

/// RTCRemoteOutboundRtpStreamStats - Statistics for remote outbound streams
/// (Received in RTCP Sender Reports)
class RTCRemoteOutboundRtpStreamStats extends RTCSentRtpStreamStats {
  /// ID of the local inbound stream this corresponds to
  final String? localId;

  /// Remote timestamp when SR was sent
  final double? remoteTimestamp;

  /// Number of reports sent
  final int? reportsSent;

  /// Round trip time (seconds)
  final double? roundTripTime;

  /// Total round trip time (seconds)
  final double? totalRoundTripTime;

  /// Number of round trip time measurements
  final int? roundTripTimeMeasurements;

  const RTCRemoteOutboundRtpStreamStats({
    required super.timestamp,
    required super.id,
    required super.ssrc,
    super.codecId,
    super.kind,
    super.transportId,
    required super.packetsSent,
    required super.bytesSent,
    this.localId,
    this.remoteTimestamp,
    this.reportsSent,
    this.roundTripTime,
    this.totalRoundTripTime,
    this.roundTripTimeMeasurements,
  }) : super(type: RTCStatsType.remoteOutboundRtp);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (localId != null) 'localId': localId,
      if (remoteTimestamp != null) 'remoteTimestamp': remoteTimestamp,
      if (reportsSent != null) 'reportsSent': reportsSent,
      if (roundTripTime != null) 'roundTripTime': roundTripTime,
      if (totalRoundTripTime != null) 'totalRoundTripTime': totalRoundTripTime,
      if (roundTripTimeMeasurements != null)
        'roundTripTimeMeasurements': roundTripTimeMeasurements,
    });
    return json;
  }
}

/// RTCMediaSourceStats - Statistics for media sources
class RTCMediaSourceStats extends RTCStats {
  /// Track identifier
  final String trackIdentifier;

  /// Kind of media (audio/video)
  final String kind;

  /// Width in pixels (video only)
  final int? width;

  /// Height in pixels (video only)
  final int? height;

  /// Frames per second (video only)
  final double? framesPerSecond;

  /// Total number of frames (video only)
  final int? frames;

  /// Audio level (0.0 to 1.0, audio only)
  final double? audioLevel;

  /// Total audio energy (audio only)
  final double? totalAudioEnergy;

  /// Total samples duration (seconds, audio only)
  final double? totalSamplesDuration;

  const RTCMediaSourceStats({
    required super.timestamp,
    required super.id,
    required this.trackIdentifier,
    required this.kind,
    this.width,
    this.height,
    this.framesPerSecond,
    this.frames,
    this.audioLevel,
    this.totalAudioEnergy,
    this.totalSamplesDuration,
  }) : super(type: RTCStatsType.mediaSource);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'trackIdentifier': trackIdentifier,
      'kind': kind,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (framesPerSecond != null) 'framesPerSecond': framesPerSecond,
      if (frames != null) 'frames': frames,
      if (audioLevel != null) 'audioLevel': audioLevel,
      if (totalAudioEnergy != null) 'totalAudioEnergy': totalAudioEnergy,
      if (totalSamplesDuration != null)
        'totalSamplesDuration': totalSamplesDuration,
    });
    return json;
  }
}

/// RTCCodecStats - Statistics for codecs
class RTCCodecStats extends RTCStats {
  /// Payload type
  final int payloadType;

  /// Transport ID
  final String transportId;

  /// MIME type (e.g., 'audio/opus', 'video/VP8')
  final String mimeType;

  /// Clock rate in Hz
  final int? clockRate;

  /// Number of channels (audio only)
  final int? channels;

  /// SDP fmtp line parameters
  final String? sdpFmtpLine;

  const RTCCodecStats({
    required super.timestamp,
    required super.id,
    required this.payloadType,
    required this.transportId,
    required this.mimeType,
    this.clockRate,
    this.channels,
    this.sdpFmtpLine,
  }) : super(type: RTCStatsType.codec);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'payloadType': payloadType,
      'transportId': transportId,
      'mimeType': mimeType,
      if (clockRate != null) 'clockRate': clockRate,
      if (channels != null) 'channels': channels,
      if (sdpFmtpLine != null) 'sdpFmtpLine': sdpFmtpLine,
    });
    return json;
  }
}
