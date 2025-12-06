import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/av1.dart';

void main() {
  group('LEB128', () {
    test('decode single byte value', () {
      // Value 10 = 0x0A (no continuation bit)
      final buf = Uint8List.fromList([0x0A]);
      final result = leb128decode(buf);
      expect(result[0], 10); // value
      expect(result[1], 1); // bytes read
    });

    test('decode two byte value', () {
      // Value 300 = 0b100101100 = 0xAC 0x02 in LEB128
      // Low byte: 0101100 | 0x80 = 0xAC
      // High byte: 0000010 = 0x02
      final buf = Uint8List.fromList([0xAC, 0x02]);
      final result = leb128decode(buf);
      expect(result[0], 300); // value
      expect(result[1], 2); // bytes read
    });

    test('decode zero', () {
      final buf = Uint8List.fromList([0x00]);
      final result = leb128decode(buf);
      expect(result[0], 0);
      expect(result[1], 1);
    });

    test('decode 127 (max single byte)', () {
      final buf = Uint8List.fromList([0x7F]);
      final result = leb128decode(buf);
      expect(result[0], 127);
      expect(result[1], 1);
    });

    test('decode 128 (requires two bytes)', () {
      // 128 = 0x80 0x01 in LEB128
      final buf = Uint8List.fromList([0x80, 0x01]);
      final result = leb128decode(buf);
      expect(result[0], 128);
      expect(result[1], 2);
    });

    test('encode single byte value', () {
      final result = leb128encode(10);
      expect(result, equals(Uint8List.fromList([0x0A])));
    });

    test('encode two byte value', () {
      final result = leb128encode(300);
      expect(result, equals(Uint8List.fromList([0xAC, 0x02])));
    });

    test('encode zero', () {
      final result = leb128encode(0);
      expect(result, equals(Uint8List.fromList([0x00])));
    });

    test('encode 127', () {
      final result = leb128encode(127);
      expect(result, equals(Uint8List.fromList([0x7F])));
    });

    test('encode 128', () {
      final result = leb128encode(128);
      expect(result, equals(Uint8List.fromList([0x80, 0x01])));
    });

    test('round-trip encode/decode', () {
      for (final value in [0, 1, 127, 128, 255, 300, 16383, 16384, 100000]) {
        final encoded = leb128encode(value);
        final decoded = leb128decode(encoded);
        expect(decoded[0], value, reason: 'Failed for value $value');
      }
    });
  });

  group('Av1Obu', () {
    test('deserialize sequence header OBU', () {
      // OBU header bit layout (MSB first): F | TYPE(4) | X | S | R
      // type=1 (sequence header), F=0, X=0, S=0, R=0
      // Binary: 0 0001 0 0 0 = 0b00001000 = 0x08
      final buf = Uint8List.fromList([0x08, 0x11, 0x22, 0x33]);
      final obu = Av1Obu.deserialize(buf);

      expect(obu.obuForbiddenBit, 0);
      expect(obu.obuType, 'OBU_SEQUENCE_HEADER');
      expect(obu.obuExtensionFlag, 0);
      expect(obu.obuHasSizeField, 0);
      expect(obu.payload, equals(Uint8List.fromList([0x11, 0x22, 0x33])));
    });

    test('deserialize frame OBU', () {
      // type=6 (frame): 0 0110 0 0 0 = 0b00110000 = 0x30
      final buf = Uint8List.fromList([0x30, 0xAA, 0xBB]);
      final obu = Av1Obu.deserialize(buf);

      expect(obu.obuType, 'OBU_FRAME');
      expect(obu.payload, equals(Uint8List.fromList([0xAA, 0xBB])));
    });

    test('deserialize OBU with size field flag', () {
      // type=1, has_size=1: 0 0001 0 1 0 = 0b00001010 = 0x0A
      final buf = Uint8List.fromList([0x0A, 0x03, 0x11, 0x22, 0x33]);
      final obu = Av1Obu.deserialize(buf);

      expect(obu.obuHasSizeField, 1);
      // Note: TypeScript doesn't parse size field, just includes it in payload
      expect(obu.payload.length, 4); // size byte + 3 data bytes
    });

    test('deserialize empty buffer', () {
      final obu = Av1Obu.deserialize(Uint8List(0));
      expect(obu.payload, isEmpty);
    });

    test('serialize OBU without size field', () {
      final obu = Av1Obu();
      obu.obuType = 'OBU_FRAME';
      obu.obuHasSizeField = 0;
      obu.payload = Uint8List.fromList([0xAA, 0xBB]);

      final serialized = obu.serialize();
      // type=6 at bits 1-4 in MSB-first: 0 0110 0 0 0 = 0x30
      expect(serialized[0], 0x30);
      expect(serialized.sublist(1), equals(Uint8List.fromList([0xAA, 0xBB])));
    });

    test('serialize OBU with size field', () {
      final obu = Av1Obu();
      obu.obuType = 'OBU_FRAME';
      obu.obuHasSizeField = 1;
      obu.payload = Uint8List.fromList([0xAA, 0xBB]);

      final serialized = obu.serialize();
      // type=6 + has_size at bit 6: 0 0110 0 1 0 = 0x32
      expect(serialized[0], 0x32);
      expect(serialized[1], 2); // LEB128 size = 2
      expect(serialized.sublist(2), equals(Uint8List.fromList([0xAA, 0xBB])));
    });

    test('round-trip serialize/deserialize', () {
      final original = Av1Obu();
      original.obuType = 'OBU_SEQUENCE_HEADER';
      original.obuHasSizeField = 0;
      original.payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      final serialized = original.serialize();
      final restored = Av1Obu.deserialize(serialized);

      expect(restored.obuType, original.obuType);
      expect(restored.obuHasSizeField, original.obuHasSizeField);
      expect(restored.payload, equals(original.payload));
    });
  });

  group('Av1RtpPayload', () {
    test('deserialize single OBU packet (W=1)', () {
      // Aggregation header bit layout (MSB first, getBit starts from bit 0 = MSB):
      // Bit 0=Z, Bit 1=Y, Bits 2-3=W, Bit 4=N, Bits 5-7=reserved
      // Binary view: ZYWNNNRR where R=reserved
      // W=1 (binary 01) in bits 2-3 -> byte = 0b00010000 = 0x10
      final header = 0x10; // W=1
      final obuData =
          Uint8List.fromList([0x02, 0x11, 0x22]); // sequence header OBU
      final buf = Uint8List.fromList([header, ...obuData]);

      final payload = Av1RtpPayload.deserialize(buf);

      expect(payload.zBit, 0);
      expect(payload.yBit, 0);
      expect(payload.wField, 1);
      expect(payload.nBit, 0);
      expect(payload.obuOrFragment.length, 1);
      expect(payload.obuOrFragment[0].data, equals(obuData));
      expect(payload.obuOrFragment[0].isFragment, false);
    });

    test('deserialize keyframe packet (N=1)', () {
      // W=1: bits 2-3 = 01 -> 0x10
      // N=1: bit 4 = 1 -> 0x08
      final header = 0x10 | 0x08; // W=1, N=1 = 0x18
      final obuData = Uint8List.fromList([0x02, 0x11]);
      final buf = Uint8List.fromList([header, ...obuData]);

      final payload = Av1RtpPayload.deserialize(buf);

      expect(payload.nBit, 1);
      expect(payload.isKeyframe, true);
    });

    test('deserialize fragment start packet (Y=1)', () {
      // W=1: 0x10, Y=1: bit 1 = 1 -> 0x40
      final header = 0x10 | 0x40; // W=1, Y=1 = 0x50
      final obuData = Uint8List.fromList([0x02, 0x11, 0x22]);
      final buf = Uint8List.fromList([header, ...obuData]);

      final payload = Av1RtpPayload.deserialize(buf);

      expect(payload.yBit, 1);
      expect(payload.obuOrFragment[0].isFragment, true);
    });

    test('deserialize fragment continuation packet (Z=1)', () {
      // W=1: 0x10, Z=1: bit 0 = 1 -> 0x80
      final header = 0x10 | 0x80; // W=1, Z=1 = 0x90
      final fragmentData = Uint8List.fromList([0x33, 0x44, 0x55]);
      final buf = Uint8List.fromList([header, ...fragmentData]);

      final payload = Av1RtpPayload.deserialize(buf);

      expect(payload.zBit, 1);
      expect(payload.obuOrFragment[0].isFragment, true);
    });

    test('throws on invalid N=1 and Z=1', () {
      // W=1: 0x10, N=1: 0x08, Z=1: 0x80
      final header = 0x10 | 0x08 | 0x80; // W=1, N=1, Z=1 = 0x98
      final buf = Uint8List.fromList([header, 0x02, 0x11]);

      expect(
        () => Av1RtpPayload.deserialize(buf),
        throwsFormatException,
      );
    });

    test('deserialize multiple OBU packet (W=2)', () {
      // W=2: bits 2-3 = 10 -> 0x20
      final header = 0x20; // W=2
      // First OBU: size=3 (LEB128), then 3 bytes
      // Second OBU: remaining bytes
      final buf = Uint8List.fromList([
        header,
        0x03, // LEB128 size = 3
        0x02, 0x11, 0x22, // First OBU (3 bytes)
        0x0C, 0xAA, 0xBB, // Second OBU (remaining)
      ]);

      final payload = Av1RtpPayload.deserialize(buf);

      expect(payload.wField, 2);
      expect(payload.obuOrFragment.length, 2);
      expect(payload.obuOrFragment[0].data,
          equals(Uint8List.fromList([0x02, 0x11, 0x22])));
      expect(payload.obuOrFragment[1].data,
          equals(Uint8List.fromList([0x0C, 0xAA, 0xBB])));
    });

    test('deserialize empty buffer', () {
      final payload = Av1RtpPayload.deserialize(Uint8List(0));
      expect(payload.obuOrFragment, isEmpty);
    });

    test('isDetectedFinalPacketInSequence returns RTP marker', () {
      expect(Av1RtpPayload.isDetectedFinalPacketInSequence(true), true);
      expect(Av1RtpPayload.isDetectedFinalPacketInSequence(false), false);
    });
  });

  group('Av1RtpPayload.getFrame', () {
    test('reassemble single complete OBU', () {
      // Single packet with one complete OBU
      // W=1: bits 2-3 = 01 -> 0x10
      final header = 0x10; // W=1
      // OBU header: type=1 (sequence header): 0 0001 0 0 0 = 0x08
      final obuData = Uint8List.fromList([0x08, 0x11, 0x22, 0x33]);
      final buf = Uint8List.fromList([header, ...obuData]);
      final payload = Av1RtpPayload.deserialize(buf);

      final frame = Av1RtpPayload.getFrame([payload]);

      // Should get the OBU serialized
      expect(frame.isNotEmpty, true);
      expect(frame[0], 0x08); // OBU header preserved
    });

    test('reassemble fragmented OBU across two packets', () {
      // First packet: Y=1 (ends with fragment)
      // W=1: 0x10, Y=1: 0x40
      final header1 = 0x10 | 0x40; // W=1, Y=1
      // Start of OBU with type=1 header (0x08) + payload start
      final fragment1 = Uint8List.fromList([0x08, 0x11]); // Start of OBU
      final buf1 = Uint8List.fromList([header1, ...fragment1]);
      final payload1 = Av1RtpPayload.deserialize(buf1);

      // Second packet: Z=1 (starts with fragment continuation)
      // W=1: 0x10, Z=1: 0x80
      final header2 = 0x10 | 0x80; // W=1, Z=1
      final fragment2 = Uint8List.fromList([0x22, 0x33]); // Rest of OBU
      final buf2 = Uint8List.fromList([header2, ...fragment2]);
      final payload2 = Av1RtpPayload.deserialize(buf2);

      final frame = Av1RtpPayload.getFrame([payload1, payload2]);

      // Should merge fragments
      expect(frame.isNotEmpty, true);
    });

    test('reassemble multiple complete OBUs', () {
      // Packet with two OBUs
      // W=2: bits 2-3 = 10 -> 0x20
      final header = 0x20; // W=2
      final buf = Uint8List.fromList([
        header,
        0x03, // LEB128 size = 3
        0x08, 0x11, 0x22, // First OBU (type=1 header = 0x08)
        0x30, 0xAA, // Second OBU (type=6 header = 0x30)
      ]);
      final payload = Av1RtpPayload.deserialize(buf);

      final frame = Av1RtpPayload.getFrame([payload]);

      expect(frame.isNotEmpty, true);
      // First OBU should have size field added, second should not
    });

    test('handle empty payloads', () {
      final frame = Av1RtpPayload.getFrame([]);
      expect(frame, isEmpty);
    });
  });

  group('OBU Types', () {
    test('all OBU types are mapped', () {
      expect(obuTypes[0], 'Reserved');
      expect(obuTypes[1], 'OBU_SEQUENCE_HEADER');
      expect(obuTypes[2], 'OBU_TEMPORAL_DELIMITER');
      expect(obuTypes[3], 'OBU_FRAME_HEADER');
      expect(obuTypes[4], 'OBU_TILE_GROUP');
      expect(obuTypes[5], 'OBU_METADATA');
      expect(obuTypes[6], 'OBU_FRAME');
      expect(obuTypes[7], 'OBU_REDUNDANT_FRAME_HEADER');
      expect(obuTypes[8], 'OBU_TILE_LIST');
      expect(obuTypes[15], 'OBU_PADDING');
    });

    test('reverse mapping works', () {
      expect(obuTypeIds['OBU_SEQUENCE_HEADER'], 1);
      expect(obuTypeIds['OBU_FRAME'], 6);
      expect(obuTypeIds['OBU_PADDING'], 15);
    });
  });
}
