/// StreamStatistics - RTP stream statistics tracking
///
/// Tracks jitter, packet loss, and other statistics per RFC 3550.
/// Used for RTCP Receiver Reports and quality monitoring.
///
/// Ported from werift-webrtc statistics.ts (based on aiortc)
library;

import '../../srtp/rtp_packet.dart';

/// Compare 16-bit unsigned sequence numbers with wraparound
///
/// Returns true if [seq1] > [seq2] accounting for 16-bit wraparound.
bool _uint16Gt(int seq1, int seq2) {
  // Handle wraparound: if difference is > 32768, the smaller number is newer
  final diff = (seq1 - seq2) & 0xFFFF;
  return diff > 0 && diff < 32768;
}

/// Statistics tracker for an RTP stream
///
/// Computes statistics required for RTCP Receiver Reports:
/// - Packet loss (expected vs received)
/// - Fraction lost (for current reporting interval)
/// - Jitter (interarrival time variance)
/// - Extended highest sequence number
class StreamStatistics {
  /// Clock rate of the media stream (e.g., 90000 for video, 48000 for Opus)
  final int clockRate;

  /// Base sequence number (first packet seen)
  int? baseSeq;

  /// Maximum sequence number seen (with wraparound handling)
  int? maxSeq;

  /// Count of 16-bit sequence number cycles (wraps at 65536)
  int cycles = 0;

  /// Total packets received
  int packetsReceived = 0;

  // Jitter calculation (RFC 3550 section 6.4.1)
  // Uses Q4 fixed-point format (4 fractional bits)
  int _jitterQ4 = 0;
  int? _lastArrival;
  int? _lastTimestamp;

  // Fraction lost calculation (per reporting interval)
  int _expectedPrior = 0;
  int _receivedPrior = 0;

  /// Create statistics tracker for a stream with given clock rate
  StreamStatistics(this.clockRate);

  /// Add a received packet to the statistics
  ///
  /// [packet] is the received RTP packet.
  /// [now] is the arrival time in seconds (defaults to current time).
  void add(RtpPacket packet, [double? now]) {
    now ??= DateTime.now().millisecondsSinceEpoch / 1000.0;

    final seqNum = packet.sequenceNumber;
    final inOrder = maxSeq == null || _uint16Gt(seqNum, maxSeq!);

    packetsReceived++;

    baseSeq ??= seqNum;

    if (inOrder) {
      // Convert arrival time to clock rate units
      final arrival = (now * clockRate).toInt();

      // Check for sequence number wraparound
      if (maxSeq != null && seqNum < maxSeq!) {
        cycles += 1 << 16; // 65536
      }
      maxSeq = seqNum;

      // Calculate jitter (RFC 3550 section 6.4.1)
      // J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
      if (packet.timestamp != _lastTimestamp && packetsReceived > 1) {
        final diff = (arrival -
                (_lastArrival ?? 0) -
                (packet.timestamp - (_lastTimestamp ?? 0)))
            .abs();
        // Q4 fixed-point: jitter_q4 += diff - ((jitter_q4 + 8) >> 4)
        _jitterQ4 += diff - ((_jitterQ4 + 8) >> 4);
      }

      _lastArrival = arrival;
      _lastTimestamp = packet.timestamp;
    }
  }

  /// Fraction of packets lost in the current reporting interval
  ///
  /// Returns value in range [0, 255] where 255 = 100% loss.
  /// This value is computed since the last call to this getter.
  int get fractionLost {
    // Can't calculate fraction lost without any packets
    if (baseSeq == null) {
      return 0;
    }

    final expectedInterval = packetsExpected - _expectedPrior;
    _expectedPrior = packetsExpected;
    final receivedInterval = packetsReceived - _receivedPrior;
    _receivedPrior = packetsReceived;
    final lostInterval = expectedInterval - receivedInterval;

    if (expectedInterval == 0 || lostInterval <= 0) {
      return 0;
    } else {
      // Scale to 8-bit fraction (0-255)
      return (lostInterval << 8) ~/ expectedInterval;
    }
  }

  /// Interarrival jitter in timestamp units
  ///
  /// Computed per RFC 3550 section 6.4.1.
  int get jitter => _jitterQ4 >> 4;

  /// Expected number of packets based on sequence numbers
  ///
  /// This is the extended highest sequence number minus base + 1.
  int get packetsExpected {
    return cycles + (maxSeq ?? 0) - (baseSeq ?? 0) + 1;
  }

  /// Cumulative number of packets lost
  ///
  /// This is expected - received, clamped to >= 0.
  int get packetsLost {
    final lost = packetsExpected - packetsReceived;
    return lost < 0 ? 0 : lost;
  }

  /// Extended highest sequence number received
  ///
  /// Includes cycle count for 32-bit sequence number space.
  int get extendedHighestSequence {
    return cycles + (maxSeq ?? 0);
  }

  /// Convert statistics to JSON for debugging
  Map<String, dynamic> toJson() {
    return {
      'clockRate': clockRate,
      'baseSeq': baseSeq,
      'maxSeq': maxSeq,
      'cycles': cycles,
      'packetsReceived': packetsReceived,
      'packetsExpected': packetsExpected,
      'packetsLost': packetsLost,
      'fractionLost': fractionLost,
      'jitter': jitter,
      'extendedHighestSequence': extendedHighestSequence,
    };
  }
}
