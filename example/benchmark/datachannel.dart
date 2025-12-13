/// DataChannel Benchmark
///
/// Measures the round-trip time for sending binary messages between two peers.
/// Based on: https://github.com/dguenther/js-datachannel-benchmarks
///
/// Usage: dart run benchmark/datachannel_benchmark.dart
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:webrtc_dart/webrtc_dart.dart';

/// Generate random bytes for testing
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

class BenchmarkResult {
  final String name;
  final int iterations;
  final Duration totalTime;
  final List<Duration> samples;

  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalTime,
    required this.samples,
  });

  double get opsPerSecond => iterations / totalTime.inMicroseconds * 1000000;
  Duration get meanTime =>
      Duration(microseconds: totalTime.inMicroseconds ~/ iterations);
  Duration get minTime => samples.reduce((a, b) => a < b ? a : b);
  Duration get maxTime => samples.reduce((a, b) => a > b ? a : b);

  @override
  String toString() {
    return '$name x ${opsPerSecond.toStringAsFixed(2)} ops/sec '
        '(mean: ${meanTime.inMicroseconds}µs, '
        'min: ${minTime.inMicroseconds}µs, '
        'max: ${maxTime.inMicroseconds}µs)';
  }
}

Future<void> main() async {
  print('DataChannel Benchmark');
  print('=' * 50);
  print('');
  print('Setting up peer connections...');

  // Create two peer connections
  final peer1 = RtcPeerConnection();
  final peer2 = RtcPeerConnection();

  // Wait for transport initialization (certificate generation, etc.)
  await Future.delayed(Duration(milliseconds: 500));

  // Track data channels (ProxyDataChannel for local, DataChannel for remote)
  late ProxyDataChannel dc1;
  late DataChannel dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Set up ICE candidate exchange
  peer1.onIceCandidate.listen((candidate) async {
    await peer2.addIceCandidate(candidate);
  });

  peer2.onIceCandidate.listen((candidate) async {
    await peer1.addIceCandidate(candidate);
  });

  // Handle incoming datachannel on peer2
  peer2.onDataChannel.listen((channel) {
    dc2 = channel;
    if (channel.state == DataChannelState.open) {
      if (!dc2Ready.isCompleted) dc2Ready.complete();
    } else {
      channel.onStateChange.listen((state) {
        if (state == DataChannelState.open && !dc2Ready.isCompleted) {
          dc2Ready.complete();
        }
      });
    }
  });

  // Create datachannel on peer1
  dc1 = peer1.createDataChannel('benchmark');
  dc1.onStateChange.listen((state) {
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  // Perform offer/answer exchange
  final offer = await peer1.createOffer();
  await peer1.setLocalDescription(offer);
  await peer2.setRemoteDescription(offer);

  final answer = await peer2.createAnswer();
  await peer2.setLocalDescription(answer);
  await peer1.setRemoteDescription(answer);

  // Wait for datachannels to be ready
  print('Waiting for DataChannel connections...');
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('DataChannels connected!');
  print('');

  // Run benchmarks with different message sizes
  // Note: Keep messages under 8KB to stay within UDP MTU limits (SCTP fragmentation not fully working)
  final messageSizes = [100, 1000, 2000, 4000];

  for (final size in messageSizes) {
    final result = await runBenchmark(
      name: 'Round-trip ${size}B',
      dc1: dc1,
      dc2: dc2,
      messageSize: size,
      iterations: 100,
      warmupIterations: 10,
    );
    print(result);
  }

  print('');
  print('Benchmark complete.');

  // Calculate throughput with moderate message size
  // Note: Keep message size within UDP MTU limits for reliable transmission
  final largeMessage = randomBytes(4000);
  final throughputResult = await runThroughputBenchmark(
    dc1: dc1,
    dc2: dc2,
    message: largeMessage,
    durationSeconds: 3,
  );
  print('');
  print(
      'Throughput (4KB messages): ${throughputResult.toStringAsFixed(2)} MB/s');

  // Cleanup
  await peer1.close();
  await peer2.close();
}

Future<BenchmarkResult> runBenchmark({
  required String name,
  required dynamic dc1,
  required dynamic dc2,
  required int messageSize,
  required int iterations,
  int warmupIterations = 10,
}) async {
  final message = randomBytes(messageSize);
  final samples = <Duration>[];

  // Warmup
  for (var i = 0; i < warmupIterations; i++) {
    await roundTrip(dc1, dc2, message);
  }

  // Actual benchmark
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < iterations; i++) {
    final sampleStart = stopwatch.elapsed;
    await roundTrip(dc1, dc2, message);
    samples.add(stopwatch.elapsed - sampleStart);
  }

  stopwatch.stop();

  return BenchmarkResult(
    name: name,
    iterations: iterations,
    totalTime: stopwatch.elapsed,
    samples: samples,
  );
}

Future<void> roundTrip(
  dynamic dc1,
  dynamic dc2,
  Uint8List message,
) async {
  final responseCompleter = Completer<void>();

  // dc2 echoes back what it receives
  late final StreamSubscription dc2Sub;
  dc2Sub = dc2.onMessage.listen((msg) {
    dc2.send(msg as Uint8List);
    dc2Sub.cancel();
  });

  // dc1 waits for the echo
  late final StreamSubscription dc1Sub;
  dc1Sub = dc1.onMessage.listen((msg) {
    if (!responseCompleter.isCompleted) {
      responseCompleter.complete();
    }
    dc1Sub.cancel();
  });

  // Send the message
  dc1.send(message);

  // Wait for response
  await responseCompleter.future;
}

Future<double> runThroughputBenchmark({
  required dynamic dc1,
  required dynamic dc2,
  required Uint8List message,
  required int durationSeconds,
}) async {
  var bytesSent = 0;
  var running = true;

  // dc2 just receives and discards
  final dc2Sub = dc2.onMessage.listen((_) {});

  final stopwatch = Stopwatch()..start();

  // Send as fast as possible for the duration
  while (running && stopwatch.elapsed.inSeconds < durationSeconds) {
    dc1.send(message);
    bytesSent += message.length;

    // Small yield to prevent blocking
    if (bytesSent % (message.length * 100) == 0) {
      await Future.delayed(Duration.zero);
    }
  }

  stopwatch.stop();
  running = false;

  await dc2Sub.cancel();

  // Calculate MB/s
  final seconds = stopwatch.elapsedMicroseconds / 1000000;
  final megabytes = bytesSent / (1024 * 1024);

  return megabytes / seconds;
}
