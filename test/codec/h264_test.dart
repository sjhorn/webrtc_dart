import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/h264.dart';

void main() {
  group('H.264 RTP Payload Depacketization', () {
    test('should parse Single NAL Unit packet (type 1-23)', () {
      // NAL Unit Type 1 (non-IDR slice)
      // F:0 NRI:2 Type:1 = 0b01000001 = 0x41
      final packet = Uint8List.fromList([
        0x41, // F:0 NRI:2 Type:1
        0xAA, 0xBB, 0xCC, 0xDD, // NAL payload
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.f, equals(0));
      expect(h264.nri, equals(2));
      expect(h264.nalUnitType, equals(1));
      expect(h264.isKeyframe, isFalse);
      expect(h264.isPartitionHead, isTrue);

      // Should add Annex B start code (0x00 0x00 0x00 0x01)
      expect(h264.payload.length, equals(9)); // 4 + 5
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(4), equals([0x41, 0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('should detect IDR slice (keyframe, type 5)', () {
      // NAL Unit Type 5 (IDR slice = keyframe)
      // F:0 NRI:3 Type:5 = 0b01100101 = 0x65
      final packet = Uint8List.fromList([
        0x65, // F:0 NRI:3 Type:5
        0x88, 0x99, // NAL payload
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.f, equals(0));
      expect(h264.nri, equals(3));
      expect(h264.nalUnitType, equals(5));
      expect(h264.isKeyframe, isTrue);
      expect(h264.isPartitionHead, isTrue);

      // Check Annex B start code + NAL unit
      expect(h264.payload.length, equals(7)); // 4 + 3
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(4), equals([0x65, 0x88, 0x99]));
    });

    test('should parse STAP-A aggregation packet (type 24)', () {
      // STAP-A header: F:0 NRI:2 Type:24 = 0b01011000 = 0x58
      // NAL 1: size=3, data=[0x41, 0xAA, 0xBB]
      // NAL 2: size=2, data=[0x42, 0xCC]
      final packet = Uint8List.fromList([
        0x58, // F:0 NRI:2 Type:24 (STAP-A)
        0x00, 0x03, // NAL 1 size (3 bytes)
        0x41, 0xAA, 0xBB, // NAL 1 data
        0x00, 0x02, // NAL 2 size (2 bytes)
        0x42, 0xCC, // NAL 2 data
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));
      expect(h264.isPartitionHead, isTrue);

      // Should produce 2 NAL units, each with Annex B start code
      // NAL 1: 4 (start code) + 3 (data) = 7
      // NAL 2: 4 (start code) + 2 (data) = 6
      // Total: 13 bytes
      expect(h264.payload.length, equals(13));

      // Check first NAL unit
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(4, 7), equals([0x41, 0xAA, 0xBB]));

      // Check second NAL unit
      expect(h264.payload.sublist(7, 11), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(11, 13), equals([0x42, 0xCC]));
    });

    test('should parse FU-A start fragment (type 28, S=1)', () {
      // FU-A indicator: F:0 NRI:2 Type:28 = 0b01011100 = 0x5C
      // FU header: S:1 E:0 R:0 Type:1 = 0b10000001 = 0x81
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        0x81, // FU header: S:1 E:0 Type:1
        0xAA, 0xBB, // Fragment data
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.fuA));
      expect(h264.s, equals(1)); // Start bit
      expect(h264.e, equals(0)); // End bit
      expect(h264.r, equals(0));
      expect(h264.nalUnitPayloadType, equals(1));
      expect(h264.isPartitionHead, isTrue);

      // Fragment incomplete, should have empty payload
      expect(h264.payload.length, equals(0));

      // Fragment data should be accumulated
      expect(h264.fragment, isNotNull);
      expect(h264.fragment, equals([0xAA, 0xBB]));
    });

    test('should parse FU-A middle fragment (type 28, S=0, E=0)', () {
      // Previous fragment data
      final previousFragment = Uint8List.fromList([0xAA, 0xBB]);

      // FU-A indicator: F:0 NRI:2 Type:28 = 0x5C
      // FU header: S:0 E:0 R:0 Type:1 = 0b00000001 = 0x01
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        0x01, // FU header: S:0 E:0 Type:1
        0xCC, 0xDD, // Fragment data
      ]);

      final h264 = H264RtpPayload.deserialize(packet, previousFragment);

      expect(h264.nalUnitType, equals(NalUnitType.fuA));
      expect(h264.s, equals(0));
      expect(h264.e, equals(0));
      expect(h264.isPartitionHead, isFalse);

      // Fragment incomplete, should have empty payload
      expect(h264.payload.length, equals(0));

      // Fragment data should be accumulated
      expect(h264.fragment, equals([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('should parse FU-A end fragment and reassemble NAL unit (S=0, E=1)', () {
      // Previous fragment data
      final previousFragment = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);

      // FU-A indicator: F:0 NRI:2 Type:28 = 0x5C
      // FU header: S:0 E:1 R:0 Type:1 = 0b01000001 = 0x41
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        0x41, // FU header: S:0 E:1 Type:1
        0xEE, 0xFF, // Final fragment data
      ]);

      final h264 = H264RtpPayload.deserialize(packet, previousFragment);

      expect(h264.nalUnitType, equals(NalUnitType.fuA));
      expect(h264.s, equals(0));
      expect(h264.e, equals(1)); // End bit
      expect(h264.nalUnitPayloadType, equals(1));
      expect(h264.isPartitionHead, isFalse);

      // Fragment complete, should reassemble NAL unit
      // Reconstructed NAL header: F:0 NRI:2 Type:1 = 0x41
      // Complete NAL: [0x41, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
      // With Annex B: [0x00, 0x00, 0x00, 0x01, 0x41, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
      expect(h264.payload.length, equals(11)); // 4 + 7
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload[4], equals(0x41)); // Reconstructed NAL header
      expect(h264.payload.sublist(5), equals([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]));

      // Fragment should be cleared
      expect(h264.fragment, isNull);
    });

    test('should reassemble FU-A fragments for IDR slice (keyframe)', () {
      // FU-A indicator: F:0 NRI:3 Type:28 = 0x7C
      // FU header for IDR slice (Type:5): S:1 E:0 Type:5 = 0x85
      final startPacket = Uint8List.fromList([
        0x7C, // FU-A indicator
        0x85, // FU header: S:1 E:0 Type:5 (IDR)
        0x11, 0x22,
      ]);

      final h264Start = H264RtpPayload.deserialize(startPacket);
      expect(h264Start.s, equals(1));
      expect(h264Start.nalUnitPayloadType, equals(5));

      // End fragment: S:0 E:1 Type:5 = 0x45
      final endPacket = Uint8List.fromList([
        0x7C, // FU-A indicator
        0x45, // FU header: S:0 E:1 Type:5
        0x33, 0x44,
      ]);

      final h264End = H264RtpPayload.deserialize(endPacket, h264Start.fragment);

      expect(h264End.e, equals(1));
      expect(h264End.isKeyframe, isTrue); // Should detect IDR slice
      expect(h264End.nalUnitPayloadType, equals(5));

      // Reconstructed NAL header: F:0 NRI:3 Type:5 = 0x65
      expect(h264End.payload.length, equals(9)); // 4 + 5
      expect(h264End.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264End.payload[4], equals(0x65)); // IDR NAL header
      expect(h264End.payload.sublist(5), equals([0x11, 0x22, 0x33, 0x44]));
    });

    test('should handle empty buffer', () {
      final packet = Uint8List(0);
      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.payload.length, equals(0));
    });

    test('should handle STAP-A with single NAL unit', () {
      // STAP-A header: F:0 NRI:2 Type:24 = 0x58
      final packet = Uint8List.fromList([
        0x58, // STAP-A
        0x00, 0x03, // NAL size (3 bytes)
        0x41, 0xAA, 0xBB, // NAL data
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));
      expect(h264.payload.length, equals(7)); // 4 + 3
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(4), equals([0x41, 0xAA, 0xBB]));
    });

    test('should handle STAP-A with empty payload', () {
      // STAP-A with no NAL units (malformed)
      final packet = Uint8List.fromList([
        0x58, // STAP-A
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));
      expect(h264.payload.length, equals(0));
    });

    test('should handle STAP-A with malformed size', () {
      // STAP-A with NAL size larger than remaining buffer
      final packet = Uint8List.fromList([
        0x58, // STAP-A
        0x00, 0xFF, // NAL size (255 bytes, but buffer only has 2)
        0xAA, 0xBB,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));
      expect(h264.payload.length, equals(0)); // Should handle gracefully
    });

    test('should handle FU-A with truncated header', () {
      // FU-A indicator without FU header
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        // Missing FU header
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.fuA));
      expect(h264.payload.length, equals(0));
    });

    test('should handle unsupported NAL unit types', () {
      // NAL Unit Type 30 (unsupported)
      // F:0 NRI:0 Type:30 = 0b00011110 = 0x1E
      final packet = Uint8List.fromList([
        0x1E, // Unsupported type
        0xAA, 0xBB,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(30));
      expect(h264.payload.length, equals(0)); // Should return empty
    });

    test('should parse NAL header fields correctly', () {
      // Test various combinations of F, NRI, Type
      // F:1 NRI:3 Type:7 = 0b11100111 = 0xE7
      final packet = Uint8List.fromList([
        0xE7, // F:1 NRI:3 Type:7
        0xAA,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.f, equals(1)); // Forbidden bit set (error indicator)
      expect(h264.nri, equals(3)); // Highest priority
      expect(h264.nalUnitType, equals(7)); // SPS (Sequence Parameter Set)
    });

    test('should parse FU-A header fields correctly', () {
      // FU-A with all bits set
      // FU header: S:1 E:1 R:1 Type:31 = 0b11111111 = 0xFF
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        0xFF, // FU header: S:1 E:1 R:1 Type:31
        0xAA,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.s, equals(1));
      expect(h264.e, equals(1));
      expect(h264.r, equals(1));
      expect(h264.nalUnitPayloadType, equals(31));
    });

    test('should handle STAP-A with multiple NAL units of different types', () {
      // STAP-A with SPS (7), PPS (8), and IDR slice (5)
      final packet = Uint8List.fromList([
        0x78, // F:0 NRI:3 Type:24 (STAP-A)
        0x00, 0x02, // NAL 1 size
        0x67, 0x11, // SPS (Type:7)
        0x00, 0x02, // NAL 2 size
        0x68, 0x22, // PPS (Type:8)
        0x00, 0x02, // NAL 3 size
        0x65, 0x33, // IDR slice (Type:5)
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));

      // Total: 3 NAL units × (4 byte start code + 2 byte data) = 18 bytes
      expect(h264.payload.length, equals(18));

      // Verify each NAL unit has Annex B start code
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(6, 10), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload.sublist(12, 16), equals([0x00, 0x00, 0x00, 0x01]));

      // Verify NAL unit data
      expect(h264.payload.sublist(4, 6), equals([0x67, 0x11]));
      expect(h264.payload.sublist(10, 12), equals([0x68, 0x22]));
      expect(h264.payload.sublist(16, 18), equals([0x65, 0x33]));
    });

    test('toString should include relevant fields', () {
      final packet = Uint8List.fromList([
        0x65, // IDR slice
        0xAA, 0xBB,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);
      final str = h264.toString();

      expect(str, contains('H264RtpPayload'));
      expect(str, contains('type=5'));
      expect(str, contains('keyframe=true'));
    });

    test('should handle FU-A with empty fragment data', () {
      // FU-A end fragment with no previous data
      final packet = Uint8List.fromList([
        0x5C, // FU-A indicator
        0x41, // FU header: S:0 E:1 Type:1
        0xAA,
      ]);

      final h264 = H264RtpPayload.deserialize(packet, Uint8List(0));

      expect(h264.e, equals(1));

      // Should still reconstruct NAL unit with just the last fragment
      expect(h264.payload.length, equals(6)); // 4 + 1 + 1
      expect(h264.payload.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(h264.payload[4], equals(0x41)); // Reconstructed NAL header
      expect(h264.payload[5], equals(0xAA));
    });

    test('should verify NRI preservation in FU-A reassembly', () {
      // FU-A indicator with NRI=1: F:0 NRI:1 Type:28 = 0b00111100 = 0x3C
      // FU header: S:0 E:1 Type:5 = 0x45
      final packet = Uint8List.fromList([
        0x3C, // FU-A indicator (NRI:1)
        0x45, // FU header: E:1 Type:5
        0xBB,
      ]);

      final previousFragment = Uint8List.fromList([0xAA]);
      final h264 = H264RtpPayload.deserialize(packet, previousFragment);

      // Reconstructed NAL header should have F:0 NRI:1 Type:5 = 0x25
      expect(h264.payload[4], equals(0x25));
    });

    test('should handle STAP-A with zero-size NAL unit', () {
      // STAP-A with NAL size of 0
      final packet = Uint8List.fromList([
        0x58, // STAP-A
        0x00, 0x00, // NAL size (0 bytes)
        0x00, 0x02, // NAL 2 size
        0x41, 0xAA,
      ]);

      final h264 = H264RtpPayload.deserialize(packet);

      expect(h264.nalUnitType, equals(NalUnitType.stapA));
      // Should still process second NAL unit
      expect(h264.payload.length, greaterThan(0));
    });

    test('should detect partition head for non-FU types', () {
      // Single NAL unit (always partition head)
      var packet = Uint8List.fromList([0x41, 0xAA]);
      var h264 = H264RtpPayload.deserialize(packet);
      expect(h264.isPartitionHead, isTrue);

      // STAP-A (always partition head)
      packet = Uint8List.fromList([0x58, 0x00, 0x02, 0x41, 0xAA]);
      h264 = H264RtpPayload.deserialize(packet);
      expect(h264.isPartitionHead, isTrue);
    });

    test('should detect partition head for FU-A based on S bit', () {
      // FU-A with S=1 (partition head)
      var packet = Uint8List.fromList([0x5C, 0x81, 0xAA]); // S:1
      var h264 = H264RtpPayload.deserialize(packet);
      expect(h264.isPartitionHead, isTrue);

      // FU-A with S=0 (not partition head)
      packet = Uint8List.fromList([0x5C, 0x01, 0xAA]); // S:0
      h264 = H264RtpPayload.deserialize(packet);
      expect(h264.isPartitionHead, isFalse);
    });
  });
}
