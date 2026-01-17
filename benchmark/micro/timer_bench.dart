/// Timer vs scheduleMicrotask Benchmark
///
/// Measures the latency difference between scheduling mechanisms.
///
/// Usage: dart run benchmark/micro/timer_bench.dart
library;

import 'dart:async';

void main() async {
  print('Timer Scheduling Benchmark');
  print('=' * 60);

  const iterations = 10000;

  // Warmup
  for (var i = 0; i < 100; i++) {
    await Future(() {});
  }

  print('\nIterations: $iterations\n');

  // Benchmark: Timer(Duration.zero)
  final sw1 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final completer = Completer<void>();
    Timer(Duration.zero, completer.complete);
    await completer.future;
  }
  sw1.stop();
  final timerUs = sw1.elapsedMicroseconds / iterations;
  print('Timer(Duration.zero):  ${timerUs.toStringAsFixed(2)} µs/call');

  // Benchmark: scheduleMicrotask
  final sw2 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final completer = Completer<void>();
    scheduleMicrotask(completer.complete);
    await completer.future;
  }
  sw2.stop();
  final microUs = sw2.elapsedMicroseconds / iterations;
  print('scheduleMicrotask:     ${microUs.toStringAsFixed(2)} µs/call');

  // Benchmark: Future.microtask
  final sw3 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await Future.microtask(() {});
  }
  sw3.stop();
  final futureUs = sw3.elapsedMicroseconds / iterations;
  print('Future.microtask:      ${futureUs.toStringAsFixed(2)} µs/call');

  // Benchmark: Future(() {})
  final sw4 = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await Future(() {});
  }
  sw4.stop();
  final futureDelayUs = sw4.elapsedMicroseconds / iterations;
  print('Future(() {}):         ${futureDelayUs.toStringAsFixed(2)} µs/call');

  print('\n${'-' * 60}');
  print(
      'Speedup (scheduleMicrotask vs Timer): ${(timerUs / microUs).toStringAsFixed(2)}x');
}
