/// Save Benchmark Results
///
/// Runs all performance tests and saves results to `benchmark/results/{version}.json`
///
/// Usage:
///   dart run benchmark/save_results.dart          # Uses version from pubspec.yaml
///   dart run benchmark/save_results.dart v0.24.0  # Explicit version
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  // Get version from args or pubspec.yaml
  final version = args.isNotEmpty ? args[0] : await getVersionFromPubspec();

  print('Saving benchmark results for version: $version');
  print('=' * 60);

  // Run performance tests and capture output
  final result = await Process.run(
    'dart',
    ['test', 'test/performance/', '--reporter=json'],
    workingDirectory: Directory.current.path,
  );

  if (result.exitCode != 0) {
    print('Error running tests:');
    print(result.stderr);
    exit(1);
  }

  // Parse JSON output to extract performance metrics
  final metrics = await runBenchmarksAndCollect();

  // Save results
  final resultsDir = Directory('benchmark/results');
  await resultsDir.create(recursive: true);

  final outputFile = File('${resultsDir.path}/$version.json');
  final data = {
    'version': version,
    'timestamp': DateTime.now().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version.split(' ').first,
    'results': metrics,
  };

  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
  );

  print('\nResults saved to: ${outputFile.path}');
  print('\nSummary:');
  for (final metric in metrics) {
    print(
        '  ${metric['name']}: ${metric['opsPerSecond'].toStringAsFixed(0)} ops/sec');
  }
}

Future<String> getVersionFromPubspec() async {
  final pubspec = File('pubspec.yaml');
  final content = await pubspec.readAsString();
  final match =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(content);
  return match?.group(1)?.trim() ?? 'unknown';
}

Future<List<Map<String, dynamic>>> runBenchmarksAndCollect() async {
  final metrics = <Map<String, dynamic>>[];

  // Run each benchmark individually and parse output
  final benchmarks = [
    BenchmarkConfig('SRTP encrypt 1KB', 'test/performance/srtp_perf_test.dart',
        'encrypt throughput meets threshold (1KB payload)'),
    BenchmarkConfig('SRTP decrypt 1KB', 'test/performance/srtp_perf_test.dart',
        'decrypt throughput meets threshold'),
    BenchmarkConfig('RTP parse', 'test/performance/rtp_perf_test.dart',
        'parse throughput meets threshold'),
    BenchmarkConfig('RTP serialize', 'test/performance/rtp_perf_test.dart',
        'serialize throughput meets threshold'),
    BenchmarkConfig(
        'SDP parse realistic',
        'test/performance/sdp_perf_test.dart',
        'parse realistic SDP meets threshold'),
    BenchmarkConfig('STUN parse', 'test/performance/stun_perf_test.dart',
        'parse binding request meets threshold'),
    BenchmarkConfig(
        'SCTP batch removal',
        'test/performance/sctp_perf_test.dart',
        'batch queue removal meets threshold'),
  ];

  for (final config in benchmarks) {
    print('\nRunning: ${config.name}...');

    final result = await Process.run(
      'dart',
      ['test', config.testFile, '--name', config.testName],
      workingDirectory: Directory.current.path,
    );

    // Parse the PERF OK/WARNING output
    final output = result.stdout.toString();
    final match = RegExp(r'(\d+) ops/sec').firstMatch(output);

    if (match != null) {
      final opsPerSec = int.parse(match.group(1)!);
      metrics.add({
        'name': config.name,
        'opsPerSecond': opsPerSec,
        'testFile': config.testFile,
      });
      print('  ${config.name}: $opsPerSec ops/sec');
    } else {
      print('  ${config.name}: Could not parse result');
    }
  }

  return metrics;
}

class BenchmarkConfig {
  final String name;
  final String testFile;
  final String testName;

  BenchmarkConfig(this.name, this.testFile, this.testName);
}
