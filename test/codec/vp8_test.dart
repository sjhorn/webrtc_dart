import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/vp8.dart';

void main() {
  group('VP8 RTP Payload Depacketization', () {
    test('should parse minimal packet (no extensions)', () {
      // X:0 N:0 S:0 PID:0 + payload
      final packet = Uint8List.fromList([0x00, 0xAA, 0xBB, 0xCC]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.xBit, equals(0));
      expect(vp8.nBit, equals(0));
      expect(vp8.sBit, equals(0));
      expect(vp8.pid, equals(0));
      expect(vp8.iBit, isNull);
      expect(vp8.pictureId, isNull);
      expect(vp8.payload.length, equals(3));
      expect(vp8.payload, equals([0xAA, 0xBB, 0xCC]));
      expect(vp8.payloadHeaderExist, isFalse);
    });

    test('should parse packet with S=1 and PID=0 (partition head)', () {
      // X:0 N:0 S:1 PID:0
      final packet = Uint8List.fromList([0x10, 0xAA, 0xBB]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.sBit, equals(1));
      expect(vp8.pid, equals(0));
      expect(vp8.isPartitionHead, isTrue);
      expect(vp8.payloadHeaderExist, isTrue);
    });

    test('should parse 7-bit Picture ID', () {
      // X:1 (extensions present)
      // I:1 (PictureID present)
      // M:0, PictureID:127 (max 7-bit)
      final packet = Uint8List.fromList([
        0x80, // X:1 N:0 S:0 PID:0
        0x80, // I:1 L:0 T:0 K:0
        0x7F, // M:0, PictureID:127
        0xAA, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.xBit, equals(1));
      expect(vp8.iBit, equals(1));
      expect(vp8.mBit, equals(0));
      expect(vp8.pictureId, equals(127));
      expect(vp8.payload, equals([0xAA]));
    });

    test('should parse 15-bit Picture ID', () {
      // X:1, I:1
      // M:1, PictureID:0x7FFF (32767, max 15-bit)
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x80, // I:1
        0xFF, // M:1, PictureID[8-14]:0x7F
        0xFF, // PictureID[0-7]:0xFF
        0xBB, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.mBit, equals(1));
      expect(vp8.pictureId, equals(0x7FFF)); // 32767
      expect(vp8.payload, equals([0xBB]));
    });

    test('should parse 15-bit Picture ID with value 1234', () {
      // PictureID = 1234 = 0x04D2 = 0b0000010011010010
      // M:1, bits[8-14]:0x04, bits[0-7]:0xD2
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x80, // I:1
        0x84, // M:1, bits[8-14]:0x04
        0xD2, // bits[0-7]:0xD2
        0xCC, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.mBit, equals(1));
      expect(vp8.pictureId, equals(1234));
      expect(vp8.payload, equals([0xCC]));
    });

    test('should detect keyframe (P=0)', () {
      // S:1, PID:0 (payload header present), P:0 (keyframe)
      final packet = Uint8List.fromList([
        0x10, // X:0 S:1 PID:0
        0x00, // Size0:0 H:0 VER:0 P:0 (keyframe!)
        0x00, // Size1
        0x00, // Size2
        0xAA, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.payloadHeaderExist, isTrue);
      expect(vp8.pBit, equals(0));
      expect(vp8.isKeyframe, isTrue);
      expect(vp8.size0, equals(0));
      expect(vp8.hBit, equals(0));
      expect(vp8.ver, equals(0));
    });

    test('should detect interframe (P=1)', () {
      // S:1, PID:0, P:1 (interframe)
      final packet = Uint8List.fromList([
        0x10, // S:1 PID:0
        0x01, // P:1 (interframe)
        0x00,
        0x00,
        0xBB,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.pBit, equals(1));
      expect(vp8.isKeyframe, isFalse);
    });

    test('should calculate partition size correctly', () {
      // Size = 7 + (8 × 255) + (2048 × 255) = 524,287 bytes (max)
      final packet = Uint8List.fromList([
        0x10, // S:1 PID:0
        0xE1, // Size0:7 (0b111), H:0, VER:0, P:1
        0xFF, // Size1:255
        0xFF, // Size2:255
        0xDD,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.size0, equals(7));
      expect(vp8.size1, equals(255));
      expect(vp8.size2, equals(255));
      expect(vp8.frameSize, equals(7 + (8 * 255) + (2048 * 255)));
      expect(vp8.frameSize, equals(524287));
    });

    test('should parse partition with different PID values', () {
      // Test PID:0
      var packet = Uint8List.fromList([0x10, 0xAA]); // S:1 PID:0
      var vp8 = Vp8RtpPayload.deserialize(packet);
      expect(vp8.pid, equals(0));
      expect(vp8.payloadHeaderExist, isTrue);

      // Test PID:1
      packet = Uint8List.fromList([0x11, 0xBB]); // S:1 PID:1
      vp8 = Vp8RtpPayload.deserialize(packet);
      expect(vp8.pid, equals(1));
      expect(vp8.payloadHeaderExist, isFalse);

      // Test PID:7 (max)
      packet = Uint8List.fromList([0x17, 0xCC]); // S:1 PID:7
      vp8 = Vp8RtpPayload.deserialize(packet);
      expect(vp8.pid, equals(7));
      expect(vp8.payloadHeaderExist, isFalse);
    });

    test('should parse packet with TL0PICIDX (L=1)', () {
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x40, // I:0 L:1 T:0 K:0
        0x42, // TL0PICIDX value
        0xEE, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.lBit, equals(1));
      expect(vp8.payload, equals([0xEE]));
    });

    test('should parse packet with TID (T=1)', () {
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x20, // I:0 L:0 T:1 K:0
        0x55, // TID/Y/KEYIDX value
        0xFF, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.tBit, equals(1));
      expect(vp8.payload, equals([0xFF]));
    });

    test('should parse packet with KEYIDX (K=1)', () {
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x10, // I:0 L:0 T:0 K:1
        0x88, // KEYIDX value
        0x11, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.kBit, equals(1));
      expect(vp8.payload, equals([0x11]));
    });

    test('should parse complex packet with all extensions', () {
      final packet = Uint8List.fromList([
        0x90, // X:1 N:0 S:1 PID:0
        0xF0, // I:1 L:1 T:1 K:1
        0x7F, // M:0, PictureID:127
        0x10, // TL0PICIDX
        0x20, // TID/Y/KEYIDX
        0x00, // VP8 payload header: P:0 (keyframe)
        0x00, 0x00, // Size1, Size2
        0xAA, 0xBB, 0xCC, // payload
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.xBit, equals(1));
      expect(vp8.sBit, equals(1));
      expect(vp8.pid, equals(0));
      expect(vp8.iBit, equals(1));
      expect(vp8.lBit, equals(1));
      expect(vp8.tBit, equals(1));
      expect(vp8.kBit, equals(1));
      expect(vp8.pictureId, equals(127));
      expect(vp8.isKeyframe, isTrue);
      expect(vp8.payload.length, equals(6)); // payload header + data
    });

    test('should handle empty buffer', () {
      final packet = Uint8List(0);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.payload.length, equals(0));
    });

    test('should handle truncated packets gracefully', () {
      // Packet claims to have Picture ID but buffer is too short
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x80, // I:1 (claims Picture ID present)
        // Missing Picture ID bytes
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.payload.length, equals(0)); // Returns empty payload
    });

    test('should parse non-reference frame (N=1)', () {
      final packet = Uint8List.fromList([
        0x20, // X:0 N:1 S:0 PID:0
        0xAA,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.nBit, equals(1));
      expect(vp8.payload, equals([0xAA]));
    });

    test('should parse VP8 payload header fields correctly', () {
      // Test complete payload header parsing
      // Byte format: SIZE0(3) | H(1) | VER(3) | P(1)
      final packet = Uint8List.fromList([
        0x10, // S:1 PID:0
        0xE1, // SIZE0:7, H:0, VER:0, P:1 - binary: 11100001
        0x00, // SIZE1
        0x00, // SIZE2
        0xFF,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.size0, equals(7)); // bits 0-2
      expect(vp8.hBit, equals(0)); // bit 3
      expect(vp8.ver, equals(0)); // bits 4-6
      expect(vp8.pBit, equals(1)); // bit 7
    });

    test('toString should include relevant fields', () {
      final packet = Uint8List.fromList([
        0x90, // X:1 S:1 PID:0
        0x80, // I:1
        0x42, // PictureID:66
        0x00, // VP8 header: P:0 (keyframe)
        0x00,
        0x00,
        0xAA,
        0xBB,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);
      final str = vp8.toString();

      expect(str, contains('keyframe'));
      expect(str, contains('partitionHead'));
      expect(str, contains('pictureId'));
    });

    test('should correctly identify partition head', () {
      // S=1: partition head
      var packet = Uint8List.fromList([0x10, 0xAA]); // S:1
      var vp8 = Vp8RtpPayload.deserialize(packet);
      expect(vp8.isPartitionHead, isTrue);

      // S=0: not partition head (continuation)
      packet = Uint8List.fromList([0x00, 0xBB]); // S:0
      vp8 = Vp8RtpPayload.deserialize(packet);
      expect(vp8.isPartitionHead, isFalse);
    });

    test('should parse Picture ID at boundary (7-bit: 0)', () {
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x80, // I:1
        0x00, // M:0, PictureID:0
        0xFF,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.pictureId, equals(0));
    });

    test('should parse Picture ID at boundary (15-bit: 0)', () {
      final packet = Uint8List.fromList([
        0x80, // X:1
        0x80, // I:1
        0x80, // M:1, PictureID[8-14]:0
        0x00, // PictureID[0-7]:0
        0xFF,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.pictureId, equals(0));
    });

    test('frameSize should return 0 when payload header does not exist', () {
      final packet = Uint8List.fromList([
        0x00, // X:0 S:0 PID:0 (no payload header)
        0xAA,
      ]);
      final vp8 = Vp8RtpPayload.deserialize(packet);

      expect(vp8.payloadHeaderExist, isFalse);
      expect(vp8.frameSize, equals(0));
    });
  });
}
