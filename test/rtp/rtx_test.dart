import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/rtx.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RTX Retransmission', () {
    test('should wrap RTP packet as RTX', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
        rtxSequenceNumber: 100,
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 111, // Original payload type
        sequenceNumber: 1234,
        timestamp: 567890,
        ssrc: 0x12345678, // Original SSRC
        csrcs: [],
        extensionHeader: null,
        payload: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]),
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);

      // RTX packet should have different SSRC and payload type
      expect(rtx.ssrc, equals(0x87654321));
      expect(rtx.payloadType, equals(96));
      expect(rtx.sequenceNumber, equals(100));

      // RTX sequence number should increment
      expect(handler.rtxSequenceNumber, equals(101));

      // Timestamp preserved
      expect(rtx.timestamp, equals(567890));

      // Marker preserved
      expect(rtx.marker, isTrue);

      // Payload should be OSN (2 bytes) + original payload
      expect(rtx.payload.length, equals(6)); // 2 + 4

      // Check OSN (Original Sequence Number) in first 2 bytes
      final osnView = ByteData.sublistView(rtx.payload);
      final osn = osnView.getUint16(0);
      expect(osn, equals(1234));

      // Check original payload follows OSN
      expect(rtx.payload.sublist(2), equals([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('should unwrap RTX packet to restore original', () {
      final rtxPayload = Uint8List(6);
      final view = ByteData.sublistView(rtxPayload);
      view.setUint16(0, 1234); // OSN
      rtxPayload.setRange(2, 6, [0xAA, 0xBB, 0xCC, 0xDD]); // Original payload

      final rtx = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 96, // RTX payload type
        sequenceNumber: 100, // RTX sequence number
        timestamp: 567890,
        ssrc: 0x87654321, // RTX SSRC
        csrcs: [],
        extensionHeader: null,
        payload: rtxPayload,
        paddingLength: 0,
      );

      final original = RtxHandler.unwrapRtx(
        rtx,
        111, // Original payload type
        0x12345678, // Original SSRC
      );

      // Should restore original SSRC and payload type
      expect(original.ssrc, equals(0x12345678));
      expect(original.payloadType, equals(111));

      // Should restore original sequence number from OSN
      expect(original.sequenceNumber, equals(1234));

      // Timestamp preserved
      expect(original.timestamp, equals(567890));

      // Marker preserved
      expect(original.marker, isTrue);

      // Payload should be original (without OSN)
      expect(original.payload, equals([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('should handle RTX sequence number wraparound', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
        rtxSequenceNumber: 0xFFFF, // Max uint16
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 5000,
        timestamp: 123456,
        ssrc: 0x12345678,
        csrcs: [],
        extensionHeader: null,
        payload: Uint8List.fromList([0x01, 0x02]),
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);

      expect(rtx.sequenceNumber, equals(0xFFFF));

      // Next RTX should wrap to 0
      final rtx2 = handler.wrapRtx(original);
      expect(rtx2.sequenceNumber, equals(0));
    });

    test('should throw on RTX payload too short', () {
      final rtx = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 567890,
        ssrc: 0x87654321,
        csrcs: [],
        extensionHeader: null,
        payload: Uint8List.fromList([0xAA]), // Only 1 byte, needs 2 for OSN
        paddingLength: 0,
      );

      expect(
        () => RtxHandler.unwrapRtx(rtx, 111, 0x12345678),
        throwsA(isA<FormatException>()),
      );
    });

    test('should preserve CSRCs in RTX wrapping', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1234,
        timestamp: 567890,
        ssrc: 0x12345678,
        csrcs: [0x11111111, 0x22222222],
        extensionHeader: null,
        payload: Uint8List.fromList([0xAA, 0xBB]),
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);

      expect(rtx.csrcs, equals([0x11111111, 0x22222222]));
    });

    test('should preserve extension header in RTX wrapping', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: true,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1234,
        timestamp: 567890,
        ssrc: 0x12345678,
        csrcs: [],
        extensionHeader: RtpExtension(
          profile: 0xBEDE,
          data: Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
        ),
        payload: Uint8List.fromList([0xAA, 0xBB]),
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);

      expect(rtx.extension, isTrue);
      expect(rtx.extensionHeader?.profile, equals(0xBEDE));
      expect(rtx.extensionHeader?.data, equals([0x01, 0x02, 0x03, 0x04]));
    });

    test('uint16Add should handle wraparound', () {
      expect(uint16Add(0xFFFF, 1), equals(0));
      expect(uint16Add(0xFFFF, 2), equals(1));
      expect(uint16Add(0x8000, 0x8000), equals(0));
      expect(uint16Add(100, 200), equals(300));
    });

    test('uint16Gt should handle sequence number comparison with wraparound', () {
      // Normal comparison
      expect(uint16Gt(200, 100), isTrue);
      expect(uint16Gt(100, 200), isFalse);
      expect(uint16Gt(100, 100), isFalse);

      // Wraparound cases
      expect(uint16Gt(100, 0xFFFF), isTrue); // 100 > 65535 (wraparound)
      expect(uint16Gt(0xFFFF, 100), isFalse); // 65535 < 100 (wraparound)

      // Half modulo boundary case
      // When exactly halfMod apart (32768), neither is greater than the other
      expect(uint16Gt(0x4000, 0xC000), isFalse);
      expect(uint16Gt(0xC000, 0x4000), isFalse);
    });

    test('uint16Lt should handle sequence number comparison with wraparound', () {
      // Normal comparison
      expect(uint16Lt(100, 200), isTrue);
      expect(uint16Lt(200, 100), isFalse);
      expect(uint16Lt(100, 100), isFalse);

      // Wraparound cases
      expect(uint16Lt(0xFFFF, 100), isTrue); // 65535 < 100 (wraparound)
      expect(uint16Lt(100, 0xFFFF), isFalse); // 100 > 65535 (wraparound)
    });

    test('should handle empty payload in RTX wrapping', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1234,
        timestamp: 567890,
        ssrc: 0x12345678,
        csrcs: [],
        extensionHeader: null,
        payload: Uint8List(0), // Empty payload
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);

      // Should still have 2-byte OSN
      expect(rtx.payload.length, equals(2));

      final osnView = ByteData.sublistView(rtx.payload);
      expect(osnView.getUint16(0), equals(1234));
    });

    test('should handle large sequence numbers in OSN', () {
      final handler = RtxHandler(
        rtxPayloadType: 96,
        rtxSsrc: 0x87654321,
      );

      final original = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 0xFFFE, // Near max uint16
        timestamp: 567890,
        ssrc: 0x12345678,
        csrcs: [],
        extensionHeader: null,
        payload: Uint8List.fromList([0xDD]),
        paddingLength: 0,
      );

      final rtx = handler.wrapRtx(original);
      final restored = RtxHandler.unwrapRtx(rtx, 111, 0x12345678);

      expect(restored.sequenceNumber, equals(0xFFFE));
    });
  });
}
