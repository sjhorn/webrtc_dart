import 'dart:math' as math;

import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';

/// ICE candidate pair state
/// See RFC 5245 - 5.7.4. Computing States
enum CandidatePairState {
  frozen,
  waiting,
  inProgress,
  succeeded,
  failed;
}

/// Statistics for a candidate pair
class CandidatePairStats {
  int packetsSent = 0;
  int packetsReceived = 0;
  int bytesSent = 0;
  int bytesReceived = 0;
  double? rtt;
  double totalRoundTripTime = 0;
  int roundTripTimeMeasurements = 0;

  CandidatePairStats();

  CandidatePairStats copyWith({
    int? packetsSent,
    int? packetsReceived,
    int? bytesSent,
    int? bytesReceived,
    double? rtt,
    double? totalRoundTripTime,
    int? roundTripTimeMeasurements,
  }) {
    return CandidatePairStats()
      ..packetsSent = packetsSent ?? this.packetsSent
      ..packetsReceived = packetsReceived ?? this.packetsReceived
      ..bytesSent = bytesSent ?? this.bytesSent
      ..bytesReceived = bytesReceived ?? this.bytesReceived
      ..rtt = rtt ?? this.rtt
      ..totalRoundTripTime = totalRoundTripTime ?? this.totalRoundTripTime
      ..roundTripTimeMeasurements =
          roundTripTimeMeasurements ?? this.roundTripTimeMeasurements;
  }
}

/// ICE candidate pair
/// Represents a pairing of a local and remote candidate
class CandidatePair {
  /// Unique identifier for this pair
  final String id;

  /// Local candidate
  final Candidate localCandidate;

  /// Remote candidate
  final Candidate remoteCandidate;

  /// Whether this agent is controlling
  final bool iceControlling;

  /// Whether this pair has been nominated
  bool nominated = false;

  /// Whether the remote peer nominated this pair
  bool remoteNominated = false;

  /// Current state of the pair
  CandidatePairState _state = CandidatePairState.frozen;

  /// Statistics for this pair
  final CandidatePairStats stats = CandidatePairStats();

  CandidatePair({
    required this.id,
    required this.localCandidate,
    required this.remoteCandidate,
    required this.iceControlling,
  });

  /// Get current state
  CandidatePairState get state => _state;

  /// Update state
  void updateState(CandidatePairState newState) {
    _state = newState;
  }

  /// Get component ID
  int get component => localCandidate.component;

  /// Get foundation
  String get foundation => localCandidate.foundation;

  /// Get remote address
  (String, int) get remoteAddr => (remoteCandidate.host, remoteCandidate.port);

  /// Compute pair priority
  /// See RFC 5245 - 5.7.2. Computing Pair Priority and Ordering Pairs
  int get priority {
    return candidatePairPriority(
      localCandidate,
      remoteCandidate,
      iceControlling,
    );
  }

  @override
  String toString() {
    return 'CandidatePair($state, '
        'local=${localCandidate.host}:${localCandidate.port}, '
        'remote=${remoteCandidate.host}:${remoteCandidate.port}, '
        'priority=$priority)';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'localCandidate': localCandidate.toSdp(),
      'remoteCandidate': remoteCandidate.toSdp(),
      'state': state.name,
      'nominated': nominated,
      'priority': priority,
      'stats': {
        'packetsSent': stats.packetsSent,
        'packetsReceived': stats.packetsReceived,
        'bytesSent': stats.bytesSent,
        'bytesReceived': stats.bytesReceived,
        'rtt': stats.rtt,
      },
    };
  }
}

/// Compute priority for a candidate pair
/// See RFC 5245 - 5.7.2. Computing Pair Priority and Ordering Pairs
///
/// priority = 2^32*MIN(G,D) + 2*MAX(G,D) + (G>D?1:0)
/// where G is the priority for the controlling agent's candidate
/// and D is the priority for the controlled agent's candidate
int candidatePairPriority(
  Candidate local,
  Candidate remote,
  bool iceControlling,
) {
  final g = iceControlling ? local.priority : remote.priority;
  final d = iceControlling ? remote.priority : local.priority;

  final minVal = math.min(g, d);
  final maxVal = math.max(g, d);

  // Note: In Dart, we use BigInt for the large number calculation
  // then convert back to int (which is 64-bit in Dart)
  final result = (BigInt.from(1) << 32) * BigInt.from(minVal) +
      BigInt.from(2) * BigInt.from(maxVal) +
      BigInt.from(g > d ? 1 : 0);

  return result.toInt();
}

/// Sort candidate pairs by priority (highest first)
List<CandidatePair> sortCandidatePairs(
  List<CandidatePair> pairs,
) {
  final sorted = List<CandidatePair>.from(pairs);
  sorted.sort((a, b) => b.priority.compareTo(a.priority));
  return sorted;
}

/// Validate remote candidate
/// Check if the remote candidate is supported
Candidate validateRemoteCandidate(Candidate candidate) {
  const supportedTypes = ['host', 'relay', 'srflx'];

  if (!supportedTypes.contains(candidate.type)) {
    throw ArgumentError('Unexpected candidate type "${candidate.type}"');
  }

  return candidate;
}
