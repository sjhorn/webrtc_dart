import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/vp9.dart';

void main() {
  group('VP9 RTP Payload Depacketization', () {
    test('should parse minimal packet (no extensions)', () {
      // I:0 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00001000 = 0x08
      final packet = Uint8List.fromList([0x08, 0xAA, 0xBB, 0xCC]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.iBit, equals(0));
      expect(vp9.pBit, equals(0));
      expect(vp9.lBit, equals(0));
      expect(vp9.fBit, equals(0));
      expect(vp9.bBit, equals(1));
      expect(vp9.eBit, equals(0));
      expect(vp9.vBit, equals(0));
      expect(vp9.zBit, equals(0));
      expect(vp9.pictureId, isNull);
      expect(vp9.payload.length, equals(3));
      expect(vp9.payload, equals([0xAA, 0xBB, 0xCC]));
    });

    test('should parse packet with beginning flag (B=1)', () {
      // I:0 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00001000 = 0x08
      final packet = Uint8List.fromList([0x08, 0xAA, 0xBB]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.bBit, equals(1));
      expect(vp9.isPartitionHead, isTrue);
    });

    test('should parse packet with end flag (E=1)', () {
      // I:0 P:0 L:0 F:0 B:0 E:1 V:0 Z:0
      // Binary: 00000100 = 0x04
      final packet = Uint8List.fromList([0x04, 0xAA, 0xBB]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.eBit, equals(1));
    });

    test('should parse 7-bit Picture ID', () {
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1
        0x7F, // M:0, PictureID:127
        0xAA, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.iBit, equals(1));
      expect(vp9.m, equals(0));
      expect(vp9.pictureId, equals(127));
      expect(vp9.payload, equals([0xAA]));
    });

    test('should parse 15-bit Picture ID', () {
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1
        0xFF, // M:1, PictureID[8-14]:0x7F
        0xFF, // PictureID[0-7]:0xFF
        0xBB, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.m, equals(1));
      expect(vp9.pictureId, equals(0x7FFF)); // 32767
      expect(vp9.payload, equals([0xBB]));
    });

    test('should parse 15-bit Picture ID with value 1234', () {
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1
        0x84, // M:1, bits[8-14]:0x04
        0xD2, // bits[0-7]:0xD2
        0xCC, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.m, equals(1));
      expect(vp9.pictureId, equals(1234));
      expect(vp9.payload, equals([0xCC]));
    });

    test('should detect keyframe (P=0, B=1, L=0)', () {
      // I:0 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00001000 = 0x08
      final packet = Uint8List.fromList([
        0x08, // I:0 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
        0xAA, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pBit, equals(0));
      expect(vp9.bBit, equals(1));
      expect(vp9.lBit, equals(0));
      expect(vp9.isKeyframe, isTrue);
    });

    test('should detect interframe (P=1)', () {
      // I:0 P:1 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 01001000 = 0x48
      final packet = Uint8List.fromList([
        0x48, // I:0 P:1 L:0 F:0 B:1 E:0 V:0 Z:0
        0xBB, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pBit, equals(1));
      expect(vp9.isKeyframe, isFalse);
    });

    test('should parse layer indices with flexible mode (F=1)', () {
      // I:0 P:0 L:1 F:1 B:0 E:0 V:0 Z:0
      // Binary: 00110000 = 0x30
      final packet = Uint8List.fromList([
        0x30, // I:0 P:0 L:1 F:1 B:0 E:0 V:0 Z:0
        0xA5, // TID:5(0b101) U:0 SID:2(0b010) D:1
        0xEE, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.lBit, equals(1));
      expect(vp9.fBit, equals(1));
      expect(vp9.tid, equals(5)); // bits 0-2
      expect(vp9.u, equals(0)); // bit 3
      expect(vp9.sid, equals(2)); // bits 4-6
      expect(vp9.d, equals(1)); // bit 7
      expect(vp9.tl0PicIdx, isNull); // Not present in flexible mode
      expect(vp9.payload, equals([0xEE]));
    });

    test('should parse layer indices with non-flexible mode (F=0)', () {
      // I:0 P:0 L:1 F:0 B:0 E:0 V:0 Z:0
      // Binary: 00100000 = 0x20
      final packet = Uint8List.fromList([
        0x20, // I:0 P:0 L:1 F:0 B:0 E:0 V:0 Z:0
        0xA5, // TID:5 U:0 SID:2 D:1
        0x42, // TL0PICIDX value
        0xFF, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.lBit, equals(1));
      expect(vp9.fBit, equals(0));
      expect(vp9.tid, equals(5));
      expect(vp9.sid, equals(2));
      expect(vp9.tl0PicIdx, equals(0x42));
      expect(vp9.payload, equals([0xFF]));
    });

    test('should parse single reference frame (P_DIFF, N=0)', () {
      // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
      // Binary: 01110000 = 0x70
      final packet = Uint8List.fromList([
        0x70, // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
        0x21, // TID:1 U:0 SID:0 D:1
        0x05, // P_DIFF:5 N:0 (references frame 5 frames back)
        0xDD, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.fBit, equals(1));
      expect(vp9.pBit, equals(1));
      expect(vp9.pDiff.length, equals(1));
      expect(vp9.pDiff[0], equals(5));
      expect(vp9.payload, equals([0xDD]));
    });

    test('should parse multiple reference frames (P_DIFF with N=1)', () {
      // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
      // Binary: 01110000 = 0x70
      final packet = Uint8List.fromList([
        0x70, // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
        0x21, // TID:1 U:0 SID:0 D:1
        0x85, // P_DIFF:5 N:1 (first reference, more to follow)
        0x03, // P_DIFF:3 N:0 (second reference, last one)
        0xCC, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.fBit, equals(1));
      expect(vp9.pBit, equals(1));
      expect(vp9.pDiff.length, equals(2));
      expect(vp9.pDiff[0], equals(5));
      expect(vp9.pDiff[1], equals(3));
      expect(vp9.payload, equals([0xCC]));
    });

    test('should parse scalability structure with resolutions (V=1, Y=1)', () {
      // I:0 P:0 L:0 F:0 B:0 E:0 V:1 Z:0
      // Binary: 00000010 = 0x02
      final packet = Uint8List.fromList([
        0x02, // I:0 P:0 L:0 F:0 B:0 E:0 V:1 Z:0
        0x30, // N_S:1 (2 layers) Y:1 G:0 (bits 7-5=001, bit 4=1, bit 3=0)
        // Layer 0 resolution
        0x05, 0x00, // width: 1280 (5 * 256)
        0x02, 0xD0, // height: 720 (2 * 256 + 208)
        // Layer 1 resolution
        0x0A, 0x00, // width: 2560 (10 * 256)
        0x05, 0xA0, // height: 1440 (5 * 256 + 160)
        0xBB, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.vBit, equals(1));
      expect(vp9.nS, equals(1)); // 2 layers (N_S + 1)
      expect(vp9.y, equals(1));
      expect(vp9.g, equals(0));
      expect(vp9.width.length, equals(2));
      expect(vp9.height.length, equals(2));
      expect(vp9.width[0], equals(1280));
      expect(vp9.height[0], equals(720));
      expect(vp9.width[1], equals(2560));
      expect(vp9.height[1], equals(1440));
    });

    test('should parse scalability structure with picture groups (G=1)', () {
      // I:0 P:0 L:0 F:0 B:0 E:0 V:1 Z:0
      // Binary: 00000010 = 0x02
      final packet = Uint8List.fromList([
        0x02, // V:1
        0x28, // N_S:1 (2 layers) Y:0 G:1 (bits 7-5=001, bit 4=0, bit 3=1)
        0x02, // N_G:2 (2 picture groups)
        // PG 0
        0x4C, // T:2 U:0 R:3 (bits 7-5=010, bit 4=0, bits 3-2=11)
        0x03, // P_DIFF[0]:3
        0x02, // P_DIFF[1]:2
        0x01, // P_DIFF[2]:1
        // PG 1
        0x24, // T:1 U:0 R:1 (bits 7-5=001, bit 4=0, bits 3-2=01)
        0x01, // P_DIFF[0]:1
        0xAA, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.vBit, equals(1));
      expect(vp9.g, equals(1));
      expect(vp9.nG, equals(2));
      expect(vp9.pgT.length, equals(2));
      expect(vp9.pgU.length, equals(2));
      expect(vp9.pgPDiff.length, equals(2));

      // Picture group 0
      expect(vp9.pgT[0], equals(2));
      expect(vp9.pgU[0], equals(0));
      expect(vp9.pgPDiff[0].length, equals(3));
      expect(vp9.pgPDiff[0], equals([3, 2, 1]));

      // Picture group 1
      expect(vp9.pgT[1], equals(1));
      expect(vp9.pgU[1], equals(0));
      expect(vp9.pgPDiff[1].length, equals(1));
      expect(vp9.pgPDiff[1], equals([1]));
    });

    test('should parse complex packet with all extensions', () {
      // I:1 P:0 L:1 F:0 B:1 E:0 V:0 Z:1
      // Binary: 10101001 = 0xA9
      final packet = Uint8List.fromList([
        0xA9, // I:1 P:0 L:1 F:0 B:1 E:0 V:0 Z:1
        0x7F, // M:0, PictureID:127
        0x21, // TID:1 U:0 SID:0 D:1
        0x10, // TL0PICIDX
        0xAA, 0xBB, 0xCC, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.iBit, equals(1));
      expect(vp9.pBit, equals(0));
      expect(vp9.lBit, equals(1));
      expect(vp9.fBit, equals(0));
      expect(vp9.bBit, equals(1));
      expect(vp9.zBit, equals(1));
      expect(vp9.pictureId, equals(127));
      expect(vp9.tid, equals(1));
      expect(vp9.sid, equals(0));
      expect(vp9.tl0PicIdx, equals(0x10));
      expect(vp9.payload.length, equals(3));
    });

    test('should handle empty buffer', () {
      final packet = Uint8List(0);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.payload.length, equals(0));
    });

    test('should handle truncated packets gracefully', () {
      // Packet claims to have Picture ID but buffer is too short
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1 (claims Picture ID present)
        // Missing Picture ID bytes
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.payload.length, equals(0)); // Returns empty payload
    });

    test('should parse Picture ID at boundary (7-bit: 0)', () {
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1
        0x00, // M:0, PictureID:0
        0xFF,
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pictureId, equals(0));
    });

    test('should parse Picture ID at boundary (15-bit: 0)', () {
      // I:1 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 10000000 = 0x80
      final packet = Uint8List.fromList([
        0x80, // I:1
        0x80, // M:1, PictureID[8-14]:0
        0x00, // PictureID[0-7]:0
        0xFF,
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pictureId, equals(0));
    });

    test('should detect keyframe with spatial layer 0 (P=0, B=1, SID=0)', () {
      // I:0 P:0 L:1 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00101000 = 0x28
      final packet = Uint8List.fromList([
        0x28, // I:0 P:0 L:1 F:0 B:1 E:0 V:0 Z:0
        0x01, // TID:0 U:0 SID:0 D:1
        0xAA,
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pBit, equals(0));
      expect(vp9.bBit, equals(1));
      expect(vp9.lBit, equals(1));
      expect(vp9.sid, equals(0));
      expect(vp9.isKeyframe, isTrue);
    });

    test('should not be keyframe with spatial layer > 0', () {
      // I:0 P:0 L:1 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00101000 = 0x28
      final packet = Uint8List.fromList([
        0x28, // I:0 P:0 L:1 F:0 B:1 E:0 V:0 Z:0
        0x03, // TID:0 U:0 SID:1 D:1 (bits 7-5=000, bit 4=0, bits 3-1=001, bit 0=1)
        0xAA,
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pBit, equals(0));
      expect(vp9.bBit, equals(1));
      expect(vp9.sid, equals(1));
      expect(vp9.isKeyframe, isFalse);
    });

    test('should correctly identify partition head (B=1)', () {
      // I:0 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 00001000 = 0x08
      var packet = Uint8List.fromList([0x08, 0xAA]); // B:1
      var vp9 = Vp9RtpPayload.deserialize(packet);
      expect(vp9.isPartitionHead, isTrue);

      // I:0 P:0 L:0 F:0 B:0 E:0 V:0 Z:0
      // Binary: 00000000 = 0x00
      packet = Uint8List.fromList([0x00, 0xBB]); // B:0
      vp9 = Vp9RtpPayload.deserialize(packet);
      expect(vp9.isPartitionHead, isFalse);
    });

    test('toString should include relevant fields', () {
      // I:1 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
      // Binary: 10001000 = 0x88
      final packet = Uint8List.fromList([
        0x88, // I:1 P:0 L:0 F:0 B:1 E:0 V:0 Z:0
        0x42, // PictureID:66
        0xAA,
        0xBB,
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);
      final str = vp9.toString();

      expect(str, contains('keyframe'));
      expect(str, contains('partitionHead'));
      expect(str, contains('pictureId'));
    });

    test('should parse maximum P_DIFF reference count', () {
      // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
      // Binary: 01110000 = 0x70
      final packet = Uint8List.fromList([
        0x70, // I:0 P:1 L:1 F:1 B:0 E:0 V:0 Z:0
        0x21, // TID:1 U:0 SID:0 D:1
        0x87, // P_DIFF:7 N:1 (first reference)
        0x85, // P_DIFF:5 N:1 (second reference)
        0x03, // P_DIFF:3 N:0 (third reference, last)
        0xEE, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.pDiff.length, equals(3));
      expect(vp9.pDiff[0], equals(7));
      expect(vp9.pDiff[1], equals(5));
      expect(vp9.pDiff[2], equals(3));
    });

    test('should parse scalability structure with maximum layers', () {
      // I:0 P:0 L:0 F:0 B:0 E:0 V:1 Z:0
      // Binary: 00000010 = 0x02
      final packet = Uint8List.fromList([
        0x02, // V:1
        0xF9, // N_S:7 (8 layers) Y:1 G:0
        // 8 layers worth of resolutions (8 * 4 bytes = 32 bytes)
        0x02, 0x80, 0x01, 0x68, // 640x360
        0x05, 0x00, 0x02, 0xD0, // 1280x720
        0x07, 0x80, 0x04, 0x38, // 1920x1080
        0x0A, 0x00, 0x05, 0xA0, // 2560x1440
        0x0F, 0x00, 0x08, 0x70, // 3840x2160
        0x1E, 0x00, 0x10, 0xE0, // 7680x4320
        0x3C, 0x00, 0x21, 0xC0, // 15360x8640
        0x78, 0x00, 0x43, 0x80, // 30720x17280
        0xAA, // payload
      ]);
      final vp9 = Vp9RtpPayload.deserialize(packet);

      expect(vp9.nS, equals(7)); // 8 layers (N_S + 1)
      expect(vp9.width.length, equals(8));
      expect(vp9.height.length, equals(8));
      expect(vp9.width[0], equals(640));
      expect(vp9.height[0], equals(360));
      expect(vp9.width[4], equals(3840));
      expect(vp9.height[4], equals(2160));
    });
  });
}
