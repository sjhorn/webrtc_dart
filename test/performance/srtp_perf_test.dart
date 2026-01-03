/// SRTP Performance Regression Tests
///
/// Tests SRTP encrypt/decrypt throughput to catch regressions.
/// Warns (does not fail) when performance drops below thresholds.
///
/// Run: dart test test/performance/srtp_perf_test.dart
@Tags(['performance'])
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

import 'perf_test_utils.dart';

void main() {
  group('SRTP Performance', () {
    late Uint8List masterKey;
    late Uint8List masterSalt;

    setUp(() {
      masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      masterSalt = Uint8List.fromList(List.generate(14, (i) => i + 16));
    });

    test('encrypt throughput meets threshold (1KB payload)', () async {
      const payloadSize = 1000;
      const iterations = 5000;

      // Create test packets with unique sequence numbers
      final packets = List.generate(
        iterations + 100,
        (i) => RtpPacket(
          payloadType: 96,
          sequenceNumber: i & 0xFFFF,
          timestamp: i * 3000,
          ssrc: 0x12345678,
          payload: Uint8List(payloadSize),
        ),
      );

      var packetIndex = 0;
      final cipher = SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);

      final result = await runBenchmark(
        name: 'SRTP encrypt 1KB',
        iterations: iterations,
        warmupIterations: 100,
        operation: () async {
          await cipher.encrypt(packets[packetIndex++]);
        },
        metadata: {'payloadSize': payloadSize},
      );

      // Threshold: >20,000 packets/sec (current ~24,000)
      // This gives 20% headroom for normal variance
      result.checkThreshold(PerfThreshold(
        name: 'SRTP encrypt 1KB',
        minOpsPerSecond: 20000,
      ));
    });

    test('encrypt throughput meets threshold (100B payload)', () async {
      const payloadSize = 100;
      const iterations = 10000;

      final packets = List.generate(
        iterations + 100,
        (i) => RtpPacket(
          payloadType: 96,
          sequenceNumber: i & 0xFFFF,
          timestamp: i * 3000,
          ssrc: 0x12345678,
          payload: Uint8List(payloadSize),
        ),
      );

      var packetIndex = 0;
      final cipher = SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);

      final result = await runBenchmark(
        name: 'SRTP encrypt 100B',
        iterations: iterations,
        warmupIterations: 100,
        operation: () async {
          await cipher.encrypt(packets[packetIndex++]);
        },
        metadata: {'payloadSize': payloadSize},
      );

      // Threshold: >25,000 packets/sec for small packets
      result.checkThreshold(PerfThreshold(
        name: 'SRTP encrypt 100B',
        minOpsPerSecond: 25000,
      ));
    });

    test('decrypt throughput meets threshold (1KB payload)', () async {
      const payloadSize = 1000;
      const iterations = 5000;

      // Pre-encrypt packets
      final encryptCipher =
          SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);
      final encryptedPackets = <Uint8List>[];

      for (var i = 0; i < iterations + 100; i++) {
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: i & 0xFFFF,
          timestamp: i * 3000,
          ssrc: 0x12345678,
          payload: Uint8List(payloadSize),
        );
        encryptedPackets.add(await encryptCipher.encrypt(packet));
      }

      var packetIndex = 0;
      final decryptCipher =
          SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);

      final result = await runBenchmark(
        name: 'SRTP decrypt 1KB',
        iterations: iterations,
        warmupIterations: 100,
        operation: () async {
          await decryptCipher.decrypt(encryptedPackets[packetIndex++]);
        },
        metadata: {'payloadSize': payloadSize},
      );

      // Threshold: >20,000 packets/sec
      result.checkThreshold(PerfThreshold(
        name: 'SRTP decrypt 1KB',
        minOpsPerSecond: 20000,
      ));
    });
  });
}
