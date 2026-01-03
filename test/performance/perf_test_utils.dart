/// Performance Test Utilities
///
/// Common utilities for performance regression tests.
/// These tests warn (not fail) when thresholds are exceeded.
library;

import 'dart:io';
import 'dart:convert';

/// Performance threshold that warns on regression
class PerfThreshold {
  final String name;
  final double minOpsPerSecond;
  final double? maxMicroseconds;

  const PerfThreshold({
    required this.name,
    this.minOpsPerSecond = 0,
    this.maxMicroseconds,
  });
}

/// Result of a performance benchmark
class PerfResult {
  final String name;
  final int iterations;
  final Duration elapsed;
  final Map<String, dynamic> metadata;

  PerfResult({
    required this.name,
    required this.iterations,
    required this.elapsed,
    this.metadata = const {},
  });

  double get opsPerSecond => iterations / elapsed.inMicroseconds * 1000000;

  double get microsecondsPerOp => elapsed.inMicroseconds / iterations;

  /// Check against threshold and warn if regression detected
  void checkThreshold(PerfThreshold threshold) {
    final warnings = <String>[];

    if (threshold.minOpsPerSecond > 0 &&
        opsPerSecond < threshold.minOpsPerSecond) {
      warnings.add(
        'ops/sec ${opsPerSecond.toStringAsFixed(0)} < threshold ${threshold.minOpsPerSecond.toStringAsFixed(0)}',
      );
    }

    if (threshold.maxMicroseconds != null &&
        microsecondsPerOp > threshold.maxMicroseconds!) {
      warnings.add(
        'latency ${microsecondsPerOp.toStringAsFixed(1)}µs > threshold ${threshold.maxMicroseconds!.toStringAsFixed(1)}µs',
      );
    }

    if (warnings.isNotEmpty) {
      print('⚠️  PERF WARNING [${threshold.name}]: ${warnings.join(', ')}');
    } else {
      print('✓  PERF OK [${threshold.name}]: '
          '${opsPerSecond.toStringAsFixed(0)} ops/sec, '
          '${microsecondsPerOp.toStringAsFixed(1)}µs/op');
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'iterations': iterations,
        'elapsedMs': elapsed.inMilliseconds,
        'opsPerSecond': opsPerSecond,
        'microsecondsPerOp': microsecondsPerOp,
        'metadata': metadata,
      };
}

/// Run a benchmark with warmup
Future<PerfResult> runBenchmark({
  required String name,
  required int iterations,
  required Future<void> Function() operation,
  int warmupIterations = 100,
  Map<String, dynamic> metadata = const {},
}) async {
  // Warmup
  for (var i = 0; i < warmupIterations; i++) {
    await operation();
  }

  // Actual benchmark
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await operation();
  }
  stopwatch.stop();

  return PerfResult(
    name: name,
    iterations: iterations,
    elapsed: stopwatch.elapsed,
    metadata: metadata,
  );
}

/// Run a synchronous benchmark with warmup
PerfResult runBenchmarkSync({
  required String name,
  required int iterations,
  required void Function() operation,
  int warmupIterations = 100,
  Map<String, dynamic> metadata = const {},
}) {
  // Warmup
  for (var i = 0; i < warmupIterations; i++) {
    operation();
  }

  // Actual benchmark
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    operation();
  }
  stopwatch.stop();

  return PerfResult(
    name: name,
    iterations: iterations,
    elapsed: stopwatch.elapsed,
    metadata: metadata,
  );
}

/// Load historical results for comparison
Future<Map<String, dynamic>?> loadHistoricalResults(String version) async {
  final file = File('benchmark/results/$version.json');
  if (!await file.exists()) return null;
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}

/// Save results for a release version
Future<void> saveResults(String version, List<PerfResult> results) async {
  final file = File('benchmark/results/$version.json');
  await file.parent.create(recursive: true);

  final data = {
    'version': version,
    'timestamp': DateTime.now().toIso8601String(),
    'results': results.map((r) => r.toJson()).toList(),
  };

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}
