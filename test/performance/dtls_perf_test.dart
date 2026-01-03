/// DTLS Performance Regression Tests
///
/// Tests DTLS anti-replay window operations - called for every encrypted packet.
///
/// Run: dart test test/performance/dtls_perf_test.dart
@Tags(['performance'])
library;

import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/record/anti_replay_window.dart';

import 'perf_test_utils.dart';

void main() {
  group('DTLS Anti-Replay Window Performance', () {
    test('sequential packet check meets threshold', () {
      const iterations = 500000;

      final window = AntiReplayWindow();
      var seqNum = 0;

      final result = runBenchmarkSync(
        name: 'Anti-replay sequential check',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          window.mayReceive(seqNum);
          window.markAsReceived(seqNum);
          seqNum++;
        },
      );

      // Threshold: >1,000,000 ops/sec (every packet goes through this)
      result.checkThreshold(PerfThreshold(
        name: 'Anti-replay sequential check',
        minOpsPerSecond: 1000000,
      ));
    });

    test('out-of-order packet check meets threshold', () {
      const iterations = 200000;

      final window = AntiReplayWindow();

      // Pre-populate window with some packets
      for (var i = 0; i < 100; i++) {
        window.markAsReceived(i);
      }

      var seqNum = 100;

      final result = runBenchmarkSync(
        name: 'Anti-replay out-of-order check',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          // Simulate out-of-order: check packet, then older one
          window.mayReceive(seqNum + 10);
          window.markAsReceived(seqNum + 10);
          window.mayReceive(seqNum);
          window.markAsReceived(seqNum);
          seqNum += 11;
        },
      );

      // Threshold: >500,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'Anti-replay out-of-order check',
        minOpsPerSecond: 500000,
      ));
    });

    test('window shift (large gap) meets threshold', () {
      const iterations = 500000;

      final window = AntiReplayWindow();
      var seqNum = 100;

      final result = runBenchmarkSync(
        name: 'Anti-replay window shift',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          // Jump ahead by varying amounts to trigger shift logic
          seqNum += 5 + (seqNum % 10); // Varies 5-14
          window.markAsReceived(seqNum);
        },
      );

      // Threshold: >1,000,000 ops/sec (window shifting is fast)
      result.checkThreshold(PerfThreshold(
        name: 'Anti-replay window shift',
        minOpsPerSecond: 1000000,
      ));
    });

    test('hasReceived lookup meets threshold', () {
      const iterations = 1000000;

      final window = AntiReplayWindow();

      // Pre-populate window
      for (var i = 0; i < 64; i++) {
        window.markAsReceived(i);
      }

      var checkIndex = 0;

      final result = runBenchmarkSync(
        name: 'Anti-replay hasReceived lookup',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          window.hasReceived(checkIndex % 64);
          checkIndex++;
        },
      );

      // Threshold: >5,000,000 ops/sec (simple bit lookup)
      result.checkThreshold(PerfThreshold(
        name: 'Anti-replay hasReceived lookup',
        minOpsPerSecond: 5000000,
      ));
    });
  });
}
