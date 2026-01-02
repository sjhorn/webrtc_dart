// Benchmark Runner
//
// Runs all Dart benchmarks and reports results.
//
// Usage: dart run benchmark/run_all.dart

import 'dart:io';

void main() async {
  print('webrtc_dart Benchmark Suite');
  print('=' * 60);
  print('');

  final benchmarks = [
    'benchmark/micro/srtp_encrypt_bench.dart',
  ];

  for (final benchmark in benchmarks) {
    final file = File(benchmark);
    if (!file.existsSync()) {
      print('Skipping $benchmark (not found)');
      continue;
    }

    print('Running: $benchmark');
    print('-' * 60);

    final result = await Process.run('dart', ['run', benchmark]);
    stdout.write(result.stdout);
    if (result.stderr.toString().isNotEmpty) {
      stderr.write(result.stderr);
    }
    print('');
  }

  print('=' * 60);
  print('All benchmarks complete');
}
