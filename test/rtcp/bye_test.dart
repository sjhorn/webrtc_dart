import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/bye.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('RtcpBye', () {
    group('construction', () {
      test('creates BYE with single SSRC', () {
        final bye = RtcpBye(ssrcs: [0x12345678]);

        expect(bye.ssrcs, equals([0x12345678]));
        expect(bye.reason, isNull);
      });

      test('creates BYE with multiple SSRCs', () {
        final bye = RtcpBye(ssrcs: [0x11111111, 0x22222222, 0x33333333]);

        expect(bye.ssrcs.length, equals(3));
        expect(bye.ssrcs[0], equals(0x11111111));
        expect(bye.ssrcs[1], equals(0x22222222));
        expect(bye.ssrcs[2], equals(0x33333333));
      });

      test('creates BYE with reason', () {
        final bye = RtcpBye(
          ssrcs: [0xAABBCCDD],
          reason: 'Leaving session',
        );

        expect(bye.ssrcs, equals([0xAABBCCDD]));
        expect(bye.reason, equals('Leaving session'));
      });

      test('single() factory creates BYE for one source', () {
        final bye = RtcpBye.single(0x12345678, reason: 'Goodbye');

        expect(bye.ssrcs, equals([0x12345678]));
        expect(bye.reason, equals('Goodbye'));
      });
    });

    group('serialization', () {
      test('serializes single SSRC without reason', () {
        final bye = RtcpBye(ssrcs: [0x12345678]);
        final packet = bye.toPacket();

        expect(packet.packetType, equals(RtcpPacketType.goodbye));
        expect(packet.reportCount, equals(1)); // SC = 1
        expect(packet.ssrc, equals(0x12345678));
        expect(packet.version, equals(2));
      });

      test('serializes multiple SSRCs', () {
        final bye = RtcpBye(ssrcs: [0x11111111, 0x22222222]);
        final packet = bye.toPacket();

        expect(packet.reportCount, equals(2)); // SC = 2
        expect(packet.ssrc, equals(0x11111111)); // First in header

        // Second SSRC should be in payload
        final payload = packet.payload;
        expect(payload.length, greaterThanOrEqualTo(4));
        final buffer = ByteData.sublistView(payload);
        expect(buffer.getUint32(0), equals(0x22222222));
      });

      test('serializes with reason string', () {
        final bye = RtcpBye(ssrcs: [0xAABBCCDD], reason: 'Bye!');
        final bytes = bye.toBytes();

        // Should be padded to 4-byte boundary
        expect(bytes.length % 4, equals(0));
      });

      test('packet size is 4-byte aligned', () {
        // Test various reason lengths to ensure padding works
        for (var reasonLen = 0; reasonLen < 20; reasonLen++) {
          final reason = reasonLen > 0 ? 'x' * reasonLen : null;
          final bye = RtcpBye(ssrcs: [0x12345678], reason: reason);
          final bytes = bye.toBytes();

          expect(bytes.length % 4, equals(0),
              reason: 'Failed for reason length $reasonLen');
        }
      });

      test('truncates reason longer than 255 bytes', () {
        final longReason = 'x' * 300;
        final bye = RtcpBye(ssrcs: [0x12345678], reason: longReason);
        final packet = bye.toPacket();

        // Should not throw, just truncate
        expect(packet.payload, isNotEmpty);
      });
    });

    group('deserialization', () {
      test('parses single SSRC without reason', () {
        final original = RtcpBye(ssrcs: [0x12345678]);
        final bytes = original.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.ssrcs, equals([0x12345678]));
        expect(parsed.reason, isNull);
      });

      test('parses multiple SSRCs', () {
        final original = RtcpBye(ssrcs: [0x11111111, 0x22222222, 0x33333333]);
        final bytes = original.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.ssrcs.length, equals(3));
        expect(parsed.ssrcs[0], equals(0x11111111));
        expect(parsed.ssrcs[1], equals(0x22222222));
        expect(parsed.ssrcs[2], equals(0x33333333));
      });

      test('parses with reason string', () {
        final original = RtcpBye(ssrcs: [0xAABBCCDD], reason: 'Session ended');
        final bytes = original.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.ssrcs, equals([0xAABBCCDD]));
        expect(parsed.reason, equals('Session ended'));
      });

      test('round-trip preserves all data', () {
        final testCases = [
          RtcpBye(ssrcs: [0x12345678]),
          RtcpBye(ssrcs: [0x11111111, 0x22222222]),
          RtcpBye(ssrcs: [0xAABBCCDD], reason: 'Goodbye'),
          RtcpBye(ssrcs: [0x11111111, 0x22222222, 0x33333333], reason: 'Leaving'),
          RtcpBye(ssrcs: [0xDEADBEEF], reason: ''),
        ];

        for (final original in testCases) {
          final bytes = original.toBytes();
          final parsed = RtcpBye.fromBytes(bytes);

          expect(parsed.ssrcs, equals(original.ssrcs),
              reason: 'SSRCs mismatch for $original');
          // Empty string becomes null on parse (no reason bytes)
          if (original.reason != null && original.reason!.isNotEmpty) {
            expect(parsed.reason, equals(original.reason),
                reason: 'Reason mismatch for $original');
          }
        }
      });
    });

    group('fromPacket', () {
      test('throws for non-BYE packet', () {
        final wrongPacket = RtcpPacket(
          reportCount: 0,
          packetType: RtcpPacketType.senderReport,
          length: 1,
          ssrc: 0x12345678,
          payload: Uint8List(0),
        );

        expect(
          () => RtcpBye.fromPacket(wrongPacket),
          throwsA(isA<FormatException>()),
        );
      });

      test('handles empty SSRC list (SC=0)', () {
        final packet = RtcpPacket(
          reportCount: 0, // SC = 0
          packetType: RtcpPacketType.goodbye,
          length: 0,
          ssrc: 0,
          payload: Uint8List(0),
        );

        final bye = RtcpBye.fromPacket(packet);
        expect(bye.ssrcs, isEmpty);
      });
    });

    group('equality', () {
      test('equal BYE packets are equal', () {
        final bye1 = RtcpBye(ssrcs: [0x12345678], reason: 'Goodbye');
        final bye2 = RtcpBye(ssrcs: [0x12345678], reason: 'Goodbye');

        expect(bye1, equals(bye2));
        expect(bye1.hashCode, equals(bye2.hashCode));
      });

      test('different SSRCs are not equal', () {
        final bye1 = RtcpBye(ssrcs: [0x12345678]);
        final bye2 = RtcpBye(ssrcs: [0x87654321]);

        expect(bye1, isNot(equals(bye2)));
      });

      test('different reasons are not equal', () {
        final bye1 = RtcpBye(ssrcs: [0x12345678], reason: 'Goodbye');
        final bye2 = RtcpBye(ssrcs: [0x12345678], reason: 'See ya');

        expect(bye1, isNot(equals(bye2)));
      });
    });

    group('toString', () {
      test('includes SSRCs', () {
        final bye = RtcpBye(ssrcs: [0x12345678]);
        expect(bye.toString(), contains('12345678'));
      });

      test('includes reason when present', () {
        final bye = RtcpBye(ssrcs: [0x12345678], reason: 'Goodbye');
        expect(bye.toString(), contains('Goodbye'));
      });
    });

    group('RFC 3550 compliance', () {
      test('packet type is 203', () {
        final bye = RtcpBye(ssrcs: [0x12345678]);
        final packet = bye.toPacket();

        expect(packet.packetType.value, equals(203));
      });

      test('version is 2', () {
        final bye = RtcpBye(ssrcs: [0x12345678]);
        final packet = bye.toPacket();

        expect(packet.version, equals(2));
      });

      test('SC field matches SSRC count', () {
        for (var count = 1; count <= 5; count++) {
          final ssrcs = List.generate(count, (i) => 0x10000000 + i);
          final bye = RtcpBye(ssrcs: ssrcs);
          final packet = bye.toPacket();

          expect(packet.reportCount, equals(count),
              reason: 'SC should be $count');
        }
      });

      test('reason length prefix is correct', () {
        final bye = RtcpBye(ssrcs: [0x12345678], reason: 'Test');
        final packet = bye.toPacket();

        // Payload should start with length byte
        expect(packet.payload[0], equals(4)); // 'Test' is 4 bytes
      });
    });

    group('edge cases', () {
      test('handles Unicode in reason', () {
        final bye = RtcpBye(ssrcs: [0x12345678], reason: 'Goodbye 👋');
        final bytes = bye.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.reason, equals('Goodbye 👋'));
      });

      test('handles maximum SSRCs (31)', () {
        // SC field is 5 bits, max value is 31
        final ssrcs = List.generate(31, (i) => 0x10000000 + i);
        final bye = RtcpBye(ssrcs: ssrcs);
        final bytes = bye.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.ssrcs.length, equals(31));
      });

      test('handles exactly 255 byte reason', () {
        final reason = 'x' * 255;
        final bye = RtcpBye(ssrcs: [0x12345678], reason: reason);
        final bytes = bye.toBytes();
        final parsed = RtcpBye.fromBytes(bytes);

        expect(parsed.reason?.length, equals(255));
      });
    });
  });
}
