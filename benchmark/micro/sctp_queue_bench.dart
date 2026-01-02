/// SCTP Queue Operations Benchmark
///
/// Measures the performance impact of different queue implementations
/// for SCTP sent/outbound queue operations.
///
/// Usage: dart run benchmark/micro/sctp_queue_bench.dart

import 'dart:collection';

/// Simulated sent chunk (minimal for benchmarking)
class SentChunk {
  final int tsn;
  bool acked = false;
  bool abandoned = false;

  SentChunk(this.tsn);
}

void main() {
  print('SCTP Queue Operations Benchmark');
  print('=' * 60);

  // Test different queue sizes
  final sizes = [100, 500, 1000, 5000];

  for (final size in sizes) {
    print('\n--- Queue size: $size chunks ---\n');

    benchmarkListRemoveAt(size);
    benchmarkListRemoveRange(size);
    benchmarkQueueRemoveFirst(size);
    benchmarkLinkedListRemoveFirst(size);
  }

  print('\n' + '=' * 60);
  print('Benchmark complete');
}

/// Benchmark: List with repeated removeAt(0) - current implementation
void benchmarkListRemoveAt(int size) {
  const iterations = 1000;
  final stopwatch = Stopwatch();

  // Warmup
  for (var w = 0; w < 10; w++) {
    final list = List.generate(size, (i) => SentChunk(i));
    while (list.isNotEmpty && list.first.tsn < size ~/ 2) {
      list.removeAt(0);
    }
  }

  stopwatch.start();
  for (var iter = 0; iter < iterations; iter++) {
    final list = List.generate(size, (i) => SentChunk(i));
    // Simulate SACK processing - remove first half
    while (list.isNotEmpty && list.first.tsn < size ~/ 2) {
      list.removeAt(0);
    }
  }
  stopwatch.stop();

  final totalMs = stopwatch.elapsedMicroseconds / 1000;
  final perIter = totalMs / iterations;
  print('List removeAt(0):     ${perIter.toStringAsFixed(3)} ms/iter');
}

/// Benchmark: List with batch removeRange - optimized pattern
void benchmarkListRemoveRange(int size) {
  const iterations = 1000;
  final stopwatch = Stopwatch();

  // Warmup
  for (var w = 0; w < 10; w++) {
    final list = List.generate(size, (i) => SentChunk(i));
    var removeCount = 0;
    for (var i = 0; i < list.length; i++) {
      if (list[i].tsn >= size ~/ 2) break;
      removeCount++;
    }
    if (removeCount > 0) list.removeRange(0, removeCount);
  }

  stopwatch.start();
  for (var iter = 0; iter < iterations; iter++) {
    final list = List.generate(size, (i) => SentChunk(i));
    // Find cutoff first, then batch remove
    var removeCount = 0;
    for (var i = 0; i < list.length; i++) {
      if (list[i].tsn >= size ~/ 2) break;
      removeCount++;
    }
    if (removeCount > 0) list.removeRange(0, removeCount);
  }
  stopwatch.stop();

  final totalMs = stopwatch.elapsedMicroseconds / 1000;
  final perIter = totalMs / iterations;
  print('List removeRange:     ${perIter.toStringAsFixed(3)} ms/iter');
}

/// Benchmark: Queue with removeFirst() - O(1) removal
void benchmarkQueueRemoveFirst(int size) {
  const iterations = 1000;
  final stopwatch = Stopwatch();

  // Warmup
  for (var w = 0; w < 10; w++) {
    final queue = Queue<SentChunk>.from(
      List.generate(size, (i) => SentChunk(i)),
    );
    while (queue.isNotEmpty && queue.first.tsn < size ~/ 2) {
      queue.removeFirst();
    }
  }

  stopwatch.start();
  for (var iter = 0; iter < iterations; iter++) {
    final queue = Queue<SentChunk>.from(
      List.generate(size, (i) => SentChunk(i)),
    );
    // Simulate SACK processing - remove first half
    while (queue.isNotEmpty && queue.first.tsn < size ~/ 2) {
      queue.removeFirst();
    }
  }
  stopwatch.stop();

  final totalMs = stopwatch.elapsedMicroseconds / 1000;
  final perIter = totalMs / iterations;
  print('Queue removeFirst:    ${perIter.toStringAsFixed(3)} ms/iter');
}

/// Benchmark: LinkedList with removeFirst()
void benchmarkLinkedListRemoveFirst(int size) {
  const iterations = 1000;
  final stopwatch = Stopwatch();

  // Warmup
  for (var w = 0; w < 10; w++) {
    final list = LinkedList<_LinkedChunk>();
    for (var i = 0; i < size; i++) {
      list.add(_LinkedChunk(SentChunk(i)));
    }
    while (list.isNotEmpty && list.first.chunk.tsn < size ~/ 2) {
      list.first.unlink();
    }
  }

  stopwatch.start();
  for (var iter = 0; iter < iterations; iter++) {
    final list = LinkedList<_LinkedChunk>();
    for (var i = 0; i < size; i++) {
      list.add(_LinkedChunk(SentChunk(i)));
    }
    // Simulate SACK processing - remove first half
    while (list.isNotEmpty && list.first.chunk.tsn < size ~/ 2) {
      list.first.unlink();
    }
  }
  stopwatch.stop();

  final totalMs = stopwatch.elapsedMicroseconds / 1000;
  final perIter = totalMs / iterations;
  print('LinkedList unlink:    ${perIter.toStringAsFixed(3)} ms/iter');
}

/// LinkedList entry wrapper
final class _LinkedChunk extends LinkedListEntry<_LinkedChunk> {
  final SentChunk chunk;
  _LinkedChunk(this.chunk);
}
