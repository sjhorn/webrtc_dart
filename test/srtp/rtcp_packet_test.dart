import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('RtcpPacketType', () {
    test('enum values have correct codes', () {
      expect(RtcpPacketType.senderReport.value, equals(200));
      expect(RtcpPacketType.receiverReport.value, equals(201));
      expect(RtcpPacketType.sourceDescription.value, equals(202));
      expect(RtcpPacketType.goodbye.value, equals(203));
      expect(RtcpPacketType.applicationDefined.value, equals(204));
      expect(RtcpPacketType.transportFeedback.value, equals(205));
      expect(RtcpPacketType.payloadFeedback.value, equals(206));
    });

    test('fromValue returns correct type', () {
      expect(
          RtcpPacketType.fromValue(200), equals(RtcpPacketType.senderReport));
      expect(
          RtcpPacketType.fromValue(201), equals(RtcpPacketType.receiverReport));
      expect(RtcpPacketType.fromValue(202),
          equals(RtcpPacketType.sourceDescription));
      expect(RtcpPacketType.fromValue(203), equals(RtcpPacketType.goodbye));
      expect(RtcpPacketType.fromValue(204),
          equals(RtcpPacketType.applicationDefined));
      expect(RtcpPacketType.fromValue(205),
          equals(RtcpPacketType.transportFeedback));
      expect(RtcpPacketType.fromValue(206),
          equals(RtcpPacketType.payloadFeedback));
    });

    test('fromValue returns null for unknown values', () {
      expect(RtcpPacketType.fromValue(0), isNull);
      expect(RtcpPacketType.fromValue(199), isNull);
      expect(RtcpPacketType.fromValue(207), isNull);
      expect(RtcpPacketType.fromValue(255), isNull);
    });
  });

  group('RtcpPacket', () {
    test('construction with defaults', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6,
        ssrc: 0x12345678,
        payload: Uint8List(20),
      );

      expect(packet.version, equals(2));
      expect(packet.padding, isFalse);
      expect(packet.reportCount, equals(0));
      expect(packet.packetType, equals(RtcpPacketType.senderReport));
      expect(packet.length, equals(6));
      expect(packet.ssrc, equals(0x12345678));
      expect(packet.paddingLength, equals(0));
    });

    test('headerSize is 8', () {
      expect(RtcpPacket.headerSize, equals(8));
    });

    test('size calculation from length field', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6, // (6 + 1) * 4 = 28 bytes
        ssrc: 0x12345678,
        payload: Uint8List(20),
      );

      expect(packet.size, equals(28));
    });

    test('serialize basic packet', () {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      final packet = RtcpPacket(
        reportCount: 1,
        packetType: RtcpPacketType.receiverReport,
        length: 2, // (2 + 1) * 4 = 12 bytes total
        ssrc: 0xAABBCCDD,
        payload: payload,
      );

      final bytes = packet.serialize();

      // Check header
      expect(bytes[0], equals(0x81)); // V=2, P=0, RC=1
      expect(bytes[1], equals(201)); // RR
      expect(bytes[2], equals(0)); // length high byte
      expect(bytes[3], equals(2)); // length low byte
      expect(bytes[4], equals(0xAA)); // SSRC
      expect(bytes[5], equals(0xBB));
      expect(bytes[6], equals(0xCC));
      expect(bytes[7], equals(0xDD));
      // Check payload
      expect(bytes[8], equals(1));
      expect(bytes[9], equals(2));
      expect(bytes[10], equals(3));
      expect(bytes[11], equals(4));
    });

    test('serialize with padding', () {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      final packet = RtcpPacket(
        padding: true,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 3, // (3 + 1) * 4 = 16 bytes
        ssrc: 0x11111111,
        payload: payload,
        paddingLength: 4,
      );

      final bytes = packet.serialize();

      // Check padding flag
      expect(bytes[0] & 0x20, equals(0x20)); // P bit set

      // Last byte should be padding length
      expect(bytes[15], equals(4));
    });

    test('parse basic packet', () {
      // Construct a valid RTCP SR packet manually
      final data = Uint8List.fromList([
        0x80, // V=2, P=0, RC=0
        200, // SR
        0, 6, // length = 6 (28 bytes total)
        0x12, 0x34, 0x56, 0x78, // SSRC
        // 20 bytes payload
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
        11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
      ]);

      final packet = RtcpPacket.parse(data);

      expect(packet.version, equals(2));
      expect(packet.padding, isFalse);
      expect(packet.reportCount, equals(0));
      expect(packet.packetType, equals(RtcpPacketType.senderReport));
      expect(packet.length, equals(6));
      expect(packet.ssrc, equals(0x12345678));
      expect(packet.payload.length, equals(20));
    });

    test('parse with padding', () {
      final data = Uint8List.fromList([
        0xA0, // V=2, P=1, RC=0
        200, // SR
        0, 3, // length = 3 (16 bytes total)
        0x11, 0x22, 0x33, 0x44, // SSRC
        1, 2, 3, 4, // payload
        0, 0, 0, 4, // 4 bytes padding, last byte is count
      ]);

      final packet = RtcpPacket.parse(data);

      expect(packet.padding, isTrue);
      expect(packet.paddingLength, equals(4));
      expect(packet.payload.length, equals(4)); // payload without padding
    });

    test('parse throws on short packet', () {
      final data = Uint8List(4); // Too short

      expect(
        () => RtcpPacket.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('too short'),
        )),
      );
    });

    test('parse throws on invalid version', () {
      final data = Uint8List.fromList([
        0x00, // V=0 (invalid)
        200,
        0, 1,
        0, 0, 0, 0,
      ]);

      expect(
        () => RtcpPacket.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid RTCP version'),
        )),
      );
    });

    test('parse returns placeholder for unknown packet type (matches werift)', () {
      // Unknown packet types should be skipped silently, matching werift behavior
      // This handles XR (207), AVB (208), and proprietary extensions
      final data = Uint8List.fromList([
        0x80, // V=2
        199, // Unknown packet type
        0, 1, // length = 1 (8 bytes total)
        0, 0, 0, 0,
      ]);

      // Should return a placeholder packet, not throw
      final packet = RtcpPacket.parse(data);
      expect(packet.bytesConsumed, 8); // Correctly advances past unknown packet
    });

    test('parse handles truncated packet gracefully', () {
      // Some devices (e.g., Ring) send RTCP packets shorter than their header claims.
      // Parser should handle these gracefully instead of throwing.
      final data = Uint8List.fromList([
        0x80, // V=2
        200,
        0, 10, // length = 10 (44 bytes expected)
        0, 0, 0, 0,
        // Only 8 bytes provided, not 44
      ]);

      // Should parse successfully with truncated payload
      final packet = RtcpPacket.parse(data);
      expect(packet.packetType, RtcpPacketType.senderReport);
      expect(packet.length, 10);
    });

    test('parse throws on invalid padding length', () {
      final data = Uint8List.fromList([
        0xA0, // V=2, P=1
        200,
        0, 1, // 8 bytes total
        0, 0, 0, 0,
      ]);
      // Padding length would be read from last byte, which is 0

      expect(
        () => RtcpPacket.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid padding length'),
        )),
      );
    });

    test('roundtrip serialize/parse', () {
      // Use a payload size that aligns with the length field
      // length=5 means (5+1)*4 = 24 bytes total, minus 8 header = 16 byte payload
      final original = RtcpPacket(
        reportCount: 3,
        packetType: RtcpPacketType.receiverReport,
        length: 5,
        ssrc: 0xDEADBEEF,
        payload: Uint8List.fromList(
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
      );

      final bytes = original.serialize();
      final parsed = RtcpPacket.parse(bytes);

      expect(parsed.version, equals(original.version));
      expect(parsed.padding, equals(original.padding));
      expect(parsed.reportCount, equals(original.reportCount));
      expect(parsed.packetType, equals(original.packetType));
      expect(parsed.length, equals(original.length));
      expect(parsed.ssrc, equals(original.ssrc));
      expect(parsed.payload, equals(original.payload));
    });

    test('toString returns readable format', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.goodbye,
        length: 1,
        ssrc: 0x12345678,
        payload: Uint8List(0),
      );

      final str = packet.toString();
      expect(str, contains('RtcpPacket'));
      expect(str, contains('goodbye'));
      expect(str, contains('ssrc'));
    });
  });

  group('RtcpCompoundPacket', () {
    test('construction with packets list', () {
      final packet1 = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 1,
        ssrc: 0x11111111,
        payload: Uint8List(0),
      );
      final packet2 = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.sourceDescription,
        length: 1,
        ssrc: 0x22222222,
        payload: Uint8List(0),
      );

      final compound = RtcpCompoundPacket([packet1, packet2]);

      expect(compound.packets.length, equals(2));
    });

    test('serialize concatenates packets', () {
      final packet1 = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 1, // 8 bytes
        ssrc: 0x11111111,
        payload: Uint8List(0),
      );
      final packet2 = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.sourceDescription,
        length: 1, // 8 bytes
        ssrc: 0x22222222,
        payload: Uint8List(0),
      );

      final compound = RtcpCompoundPacket([packet1, packet2]);
      final bytes = compound.serialize();

      expect(bytes.length, equals(16)); // 8 + 8
    });

    test('parse splits compound packet', () {
      // Create two packets back to back
      final data = Uint8List.fromList([
        // First packet (SR, length=1, 8 bytes)
        0x80, 200, 0, 1,
        0x11, 0x11, 0x11, 0x11,
        // Second packet (SDES, length=1, 8 bytes)
        0x80, 202, 0, 1,
        0x22, 0x22, 0x22, 0x22,
      ]);

      final compound = RtcpCompoundPacket.parse(data);

      expect(compound.packets.length, equals(2));
      expect(
          compound.packets[0].packetType, equals(RtcpPacketType.senderReport));
      expect(compound.packets[0].ssrc, equals(0x11111111));
      expect(compound.packets[1].packetType,
          equals(RtcpPacketType.sourceDescription));
      expect(compound.packets[1].ssrc, equals(0x22222222));
    });

    test('parse handles trailing partial data gracefully', () {
      final data = Uint8List.fromList([
        // Complete packet
        0x80, 200, 0, 1,
        0x11, 0x11, 0x11, 0x11,
        // Incomplete data (less than header size)
        0x80, 200, 0,
      ]);

      final compound = RtcpCompoundPacket.parse(data);

      // Should only parse the complete packet
      expect(compound.packets.length, equals(1));
    });

    test('roundtrip serialize/parse compound', () {
      final original = RtcpCompoundPacket([
        RtcpPacket(
          reportCount: 1,
          packetType: RtcpPacketType.receiverReport,
          length: 2,
          ssrc: 0xAAAAAAAA,
          payload: Uint8List.fromList([1, 2, 3, 4]),
        ),
        RtcpPacket(
          reportCount: 0,
          packetType: RtcpPacketType.goodbye,
          length: 1,
          ssrc: 0xBBBBBBBB,
          payload: Uint8List(0),
        ),
      ]);

      final bytes = original.serialize();
      final parsed = RtcpCompoundPacket.parse(bytes);

      expect(parsed.packets.length, equals(2));
      expect(parsed.packets[0].ssrc, equals(original.packets[0].ssrc));
      expect(parsed.packets[1].ssrc, equals(original.packets[1].ssrc));
    });

    test('toString returns readable format', () {
      final compound = RtcpCompoundPacket([
        RtcpPacket(
          reportCount: 0,
          packetType: RtcpPacketType.senderReport,
          length: 1,
          ssrc: 0x11111111,
          payload: Uint8List(0),
        ),
      ]);

      final str = compound.toString();
      expect(str, contains('RtcpCompoundPacket'));
      expect(str, contains('1 packets'));
    });
  });
}
