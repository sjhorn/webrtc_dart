// Benchmark Runner
//
// Runs all Dart benchmarks and reports results.
//
// Usage:
//   dart run benchmark/run_all.dart           # Run micro benchmarks
//   dart run benchmark/run_all.dart --perf    # Run performance tests
//   dart run benchmark/run_all.dart --all     # Run everything

import 'dart:io';

void main(List<String> args) async {
  final runPerf = args.contains('--perf') || args.contains('--all');
  final runMicro = !args.contains('--perf') || args.contains('--all');

  print('webrtc_dart Benchmark Suite');
  print('=' * 60);
  print('');

  if (runMicro) {
    print('>>> Micro Benchmarks');
    print('-' * 60);

    final benchmarks = [
      'benchmark/micro/srtp_encrypt_bench.dart',
      'benchmark/micro/sctp_queue_bench.dart',
      'benchmark/micro/timer_bench.dart',
    ];

    for (final benchmark in benchmarks) {
      final file = File(benchmark);
      if (!file.existsSync()) {
        print('Skipping $benchmark (not found)');
        continue;
      }

      print('\nRunning: $benchmark');
      print('-' * 40);

      final result = await Process.run('dart', ['run', benchmark]);
      stdout.write(result.stdout);
      if (result.stderr.toString().isNotEmpty) {
        stderr.write(result.stderr);
      }
    }
    print('');
  }

  if (runPerf) {
    print('>>> Performance Regression Tests');
    print('-' * 60);

    final result = await Process.run(
      'dart',
      ['test', 'test/performance/'],
      workingDirectory: Directory.current.path,
    );

    stdout.write(result.stdout);
    if (result.stderr.toString().isNotEmpty) {
      stderr.write(result.stderr);
    }
    print('');
  }

  print('=' * 60);
  print('All benchmarks complete');
  print('');
  print('Usage:');
  print('  dart run benchmark/run_all.dart           # Micro benchmarks only');
  print('  dart run benchmark/run_all.dart --perf    # Performance tests only');
  print('  dart run benchmark/run_all.dart --all     # Run everything');
}
