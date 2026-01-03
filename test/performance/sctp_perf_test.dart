/// SCTP Queue Operations Performance Regression Tests
///
/// Tests SCTP queue operation throughput, critical for DataChannel performance.
/// The SACK processing loop removes acknowledged chunks from the sent queue.
///
/// Run: dart test test/performance/sctp_perf_test.dart
@Tags(['performance'])
library;

import 'dart:collection';
import 'package:test/test.dart';

import 'perf_test_utils.dart';

/// Simulated sent chunk (minimal for benchmarking)
class _SentChunk {
  final int tsn;
  bool acked = false;

  _SentChunk(this.tsn);
}

void main() {
  group('SCTP Queue Performance', () {
    test('batch queue removal meets threshold (1000 chunks)', () {
      const queueSize = 1000;
      const iterations = 1000;

      final result = runBenchmarkSync(
        name: 'SCTP batch removal 1000',
        iterations: iterations,
        warmupIterations: 10,
        operation: () {
          final queue = Queue<_SentChunk>.from(
            List.generate(queueSize, (i) => _SentChunk(i)),
          );

          // Simulate SACK processing - remove first half (acknowledged chunks)
          final removeCount = queueSize ~/ 2;
          for (var i = 0; i < removeCount; i++) {
            queue.removeFirst();
          }
        },
        metadata: {'queueSize': queueSize, 'removeCount': queueSize ~/ 2},
      );

      // Threshold: >20,000 ops/sec (each op processes 500 chunk removals)
      // This ensures SACK processing is fast
      result.checkThreshold(PerfThreshold(
        name: 'SCTP batch removal 1000',
        minOpsPerSecond: 20000,
      ));
    });

    test('queue iteration for TSN lookup meets threshold', () {
      const queueSize = 1000;
      const iterations = 5000;

      // Pre-create queue
      final queue = Queue<_SentChunk>.from(
        List.generate(queueSize, (i) => _SentChunk(i)),
      );

      final result = runBenchmarkSync(
        name: 'SCTP TSN lookup',
        iterations: iterations,
        warmupIterations: 100,
        operation: () {
          // Simulate finding a specific TSN (gap ack processing)
          final targetTsn = queueSize ~/ 2;
          for (final chunk in queue) {
            if (chunk.tsn == targetTsn) {
              chunk.acked = true;
              break;
            }
          }
        },
        metadata: {'queueSize': queueSize},
      );

      // Threshold: >100,000 ops/sec for simple iteration
      result.checkThreshold(PerfThreshold(
        name: 'SCTP TSN lookup',
        minOpsPerSecond: 100000,
      ));
    });

    test('removeRange optimization meets threshold (5000 chunks)', () {
      const queueSize = 5000;
      const iterations = 200;

      final result = runBenchmarkSync(
        name: 'SCTP removeRange 5000',
        iterations: iterations,
        warmupIterations: 5,
        operation: () {
          final list = List.generate(queueSize, (i) => _SentChunk(i));

          // Find cutoff first, then batch remove (optimized pattern)
          var removeCount = 0;
          for (var i = 0; i < list.length; i++) {
            if (list[i].tsn >= queueSize ~/ 2) break;
            removeCount++;
          }
          if (removeCount > 0) {
            list.removeRange(0, removeCount);
          }
        },
        metadata: {'queueSize': queueSize, 'removeCount': queueSize ~/ 2},
      );

      // Threshold: >1,000 ops/sec (each op processes 2500 chunk removals)
      result.checkThreshold(PerfThreshold(
        name: 'SCTP removeRange 5000',
        minOpsPerSecond: 1000,
      ));
    });

    test('queue add/remove meets threshold', () {
      const iterations = 100000;

      final queue = Queue<_SentChunk>();

      final result = runBenchmarkSync(
        name: 'SCTP queue add/remove',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          queue.add(_SentChunk(0));
          queue.removeFirst();
        },
      );

      // Threshold: >1,000,000 ops/sec for simple add/remove
      result.checkThreshold(PerfThreshold(
        name: 'SCTP queue add/remove',
        minOpsPerSecond: 1000000,
      ));
    });
  });
}
