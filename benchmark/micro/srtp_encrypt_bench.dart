// SRTP Encryption Benchmark
//
// Measures encryption throughput for webrtc_dart SRTP implementation.
// Compare results against werift-webrtc (benchmark/werift/srtp_bench.mjs)
//
// Usage: dart run benchmark/micro/srtp_encrypt_bench.dart

import 'dart:typed_data';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() async {
  print('SRTP Encryption Benchmark');
  print('=' * 60);

  // Test parameters
  final payloadSizes = [100, 500, 1000, 1200];
  final iterations = 10000;
  final warmupIterations = 1000;

  // Setup cipher with test keys
  final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
  final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

  for (final payloadSize in payloadSizes) {
    print('\n--- Payload size: $payloadSize bytes ---');

    // Create test packets (different sequence numbers)
    final packets = List.generate(
      iterations + warmupIterations,
      (i) => RtpPacket(
        payloadType: 96,
        sequenceNumber: i & 0xFFFF,
        timestamp: i * 3000,
        ssrc: 0x12345678,
        payload: Uint8List(payloadSize),
      ),
    );

    // Warmup
    print('Warming up ($warmupIterations iterations)...');
    var cipher = SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);
    for (var i = 0; i < warmupIterations; i++) {
      await cipher.encrypt(packets[i]);
    }

    // Reset cipher for actual benchmark
    cipher = SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);

    // Benchmark
    print('Running benchmark ($iterations iterations)...');
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < iterations; i++) {
      await cipher.encrypt(packets[warmupIterations + i]);
    }

    stopwatch.stop();

    // Calculate metrics
    final totalMs = stopwatch.elapsedMilliseconds;
    final totalBytes = iterations * payloadSize;
    final packetsPerSecond =
        totalMs > 0 ? (iterations / totalMs * 1000).toStringAsFixed(1) : 'N/A';
    final bytesPerSecond = totalMs > 0
        ? ((totalBytes / totalMs * 1000) / 1024 / 1024).toStringAsFixed(2)
        : 'N/A';
    final usPerPacket =
        totalMs > 0 ? (totalMs * 1000 / iterations).toStringAsFixed(2) : 'N/A';

    print('Results:');
    print('  Total time:       $totalMs ms');
    print('  Packets/second:   $packetsPerSecond');
    print('  Throughput:       $bytesPerSecond MB/s');
    print('  Time per packet:  $usPerPacket us');
  }

  print('\n${'=' * 60}');
  print('Benchmark complete');
  print('');
  print('Optimizations applied:');
  print('  - Using package:cryptography AesGcm (vs pointycastle)');
  print('  - Cached cipher instance across packets');
  print('  - Pre-allocated nonce buffer');
  print('  - Cached SecretKey object');
  print('');
  print('See ROADMAP.md for comparison with werift-webrtc');
}
