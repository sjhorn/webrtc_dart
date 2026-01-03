/// Codec Depacketizer Performance Regression Tests
///
/// Tests VP8 and H.264 depacketization - called for every video packet.
///
/// Run: dart test test/performance/codec_perf_test.dart
@Tags(['performance'])
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/vp8.dart';
import 'package:webrtc_dart/src/codec/h264.dart';

import 'perf_test_utils.dart';

void main() {
  group('VP8 Depacketizer Performance', () {
    test('simple packet depacketization meets threshold', () {
      const iterations = 200000;

      // VP8 packet with minimal header (no extensions)
      // X=0, R=0, N=0, S=1, PID=0, then 1000 bytes payload
      final packet = Uint8List(1001);
      packet[0] = 0x10; // S=1, rest=0
      // Rest is payload (zeros)

      final result = runBenchmarkSync(
        name: 'VP8 depacketize simple',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          Vp8RtpPayload.deserialize(packet);
        },
        metadata: {'packetSize': packet.length},
      );

      // Threshold: >500,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'VP8 depacketize simple',
        minOpsPerSecond: 500000,
      ));
    });

    test('extended header depacketization meets threshold', () {
      const iterations = 200000;

      // VP8 packet with extended header (X=1, I=1, 15-bit picture ID)
      // X=1, R=0, N=0, S=1, PID=0 (byte 0)
      // I=1, L=0, T=0, K=0 (byte 1)
      // M=1, PictureID high (byte 2)
      // PictureID low (byte 3)
      // Then 1000 bytes payload
      final packet = Uint8List(1004);
      packet[0] = 0x90; // X=1, S=1
      packet[1] = 0x80; // I=1
      packet[2] = 0x80 | 0x12; // M=1, PictureID high
      packet[3] = 0x34; // PictureID low

      final result = runBenchmarkSync(
        name: 'VP8 depacketize extended',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          Vp8RtpPayload.deserialize(packet);
        },
        metadata: {'packetSize': packet.length, 'extended': true},
      );

      // Threshold: >400,000 ops/sec (slightly slower due to extension parsing)
      result.checkThreshold(PerfThreshold(
        name: 'VP8 depacketize extended',
        minOpsPerSecond: 400000,
      ));
    });
  });

  group('H.264 Depacketizer Performance', () {
    test('single NAL unit depacketization meets threshold', () {
      const iterations = 200000;

      // H.264 single NAL unit (type 1-23)
      // NAL header: F=0, NRI=11, Type=1 (non-IDR slice)
      final packet = Uint8List(1001);
      packet[0] = 0x61; // F=0, NRI=3, Type=1

      final result = runBenchmarkSync(
        name: 'H264 depacketize single NAL',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          H264RtpPayload.deserialize(packet);
        },
        metadata: {'packetSize': packet.length, 'nalType': 'single'},
      );

      // Threshold: >500,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'H264 depacketize single NAL',
        minOpsPerSecond: 500000,
      ));
    });

    test('STAP-A aggregation depacketization meets threshold', () {
      const iterations = 100000;

      // H.264 STAP-A packet with 3 NAL units
      // NAL header: Type=24 (STAP-A)
      // Each NAL: 2-byte length + NAL header + data
      final packet = Uint8List(100);
      packet[0] = 0x78; // F=0, NRI=3, Type=24 (STAP-A)

      // NAL 1: length=10
      packet[1] = 0x00;
      packet[2] = 0x0A;
      packet[3] = 0x67; // SPS

      // NAL 2: length=10
      packet[14] = 0x00;
      packet[15] = 0x0A;
      packet[16] = 0x68; // PPS

      // NAL 3: length=remaining
      packet[27] = 0x00;
      packet[28] = 0x0A;
      packet[29] = 0x65; // IDR

      final result = runBenchmarkSync(
        name: 'H264 depacketize STAP-A',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          H264RtpPayload.deserialize(packet);
        },
        metadata: {'packetSize': packet.length, 'nalType': 'STAP-A'},
      );

      // Threshold: >200,000 ops/sec (multi-NAL parsing is slower)
      result.checkThreshold(PerfThreshold(
        name: 'H264 depacketize STAP-A',
        minOpsPerSecond: 200000,
      ));
    });

    test('FU-A fragment start depacketization meets threshold', () {
      const iterations = 200000;

      // H.264 FU-A packet (type 28) - fragment start
      // NAL header: Type=28 (FU-A)
      // FU header: S=1, E=0, R=0, Type=5 (IDR)
      final packet = Uint8List(1002);
      packet[0] = 0x7C; // F=0, NRI=3, Type=28 (FU-A)
      packet[1] = 0x85; // S=1, E=0, R=0, Type=5

      final result = runBenchmarkSync(
        name: 'H264 depacketize FU-A start',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          H264RtpPayload.deserialize(packet);
        },
        metadata: {
          'packetSize': packet.length,
          'nalType': 'FU-A',
          'fragment': 'start'
        },
      );

      // Threshold: >400,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'H264 depacketize FU-A start',
        minOpsPerSecond: 400000,
      ));
    });
  });
}
