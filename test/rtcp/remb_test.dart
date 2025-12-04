import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/psfb/remb.dart';

void main() {
  group('ReceiverEstimatedMaxBitrate', () {
    group('constants', () {
      test('fmt is 15', () {
        expect(ReceiverEstimatedMaxBitrate.fmt, equals(15));
      });

      test('uniqueId is REMB', () {
        expect(ReceiverEstimatedMaxBitrate.uniqueId, equals('REMB'));
      });
    });

    group('fromBitrate', () {
      test('creates REMB with small bitrate', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.from(1000000), // 1 Mbps
          ssrcFeedbacks: [0xAABBCCDD],
        );

        expect(remb.senderSsrc, equals(0x12345678));
        expect(remb.mediaSsrc, equals(0));
        expect(remb.ssrcFeedbacks, equals([0xAABBCCDD]));
        expect(remb.ssrcCount, equals(1));
        expect(remb.bitrate, equals(BigInt.from(1000000)));
      });

      test('creates REMB with large bitrate', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.from(100000000), // 100 Mbps
          ssrcFeedbacks: [0x11111111, 0x22222222],
        );

        expect(remb.senderSsrc, equals(0x12345678));
        expect(remb.ssrcFeedbacks.length, equals(2));
        // Bitrate should be approximately 100 Mbps (may have rounding)
        expect(remb.bitrate.toInt(), greaterThan(90000000));
      });

      test('creates REMB with zero bitrate', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.zero,
        );

        expect(remb.brExp, equals(0));
        expect(remb.brMantissa, equals(0));
        expect(remb.bitrate, equals(BigInt.zero));
      });

      test('creates REMB with custom mediaSsrc', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0x87654321,
          bitrate: BigInt.from(5000000),
        );

        expect(remb.mediaSsrc, equals(0x87654321));
      });
    });

    group('serialize', () {
      test('serializes basic REMB', () {
        final remb = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 1,
          brExp: 17,
          brMantissa: 38350,
          bitrate: BigInt.from(38350) << 17, // ~5 Gbps
          ssrcFeedbacks: [0xAABBCCDD],
        );

        final data = remb.serialize();

        // Check minimum size: 12 + 4 = 16 bytes
        expect(data.length, equals(16));

        // Check media SSRC (0)
        expect(data[0], equals(0));
        expect(data[1], equals(0));
        expect(data[2], equals(0));
        expect(data[3], equals(0));

        // Check "REMB" identifier
        expect(String.fromCharCodes(data.sublist(4, 8)), equals('REMB'));

        // Check num SSRCs
        expect(data[8], equals(1));
      });

      test('serializes REMB with multiple SSRCs', () {
        final remb = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 3,
          brExp: 10,
          brMantissa: 1000,
          bitrate: BigInt.from(1000) << 10,
          ssrcFeedbacks: [0x11111111, 0x22222222, 0x33333333],
        );

        final data = remb.serialize();

        // 12 + 12 = 24 bytes
        expect(data.length, equals(24));

        // Check num SSRCs
        expect(data[8], equals(3));
      });

      test('serializes with zero SSRCs', () {
        final remb = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 0,
          brExp: 5,
          brMantissa: 100,
          bitrate: BigInt.from(100) << 5,
          ssrcFeedbacks: [],
        );

        final data = remb.serialize();

        // 12 bytes (no SSRC feedbacks)
        expect(data.length, equals(12));
        expect(data[8], equals(0)); // num SSRCs
      });
    });

    group('deserialize', () {
      test('deserializes basic REMB', () {
        // Create a valid REMB payload
        final data = Uint8List.fromList([
          // Media SSRC = 0
          0x00, 0x00, 0x00, 0x00,
          // "REMB"
          0x52, 0x45, 0x4D, 0x42,
          // Num SSRCs = 1
          0x01,
          // BR Exp = 17 (0x11), Mantissa high 2 bits = 0
          // (17 << 2) | 0 = 68 = 0x44
          0x44,
          // Mantissa = 38350 = 0x95CE
          0x95, 0xCE,
          // SSRC feedback
          0xAA, 0xBB, 0xCC, 0xDD,
        ]);

        final remb = ReceiverEstimatedMaxBitrate.deserialize(
          data,
          senderSsrc: 0x12345678,
        );

        expect(remb.senderSsrc, equals(0x12345678));
        expect(remb.mediaSsrc, equals(0));
        expect(remb.ssrcCount, equals(1));
        expect(remb.brExp, equals(17));
        expect(remb.brMantissa, equals(38350));
        expect(remb.ssrcFeedbacks, equals([0xAABBCCDD]));
      });

      test('deserializes REMB with multiple SSRCs', () {
        final data = Uint8List.fromList([
          // Media SSRC
          0x00, 0x00, 0x00, 0x00,
          // "REMB"
          0x52, 0x45, 0x4D, 0x42,
          // Num SSRCs = 2
          0x02,
          // BR Exp = 10, Mantissa high bits = 0
          0x28, // (10 << 2) | 0
          // Mantissa low = 1024 = 0x0400
          0x04, 0x00,
          // SSRC feedbacks
          0x11, 0x11, 0x11, 0x11,
          0x22, 0x22, 0x22, 0x22,
        ]);

        final remb = ReceiverEstimatedMaxBitrate.deserialize(
          data,
          senderSsrc: 0xDEADBEEF,
        );

        expect(remb.ssrcCount, equals(2));
        expect(remb.brExp, equals(10));
        expect(remb.brMantissa, equals(1024));
        expect(remb.ssrcFeedbacks, equals([0x11111111, 0x22222222]));
      });

      test('throws on invalid identifier', () {
        final data = Uint8List.fromList([
          0x00, 0x00, 0x00, 0x00,
          // Wrong identifier
          0x58, 0x59, 0x5A, 0x5A,
          0x01,
          0x44, 0x95, 0xCE,
        ]);

        expect(
          () =>
              ReceiverEstimatedMaxBitrate.deserialize(data, senderSsrc: 0x1234),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws on short payload', () {
        final data = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);

        expect(
          () =>
              ReceiverEstimatedMaxBitrate.deserialize(data, senderSsrc: 0x1234),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('round-trip', () {
      test('serialize then deserialize preserves data', () {
        final original = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0x87654321,
          bitrate: BigInt.from(5000000), // 5 Mbps
          ssrcFeedbacks: [0xAABBCCDD, 0x11223344],
        );

        final data = original.serialize();
        final restored = ReceiverEstimatedMaxBitrate.deserialize(
          data,
          senderSsrc: 0x12345678,
        );

        expect(restored.senderSsrc, equals(original.senderSsrc));
        expect(restored.mediaSsrc, equals(original.mediaSsrc));
        expect(restored.brExp, equals(original.brExp));
        expect(restored.brMantissa, equals(original.brMantissa));
        expect(restored.ssrcFeedbacks, equals(original.ssrcFeedbacks));
      });

      test('round-trip with various bitrates', () {
        final bitrates = [
          BigInt.from(100000), // 100 kbps
          BigInt.from(1000000), // 1 Mbps
          BigInt.from(10000000), // 10 Mbps
          BigInt.from(100000000), // 100 Mbps
        ];

        for (final bitrate in bitrates) {
          final original = ReceiverEstimatedMaxBitrate.fromBitrate(
            senderSsrc: 0x12345678,
            bitrate: bitrate,
            ssrcFeedbacks: [0xDEADBEEF],
          );

          final data = original.serialize();
          final restored = ReceiverEstimatedMaxBitrate.deserialize(
            data,
            senderSsrc: 0x12345678,
          );

          // Allow some precision loss due to exp/mantissa encoding
          final ratio = restored.bitrate.toDouble() / bitrate.toDouble();
          expect(ratio, greaterThan(0.9));
          expect(ratio, lessThan(1.1));
        }
      });
    });

    group('bitrate helpers', () {
      test('bitrateKbps returns correct value', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.from(5000000), // 5 Mbps
        );

        expect(remb.bitrateKbps, closeTo(5000, 500));
      });

      test('bitrateMbps returns correct value', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.from(10000000), // 10 Mbps
        );

        expect(remb.bitrateMbps, closeTo(10, 1));
      });
    });

    group('equality', () {
      test('equal REMBs are equal', () {
        final remb1 = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 1,
          brExp: 10,
          brMantissa: 1000,
          bitrate: BigInt.from(1000) << 10,
          ssrcFeedbacks: [0xAABBCCDD],
        );

        final remb2 = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 1,
          brExp: 10,
          brMantissa: 1000,
          bitrate: BigInt.from(1000) << 10,
          ssrcFeedbacks: [0xAABBCCDD],
        );

        expect(remb1, equals(remb2));
        expect(remb1.hashCode, equals(remb2.hashCode));
      });

      test('different REMBs are not equal', () {
        final remb1 = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 1,
          brExp: 10,
          brMantissa: 1000,
          bitrate: BigInt.from(1000) << 10,
          ssrcFeedbacks: [0xAABBCCDD],
        );

        final remb2 = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 1,
          brExp: 11, // Different exp
          brMantissa: 1000,
          bitrate: BigInt.from(1000) << 11,
          ssrcFeedbacks: [0xAABBCCDD],
        );

        expect(remb1, isNot(equals(remb2)));
      });
    });

    group('toString', () {
      test('includes relevant information', () {
        final remb = ReceiverEstimatedMaxBitrate.fromBitrate(
          senderSsrc: 0x12345678,
          bitrate: BigInt.from(5000000),
          ssrcFeedbacks: [0xAABBCCDD],
        );

        final str = remb.toString();
        expect(str, contains('ReceiverEstimatedMaxBitrate'));
        expect(str, contains('senderSsrc'));
        expect(str, contains('Mbps'));
      });
    });

    group('edge cases', () {
      test('handles mantissa with high bits set', () {
        // Mantissa = 0x3FFFF (max 18-bit value)
        final data = Uint8List.fromList([
          0x00, 0x00, 0x00, 0x00,
          0x52, 0x45, 0x4D, 0x42,
          0x01,
          // exp=10, mantissa high 2 bits = 3
          (10 << 2) | 3,
          // Mantissa low = 0xFFFF
          0xFF, 0xFF,
          0xAA, 0xBB, 0xCC, 0xDD,
        ]);

        final remb = ReceiverEstimatedMaxBitrate.deserialize(
          data,
          senderSsrc: 0x12345678,
        );

        expect(remb.brMantissa, equals(0x3FFFF));
      });

      test('handles very large bitrate', () {
        final remb = ReceiverEstimatedMaxBitrate(
          senderSsrc: 0x12345678,
          mediaSsrc: 0,
          ssrcCount: 0,
          brExp: 50,
          brMantissa: 100000,
          bitrate: BigInt.from(100000) << 50,
          ssrcFeedbacks: [],
        );

        // Should serialize and deserialize without overflow
        final data = remb.serialize();
        final restored = ReceiverEstimatedMaxBitrate.deserialize(
          data,
          senderSsrc: 0x12345678,
        );

        expect(restored.brExp, equals(50));
        expect(restored.brMantissa, equals(100000));
      });
    });
  });
}
