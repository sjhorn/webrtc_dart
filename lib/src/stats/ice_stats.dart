import 'rtc_stats.dart';

/// RTCIceCandidateStats - Statistics for ICE candidates
/// Provides information about individual ICE candidates
class RTCIceCandidateStats extends RTCStats {
  /// Transport ID this candidate belongs to
  final String? transportId;

  /// IP address (or hostname for mDNS candidates)
  final String? address;

  /// Port number
  final int? port;

  /// Transport protocol ('udp' or 'tcp')
  final String? protocol;

  /// Candidate type ('host', 'srflx', 'prflx', 'relay')
  final String? candidateType;

  /// Priority of the candidate
  final int? priority;

  /// URL of the STUN/TURN server (for srflx/relay)
  final String? url;

  /// Related address (for srflx/prflx/relay candidates)
  final String? relatedAddress;

  /// Related port (for srflx/prflx/relay candidates)
  final int? relatedPort;

  /// Username fragment
  final String? usernameFragment;

  /// TCP type ('active', 'passive', 'so') if protocol is TCP
  final String? tcpType;

  /// Foundation string
  final String? foundation;

  /// Whether this is a remote candidate
  final bool isRemote;

  const RTCIceCandidateStats({
    required super.timestamp,
    required super.id,
    required this.isRemote,
    this.transportId,
    this.address,
    this.port,
    this.protocol,
    this.candidateType,
    this.priority,
    this.url,
    this.relatedAddress,
    this.relatedPort,
    this.usernameFragment,
    this.tcpType,
    this.foundation,
  }) : super(
            type: isRemote
                ? RTCStatsType.remoteCandidate
                : RTCStatsType.localCandidate);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'isRemote': isRemote,
      if (transportId != null) 'transportId': transportId,
      if (address != null) 'address': address,
      if (port != null) 'port': port,
      if (protocol != null) 'protocol': protocol,
      if (candidateType != null) 'candidateType': candidateType,
      if (priority != null) 'priority': priority,
      if (url != null) 'url': url,
      if (relatedAddress != null) 'relatedAddress': relatedAddress,
      if (relatedPort != null) 'relatedPort': relatedPort,
      if (usernameFragment != null) 'usernameFragment': usernameFragment,
      if (tcpType != null) 'tcpType': tcpType,
      if (foundation != null) 'foundation': foundation,
    });
    return json;
  }
}

/// ICE candidate pair state
enum RTCStatsIceCandidatePairState {
  frozen('frozen'),
  waiting('waiting'),
  inProgress('in-progress'),
  failed('failed'),
  succeeded('succeeded');

  final String value;
  const RTCStatsIceCandidatePairState(this.value);

  @override
  String toString() => value;
}

/// RTCIceCandidatePairStats - Statistics for ICE candidate pairs
/// Provides information about connectivity checks and data transfer
class RTCIceCandidatePairStats extends RTCStats {
  /// Transport ID this pair belongs to
  final String? transportId;

  /// ID of the local candidate stats
  final String localCandidateId;

  /// ID of the remote candidate stats
  final String remoteCandidateId;

  /// State of the candidate pair
  final RTCStatsIceCandidatePairState state;

  /// Whether this pair is nominated
  final bool? nominated;

  /// Number of packets sent
  final int? packetsSent;

  /// Number of packets received
  final int? packetsReceived;

  /// Number of bytes sent
  final int? bytesSent;

  /// Number of bytes received
  final int? bytesReceived;

  /// Timestamp of last packet sent
  final double? lastPacketSentTimestamp;

  /// Timestamp of last packet received
  final double? lastPacketReceivedTimestamp;

  /// Total round trip time (seconds)
  final double? totalRoundTripTime;

  /// Current round trip time (seconds)
  final double? currentRoundTripTime;

  /// Available outgoing bitrate (bits per second)
  final double? availableOutgoingBitrate;

  /// Available incoming bitrate (bits per second)
  final double? availableIncomingBitrate;

  /// Number of STUN requests sent
  final int? requestsSent;

  /// Number of STUN requests received
  final int? requestsReceived;

  /// Number of STUN responses sent
  final int? responsesSent;

  /// Number of STUN responses received
  final int? responsesReceived;

  /// Number of consent requests sent
  final int? consentRequestsSent;

  /// Number of packets discarded on send
  final int? packetsDiscardedOnSend;

  /// Number of bytes discarded on send
  final int? bytesDiscardedOnSend;

  /// Priority of the candidate pair
  final int? priority;

  const RTCIceCandidatePairStats({
    required super.timestamp,
    required super.id,
    this.transportId,
    required this.localCandidateId,
    required this.remoteCandidateId,
    required this.state,
    this.nominated,
    this.packetsSent,
    this.packetsReceived,
    this.bytesSent,
    this.bytesReceived,
    this.lastPacketSentTimestamp,
    this.lastPacketReceivedTimestamp,
    this.totalRoundTripTime,
    this.currentRoundTripTime,
    this.availableOutgoingBitrate,
    this.availableIncomingBitrate,
    this.requestsSent,
    this.requestsReceived,
    this.responsesSent,
    this.responsesReceived,
    this.consentRequestsSent,
    this.packetsDiscardedOnSend,
    this.bytesDiscardedOnSend,
    this.priority,
  }) : super(type: RTCStatsType.candidatePair);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'localCandidateId': localCandidateId,
      'remoteCandidateId': remoteCandidateId,
      'state': state.value,
      if (transportId != null) 'transportId': transportId,
      if (nominated != null) 'nominated': nominated,
      if (packetsSent != null) 'packetsSent': packetsSent,
      if (packetsReceived != null) 'packetsReceived': packetsReceived,
      if (bytesSent != null) 'bytesSent': bytesSent,
      if (bytesReceived != null) 'bytesReceived': bytesReceived,
      if (lastPacketSentTimestamp != null)
        'lastPacketSentTimestamp': lastPacketSentTimestamp,
      if (lastPacketReceivedTimestamp != null)
        'lastPacketReceivedTimestamp': lastPacketReceivedTimestamp,
      if (totalRoundTripTime != null) 'totalRoundTripTime': totalRoundTripTime,
      if (currentRoundTripTime != null)
        'currentRoundTripTime': currentRoundTripTime,
      if (availableOutgoingBitrate != null)
        'availableOutgoingBitrate': availableOutgoingBitrate,
      if (availableIncomingBitrate != null)
        'availableIncomingBitrate': availableIncomingBitrate,
      if (requestsSent != null) 'requestsSent': requestsSent,
      if (requestsReceived != null) 'requestsReceived': requestsReceived,
      if (responsesSent != null) 'responsesSent': responsesSent,
      if (responsesReceived != null) 'responsesReceived': responsesReceived,
      if (consentRequestsSent != null)
        'consentRequestsSent': consentRequestsSent,
      if (packetsDiscardedOnSend != null)
        'packetsDiscardedOnSend': packetsDiscardedOnSend,
      if (bytesDiscardedOnSend != null)
        'bytesDiscardedOnSend': bytesDiscardedOnSend,
      if (priority != null) 'priority': priority,
    });
    return json;
  }
}
