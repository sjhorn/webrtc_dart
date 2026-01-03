/// RTP Packet Performance Regression Tests
///
/// Tests RTP packet parse/serialize throughput.
/// These are extremely hot paths - every media packet goes through here.
///
/// Run: dart test test/performance/rtp_perf_test.dart
@Tags(['performance'])
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

import 'perf_test_utils.dart';

void main() {
  group('RTP Packet Performance', () {
    test('parse throughput meets threshold', () {
      const iterations = 100000;

      // Create a realistic RTP packet (1200 byte payload, typical video)
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 3000000,
        ssrc: 0x12345678,
        marker: true,
        payload: Uint8List(1200),
      );
      final serialized = packet.serialize();

      final result = runBenchmarkSync(
        name: 'RTP parse',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          RtpPacket.parse(serialized);
        },
        metadata: {'packetSize': serialized.length},
      );

      // Threshold: >500,000 packets/sec
      // RTP parsing should be extremely fast (no crypto, just binary parsing)
      result.checkThreshold(PerfThreshold(
        name: 'RTP parse',
        minOpsPerSecond: 500000,
      ));
    });

    test('serialize throughput meets threshold', () {
      const iterations = 100000;

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 3000000,
        ssrc: 0x12345678,
        marker: true,
        payload: Uint8List(1200),
      );

      final result = runBenchmarkSync(
        name: 'RTP serialize',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          packet.serialize();
        },
        metadata: {'payloadSize': 1200},
      );

      // Threshold: >500,000 packets/sec
      result.checkThreshold(PerfThreshold(
        name: 'RTP serialize',
        minOpsPerSecond: 500000,
      ));
    });

    test('parse with extensions meets threshold', () {
      const iterations = 50000;

      // RTP packet with header extension (common for WebRTC - mid, abs-send-time, etc.)
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 3000000,
        ssrc: 0x12345678,
        marker: true,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE, // One-byte header extension
          data: Uint8List.fromList([
            0x10, 0x01, // mid=1
            0x21, 0x00, 0x00, // abs-send-time
            0x00, // padding
          ]),
        ),
        payload: Uint8List(1200),
      );
      final serialized = packet.serialize();

      final result = runBenchmarkSync(
        name: 'RTP parse with extensions',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          RtpPacket.parse(serialized);
        },
        metadata: {'packetSize': serialized.length, 'hasExtension': true},
      );

      // Threshold: >300,000 packets/sec (slightly slower due to extension parsing)
      result.checkThreshold(PerfThreshold(
        name: 'RTP parse with extensions',
        minOpsPerSecond: 300000,
      ));
    });

    test('round-trip (serialize + parse) meets threshold', () {
      const iterations = 50000;

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 3000000,
        ssrc: 0x12345678,
        marker: true,
        payload: Uint8List(1200),
      );

      final result = runBenchmarkSync(
        name: 'RTP round-trip',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          final serialized = packet.serialize();
          RtpPacket.parse(serialized);
        },
      );

      // Threshold: >200,000 round-trips/sec
      result.checkThreshold(PerfThreshold(
        name: 'RTP round-trip',
        minOpsPerSecond: 200000,
      ));
    });
  });
}
