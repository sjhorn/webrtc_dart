import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/common/binary.dart';

void main() {
  group('Binary Utilities', () {
    test('random16 generates 16-bit value', () {
      final value = random16();
      expect(value, greaterThanOrEqualTo(0));
      expect(value, lessThanOrEqualTo(0xFFFF));
    });

    test('random32 generates 32-bit value', () {
      final value = random32();
      expect(value, greaterThanOrEqualTo(0));
      expect(value, lessThanOrEqualTo(0xFFFFFFFF));
    });

    test('bufferXor XORs two buffers', () {
      final a = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final b = Uint8List.fromList([0x11, 0x22, 0x33, 0x44]);
      final result = bufferXor(a, b);

      expect(result, hasLength(4));
      expect(result[0], equals(0xAA ^ 0x11)); // 0xBB
      expect(result[1], equals(0xBB ^ 0x22)); // 0x99
      expect(result[2], equals(0xCC ^ 0x33)); // 0xFF
      expect(result[3], equals(0xDD ^ 0x44)); // 0x99
    });

    test('bufferXor throws on different lengths', () {
      final a = Uint8List.fromList([0xAA, 0xBB]);
      final b = Uint8List.fromList([0x11, 0x22, 0x33]);

      expect(() => bufferXor(a, b), throwsArgumentError);
    });

    test('bufferArrayXor XORs multiple buffers', () {
      final buffers = [
        Uint8List.fromList([0xAA, 0xBB]),
        Uint8List.fromList([0x11, 0x22]),
        Uint8List.fromList([0x33, 0x44]),
      ];

      final result = bufferArrayXor(buffers);

      expect(result, hasLength(2));
      expect(result[0], equals(0xAA ^ 0x11 ^ 0x33)); // 0x88
      expect(result[1], equals(0xBB ^ 0x22 ^ 0x44)); // 0xDD
    });

    test('bufferArrayXor handles different lengths', () {
      final buffers = [
        Uint8List.fromList([0xAA, 0xBB, 0xCC]),
        Uint8List.fromList([0x11, 0x22]),
        Uint8List.fromList([0x33]),
      ];

      final result = bufferArrayXor(buffers);

      expect(result, hasLength(3));
      expect(result[0], equals(0xAA ^ 0x11 ^ 0x33));
      expect(result[1], equals(0xBB ^ 0x22 ^ 0x00));
      expect(result[2], equals(0xCC ^ 0x00 ^ 0x00));
    });
  });

  group('BitWriter', () {
    test('writes single bit field', () {
      final writer = BitWriter(8);
      writer.set(4, 0, 0x0F);

      final buffer = writer.buffer;
      expect(buffer, hasLength(1));
      expect(buffer[0], equals(0xF0));
    });

    test('writes multiple bit fields', () {
      final writer = BitWriter(16);
      writer.set(4, 0, 0x0A); // 1010 at bits 0-3
      writer.set(8, 4, 0xBC); // 10111100 at bits 4-11
      writer.set(4, 12, 0x0D); // 1101 at bits 12-15

      final buffer = writer.buffer;
      expect(buffer, hasLength(2));
      expect(buffer[0], equals(0xAB));
      expect(buffer[1], equals(0xCD));
    });
  });

  group('BitWriter2', () {
    test('writes bits sequentially', () {
      final writer = BitWriter2(8);
      writer.set(0x0F, 4); // Write 1111
      writer.set(0x00, 4); // Write 0000

      final buffer = writer.buffer;
      expect(buffer, hasLength(1));
      expect(buffer[0], equals(0xF0));
    });

    test('throws on bit length > 32', () {
      expect(() => BitWriter2(33), throwsArgumentError);
    });
  });

  group('getBit', () {
    test('extracts single bit', () {
      expect(getBit(0xAA, 0, 1), equals(1)); // 0xAA = 10101010
      expect(getBit(0xAA, 1, 1), equals(0));
      expect(getBit(0xAA, 2, 1), equals(1));
    });

    test('extracts multiple bits', () {
      expect(getBit(0xAA, 0, 4),
          equals(0x0A)); // 0xAA = 10101010, first 4 bits = 1010
      expect(getBit(0xAA, 4, 4), equals(0x0A)); // last 4 bits = 1010
    });
  });

  group('padding functions', () {
    test('paddingByte pads to 8 bits', () {
      expect(paddingByte(0x0A), equals('00001010')); // 0x0A = 1010
      expect(paddingByte(0xFF), equals('11111111')); // 0xFF = 11111111
    });

    test('paddingBits pads to expected length', () {
      expect(paddingBits(0x0A, 8), equals('00001010'));
      expect(paddingBits(0x0A, 12), equals('000000001010'));
    });
  });

  group('bufferWriter and bufferReader', () {
    test('writes and reads uint8', () {
      final bytes = [1];
      final values = [0xFF];
      final buffer = bufferWriter(bytes, values);

      expect(buffer, hasLength(1));
      expect(buffer[0], equals(0xFF));

      final read = bufferReader(buffer, bytes);
      expect(read, equals(values));
    });

    test('writes and reads uint16', () {
      final bytes = [2];
      final values = [0x1234];
      final buffer = bufferWriter(bytes, values);

      expect(buffer, hasLength(2));
      expect(buffer[0], equals(0x12));
      expect(buffer[1], equals(0x34));

      final read = bufferReader(buffer, bytes);
      expect(read, equals(values));
    });

    test('writes and reads uint32', () {
      final bytes = [4];
      final values = [0x12345678];
      final buffer = bufferWriter(bytes, values);

      expect(buffer, hasLength(4));
      expect(buffer[0], equals(0x12));
      expect(buffer[1], equals(0x34));
      expect(buffer[2], equals(0x56));
      expect(buffer[3], equals(0x78));

      final read = bufferReader(buffer, bytes);
      expect(read, equals(values));
    });

    test('writes and reads multiple values', () {
      final bytes = [1, 2, 4];
      final values = [0xAA, 0xBBCC, 0x11223344];
      final buffer = bufferWriter(bytes, values);

      expect(buffer, hasLength(7));

      final read = bufferReader(buffer, bytes);
      expect(read, equals(values));
    });

    test('bufferWriterLE writes little-endian', () {
      final bytes = [2, 4];
      final values = [0x1234, 0x56789ABC];
      final buffer = bufferWriterLE(bytes, values);

      expect(buffer, hasLength(6));
      // Little-endian: least significant byte first
      expect(buffer[0], equals(0x34));
      expect(buffer[1], equals(0x12));
      expect(buffer[2], equals(0xBC));
      expect(buffer[3], equals(0x9A));
      expect(buffer[4], equals(0x78));
      expect(buffer[5], equals(0x56));
    });
  });

  group('BufferChain', () {
    test('chains buffer writes', () {
      final chain = BufferChain(4);
      chain.writeInt16BE(0x1234, 0).writeUInt8(0xAB, 2).writeUInt8(0xCD, 3);

      final buffer = chain.buffer;
      expect(buffer, hasLength(4));
      expect(buffer[0], equals(0x12));
      expect(buffer[1], equals(0x34));
      expect(buffer[2], equals(0xAB));
      expect(buffer[3], equals(0xCD));
    });
  });

  group('dumpBuffer', () {
    test('formats buffer as hex string', () {
      final buffer = Uint8List.fromList([0xAB, 0xCD, 0x12, 0x34]);
      final dump = dumpBuffer(buffer);

      expect(dump, equals('0xab,0xcd,0x12,0x34'));
    });
  });

  group('BitStream', () {
    test('writes and reads bits', () {
      final buffer = Uint8List(4);
      final stream = BitStream(buffer);

      stream.writeBits(4, 0x0A); // Write 1010
      stream.writeBits(4, 0x0B); // Write 1011
      stream.writeBits(8, 0xCD); // Write 11001101

      expect(buffer[0], equals(0xAB));
      expect(buffer[1], equals(0xCD));
    });

    test('reads bits back correctly', () {
      final buffer = Uint8List.fromList([0xAB, 0xCD]);
      final stream = BitStream(buffer);

      stream.seekTo(0);
      expect(stream.readBits(4), equals(0x0A));
      expect(stream.readBits(4), equals(0x0B));
      expect(stream.readBits(8), equals(0xCD));
    });

    test('seeks to bit position', () {
      final buffer = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      final stream = BitStream(buffer);

      stream.seekTo(8); // Seek to second byte
      expect(stream.readBits(8), equals(0xCD));
    });
  });
}
