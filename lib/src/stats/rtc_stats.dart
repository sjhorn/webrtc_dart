/// WebRTC Statistics API
/// Based on W3C WebRTC Statistics specification
/// https://www.w3.org/TR/webrtc-stats/
library;

/// Stats types enumeration
enum RTCStatsType {
  codec('codec'),
  inboundRtp('inbound-rtp'),
  outboundRtp('outbound-rtp'),
  remoteInboundRtp('remote-inbound-rtp'),
  remoteOutboundRtp('remote-outbound-rtp'),
  mediaSource('media-source'),
  peerConnection('peer-connection'),
  dataChannel('data-channel'),
  transport('transport'),
  candidatePair('candidate-pair'),
  localCandidate('local-candidate'),
  remoteCandidate('remote-candidate'),
  certificate('certificate');

  final String value;
  const RTCStatsType(this.value);

  @override
  String toString() => value;
}

/// Base class for all RTC statistics objects
abstract class RTCStats {
  /// Timestamp when stats were generated (milliseconds since epoch)
  final double timestamp;

  /// Type of statistics object
  final RTCStatsType type;

  /// Unique identifier for this stats object
  final String id;

  const RTCStats({
    required this.timestamp,
    required this.type,
    required this.id,
  });

  /// Convert to JSON-like map
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'type': type.value,
      'id': id,
    };
  }

  @override
  String toString() => 'RTCStats(id: $id, type: $type, timestamp: $timestamp)';
}

/// RTCStatsReport - Map-like container for stats objects
class RTCStatsReport {
  final Map<String, RTCStats> _stats = {};

  RTCStatsReport([List<RTCStats>? stats]) {
    if (stats != null) {
      for (final stat in stats) {
        _stats[stat.id] = stat;
      }
    }
  }

  /// Get stats by ID
  RTCStats? operator [](String id) => _stats[id];

  /// Get all stats
  Iterable<RTCStats> get values => _stats.values;

  /// Get all IDs
  Iterable<String> get keys => _stats.keys;

  /// Number of stats objects
  int get length => _stats.length;

  /// Check if stats contains ID
  bool containsKey(String id) => _stats.containsKey(id);

  /// Iterate over stats
  void forEach(void Function(String id, RTCStats stats) f) {
    _stats.forEach(f);
  }

  @override
  String toString() => 'RTCStatsReport(${_stats.length} stats objects)';
}

/// Generate unique stats ID
String generateStatsId(String type, [List<dynamic>? parts]) {
  if (parts == null || parts.isEmpty) {
    return type;
  }
  final validParts = parts.where((p) => p != null).map((p) => p.toString());
  return '${type}_${validParts.join('_')}';
}

/// Get current timestamp for stats (milliseconds with decimals)
double getStatsTimestamp() {
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}
