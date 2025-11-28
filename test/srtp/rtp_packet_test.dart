import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RtpPacket', () {
    test('serializes and parses basic packet', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 987654321,
        ssrc: 0x12345678,
        payload: payload,
      );

      final serialized = packet.serialize();
      expect(serialized.length, RtpPacket.fixedHeaderSize + payload.length);

      final parsed = RtpPacket.parse(serialized);
      expect(parsed.version, 2);
      expect(parsed.payloadType, 96);
      expect(parsed.sequenceNumber, 12345);
      expect(parsed.timestamp, 987654321);
      expect(parsed.ssrc, 0x12345678);
      expect(parsed.payload, equals(payload));
    });

    test('handles marker bit', () {
      final packet = RtpPacket(
        marker: true,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 1000,
        ssrc: 0x11111111,
        payload: Uint8List(10),
      );

      final serialized = packet.serialize();
      final parsed = RtpPacket.parse(serialized);

      expect(parsed.marker, true);
    });

    test('handles CSRCs', () {
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 1000,
        ssrc: 0x11111111,
        csrcs: [0xAAAAAAAA, 0xBBBBBBBB],
        payload: Uint8List(10),
      );

      final serialized = packet.serialize();
      final parsed = RtpPacket.parse(serialized);

      expect(parsed.csrcCount, 2);
      expect(parsed.csrcs.length, 2);
      expect(parsed.csrcs[0], 0xAAAAAAAA);
      expect(parsed.csrcs[1], 0xBBBBBBBB);
    });

    test('handles padding', () {
      final packet = RtpPacket(
        padding: true,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 1000,
        ssrc: 0x11111111,
        payload: Uint8List(10),
        paddingLength: 4,
      );

      final serialized = packet.serialize();
      expect(serialized.length, RtpPacket.fixedHeaderSize + 10 + 4);

      final parsed = RtpPacket.parse(serialized);
      expect(parsed.padding, true);
      expect(parsed.paddingLength, 4);
      expect(parsed.payload.length, 10);
    });

    test('calculates header size correctly', () {
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 1000,
        ssrc: 0x11111111,
        csrcs: [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC],
        payload: Uint8List(100),
      );

      expect(packet.headerSize, RtpPacket.fixedHeaderSize + 12); // 3 CSRCs * 4
      expect(packet.size, packet.headerSize + 100);
    });

    test('rejects packet with invalid version', () {
      final data = Uint8List(12);
      data[0] = 0x00; // Version 0

      expect(() => RtpPacket.parse(data), throwsFormatException);
    });

    test('rejects packet that is too short', () {
      final data = Uint8List(10); // Less than fixed header size

      expect(() => RtpPacket.parse(data), throwsFormatException);
    });
  });
}
