/// RTCP Performance Regression Tests
///
/// Tests RTCP NACK serialization/parsing - critical for retransmission.
///
/// Run: dart test test/performance/rtcp_perf_test.dart
@Tags(['performance'])
library;

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/nack.dart';

import 'perf_test_utils.dart';

void main() {
  group('RTCP NACK Performance', () {
    test('NACK serialize small loss meets threshold', () {
      const iterations = 100000;

      // Small loss: 5 packets
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [100, 101, 102, 105, 110],
      );

      final result = runBenchmarkSync(
        name: 'NACK serialize small',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          nack.serialize();
        },
        metadata: {'lostPackets': 5},
      );

      // Threshold: >200,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'NACK serialize small',
        minOpsPerSecond: 200000,
      ));
    });

    test('NACK serialize large loss meets threshold', () {
      const iterations = 50000;

      // Large loss: 50 packets scattered
      final lostSeqNumbers = List.generate(50, (i) => 100 + i * 3);
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: lostSeqNumbers,
      );

      final result = runBenchmarkSync(
        name: 'NACK serialize large',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          nack.serialize();
        },
        metadata: {'lostPackets': 50},
      );

      // Threshold: >50,000 ops/sec (sort + encode is O(n log n))
      result.checkThreshold(PerfThreshold(
        name: 'NACK serialize large',
        minOpsPerSecond: 50000,
      ));
    });

    test('NACK deserialize meets threshold', () {
      const iterations = 100000;

      // Create a NACK packet to deserialize
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [100, 101, 102, 105, 110, 115, 116, 117],
      );
      final packet = nack.toRtcpPacket();

      final result = runBenchmarkSync(
        name: 'NACK deserialize',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          GenericNack.deserialize(packet);
        },
      );

      // Threshold: >300,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'NACK deserialize',
        minOpsPerSecond: 300000,
      ));
    });

    test('NACK round-trip meets threshold', () {
      const iterations = 50000;

      final lostSeqNumbers = [100, 101, 102, 105, 110, 115, 116, 117, 120, 125];

      final result = runBenchmarkSync(
        name: 'NACK round-trip',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          final nack = GenericNack(
            senderSsrc: 0x12345678,
            mediaSourceSsrc: 0x87654321,
            lostSeqNumbers: lostSeqNumbers,
          );
          final packet = nack.toRtcpPacket();
          GenericNack.deserialize(packet);
        },
      );

      // Threshold: >100,000 round-trips/sec
      result.checkThreshold(PerfThreshold(
        name: 'NACK round-trip',
        minOpsPerSecond: 100000,
      ));
    });
  });
}
