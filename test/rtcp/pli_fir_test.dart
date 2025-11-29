import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/psfb/pli.dart';
import 'package:webrtc_dart/src/rtcp/psfb/fir.dart';

void main() {
  group('PictureLossIndication', () {
    group('constants', () {
      test('fmt is 1 (RFC 4585)', () {
        expect(PictureLossIndication.fmt, equals(1));
      });

      test('length is 2 (8 bytes / 4)', () {
        expect(PictureLossIndication.length, equals(2));
      });
    });

    group('serialization', () {
      test('serializes to 8 bytes', () {
        final pli = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        final data = pli.serialize();
        expect(data.length, equals(8));
      });

      test('serializes sender SSRC correctly', () {
        final pli = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        final data = pli.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(0), equals(0x12345678));
      });

      test('serializes media SSRC correctly', () {
        final pli = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        final data = pli.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(4), equals(0xABCDEF00));
      });

      test('serializes maximum SSRC values', () {
        final pli = PictureLossIndication(
          senderSsrc: 0xFFFFFFFF,
          mediaSsrc: 0xFFFFFFFF,
        );

        final data = pli.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(0), equals(0xFFFFFFFF));
        expect(buffer.getUint32(4), equals(0xFFFFFFFF));
      });

      test('serializes zero SSRC values', () {
        final pli = PictureLossIndication(
          senderSsrc: 0,
          mediaSsrc: 0,
        );

        final data = pli.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(0), equals(0));
        expect(buffer.getUint32(4), equals(0));
      });
    });

    group('deserialization', () {
      test('deserializes valid PLI data', () {
        final data = Uint8List(8);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0x12345678);
        buffer.setUint32(4, 0xABCDEF00);

        final pli = PictureLossIndication.deserialize(data);

        expect(pli.senderSsrc, equals(0x12345678));
        expect(pli.mediaSsrc, equals(0xABCDEF00));
      });

      test('deserializes maximum SSRC values', () {
        final data = Uint8List(8);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0xFFFFFFFF);
        buffer.setUint32(4, 0xFFFFFFFF);

        final pli = PictureLossIndication.deserialize(data);

        expect(pli.senderSsrc, equals(0xFFFFFFFF));
        expect(pli.mediaSsrc, equals(0xFFFFFFFF));
      });

      test('throws on data too short', () {
        final data = Uint8List(7); // Need 8 bytes

        expect(
          () => PictureLossIndication.deserialize(data),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts data longer than 8 bytes', () {
        final data = Uint8List(16);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0x11111111);
        buffer.setUint32(4, 0x22222222);

        final pli = PictureLossIndication.deserialize(data);

        expect(pli.senderSsrc, equals(0x11111111));
        expect(pli.mediaSsrc, equals(0x22222222));
      });
    });

    group('round-trip', () {
      test('serialize then deserialize preserves values', () {
        final original = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        final data = original.serialize();
        final restored = PictureLossIndication.deserialize(data);

        expect(restored.senderSsrc, equals(original.senderSsrc));
        expect(restored.mediaSsrc, equals(original.mediaSsrc));
      });

      test('round-trip with boundary values', () {
        final original = PictureLossIndication(
          senderSsrc: 0xFFFFFFFF,
          mediaSsrc: 0x00000001,
        );

        final data = original.serialize();
        final restored = PictureLossIndication.deserialize(data);

        expect(restored, equals(original));
      });
    });

    group('equality', () {
      test('equal PLIs are equal', () {
        final pli1 = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );
        final pli2 = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        expect(pli1, equals(pli2));
        expect(pli1.hashCode, equals(pli2.hashCode));
      });

      test('different sender SSRC means not equal', () {
        final pli1 = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );
        final pli2 = PictureLossIndication(
          senderSsrc: 0x87654321,
          mediaSsrc: 0xABCDEF00,
        );

        expect(pli1, isNot(equals(pli2)));
      });

      test('different media SSRC means not equal', () {
        final pli1 = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );
        final pli2 = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0x00FEDCBA,
        );

        expect(pli1, isNot(equals(pli2)));
      });
    });

    group('toString', () {
      test('includes sender and media SSRC in hex', () {
        final pli = PictureLossIndication(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
        );

        final str = pli.toString();

        expect(str, contains('12345678'));
        expect(str, contains('abcdef00'));
        expect(str, contains('PictureLossIndication'));
      });
    });
  });

  group('FirEntry', () {
    test('stores ssrc and sequence number', () {
      final entry = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);

      expect(entry.ssrc, equals(0x12345678));
      expect(entry.sequenceNumber, equals(42));
    });

    test('sequence number can be 0', () {
      final entry = FirEntry(ssrc: 0x12345678, sequenceNumber: 0);
      expect(entry.sequenceNumber, equals(0));
    });

    test('sequence number can be 255', () {
      final entry = FirEntry(ssrc: 0x12345678, sequenceNumber: 255);
      expect(entry.sequenceNumber, equals(255));
    });

    test('equality works', () {
      final entry1 = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);
      final entry2 = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);

      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
    });

    test('different ssrc means not equal', () {
      final entry1 = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);
      final entry2 = FirEntry(ssrc: 0x87654321, sequenceNumber: 42);

      expect(entry1, isNot(equals(entry2)));
    });

    test('different sequence number means not equal', () {
      final entry1 = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);
      final entry2 = FirEntry(ssrc: 0x12345678, sequenceNumber: 43);

      expect(entry1, isNot(equals(entry2)));
    });

    test('toString includes ssrc and sequence number', () {
      final entry = FirEntry(ssrc: 0x12345678, sequenceNumber: 42);
      final str = entry.toString();

      expect(str, contains('12345678'));
      expect(str, contains('42'));
    });
  });

  group('FullIntraRequest', () {
    group('constants', () {
      test('fmt is 4 (RFC 5104)', () {
        expect(FullIntraRequest.fmt, equals(4));
      });
    });

    group('serialization', () {
      test('serializes empty FIR to 8 bytes', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        final data = fir.serialize();
        expect(data.length, equals(8));
      });

      test('serializes FIR with one entry to 16 bytes', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );

        final data = fir.serialize();
        expect(data.length, equals(16));
      });

      test('serializes FIR with multiple entries', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [
            FirEntry(ssrc: 0x11111111, sequenceNumber: 1),
            FirEntry(ssrc: 0x22222222, sequenceNumber: 2),
            FirEntry(ssrc: 0x33333333, sequenceNumber: 3),
          ],
        );

        final data = fir.serialize();
        expect(data.length, equals(32)); // 8 + 3*8
      });

      test('serializes header correctly', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        final data = fir.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(0), equals(0x12345678));
        expect(buffer.getUint32(4), equals(0xABCDEF00));
      });

      test('serializes entry SSRC correctly', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 42)],
        );

        final data = fir.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint32(8), equals(0x11111111));
      });

      test('serializes entry sequence number correctly', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 42)],
        );

        final data = fir.serialize();
        final buffer = ByteData.view(data.buffer);

        expect(buffer.getUint8(12), equals(42));
      });

      test('reserved bytes are zero', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 42)],
        );

        final data = fir.serialize();
        final buffer = ByteData.view(data.buffer);

        // Reserved bytes at offset 13, 14, 15
        expect(buffer.getUint8(13), equals(0));
        expect(buffer.getUint8(14), equals(0));
        expect(buffer.getUint8(15), equals(0));
      });
    });

    group('deserialization', () {
      test('deserializes empty FIR', () {
        final data = Uint8List(8);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0x12345678);
        buffer.setUint32(4, 0xABCDEF00);

        final fir = FullIntraRequest.deserialize(data);

        expect(fir.senderSsrc, equals(0x12345678));
        expect(fir.mediaSsrc, equals(0xABCDEF00));
        expect(fir.entries, isEmpty);
      });

      test('deserializes FIR with one entry', () {
        final data = Uint8List(16);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0x12345678);
        buffer.setUint32(4, 0xABCDEF00);
        buffer.setUint32(8, 0x11111111);
        buffer.setUint8(12, 42);

        final fir = FullIntraRequest.deserialize(data);

        expect(fir.entries.length, equals(1));
        expect(fir.entries[0].ssrc, equals(0x11111111));
        expect(fir.entries[0].sequenceNumber, equals(42));
      });

      test('deserializes FIR with multiple entries', () {
        final data = Uint8List(24);
        final buffer = ByteData.view(data.buffer);
        buffer.setUint32(0, 0x12345678);
        buffer.setUint32(4, 0xABCDEF00);
        // Entry 1
        buffer.setUint32(8, 0x11111111);
        buffer.setUint8(12, 1);
        // Entry 2
        buffer.setUint32(16, 0x22222222);
        buffer.setUint8(20, 2);

        final fir = FullIntraRequest.deserialize(data);

        expect(fir.entries.length, equals(2));
        expect(fir.entries[0].ssrc, equals(0x11111111));
        expect(fir.entries[0].sequenceNumber, equals(1));
        expect(fir.entries[1].ssrc, equals(0x22222222));
        expect(fir.entries[1].sequenceNumber, equals(2));
      });

      test('throws on data too short', () {
        final data = Uint8List(7);

        expect(
          () => FullIntraRequest.deserialize(data),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid entry alignment', () {
        final data = Uint8List(12); // 8 + 4, not 8-byte aligned entries

        expect(
          () => FullIntraRequest.deserialize(data),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('round-trip', () {
      test('serialize then deserialize preserves empty FIR', () {
        final original = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        final data = original.serialize();
        final restored = FullIntraRequest.deserialize(data);

        expect(restored.senderSsrc, equals(original.senderSsrc));
        expect(restored.mediaSsrc, equals(original.mediaSsrc));
        expect(restored.entries, isEmpty);
      });

      test('serialize then deserialize preserves entries', () {
        final original = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [
            FirEntry(ssrc: 0x11111111, sequenceNumber: 1),
            FirEntry(ssrc: 0x22222222, sequenceNumber: 255),
          ],
        );

        final data = original.serialize();
        final restored = FullIntraRequest.deserialize(data);

        expect(restored, equals(original));
      });

      test('round-trip with maximum values', () {
        final original = FullIntraRequest(
          senderSsrc: 0xFFFFFFFF,
          mediaSsrc: 0xFFFFFFFF,
          entries: [
            FirEntry(ssrc: 0xFFFFFFFF, sequenceNumber: 255),
          ],
        );

        final data = original.serialize();
        final restored = FullIntraRequest.deserialize(data);

        expect(restored, equals(original));
      });
    });

    group('length calculation', () {
      test('length for empty FIR is 1', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        // 8 bytes / 4 - 1 = 1
        expect(fir.length, equals(1));
      });

      test('length for FIR with one entry is 3', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );

        // 16 bytes / 4 - 1 = 3
        expect(fir.length, equals(3));
      });

      test('length for FIR with three entries is 7', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [
            FirEntry(ssrc: 0x11111111, sequenceNumber: 1),
            FirEntry(ssrc: 0x22222222, sequenceNumber: 2),
            FirEntry(ssrc: 0x33333333, sequenceNumber: 3),
          ],
        );

        // 32 bytes / 4 - 1 = 7
        expect(fir.length, equals(7));
      });
    });

    group('equality', () {
      test('equal FIRs are equal', () {
        final fir1 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );
        final fir2 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );

        expect(fir1, equals(fir2));
        expect(fir1.hashCode, equals(fir2.hashCode));
      });

      test('different sender SSRC means not equal', () {
        final fir1 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );
        final fir2 = FullIntraRequest(
          senderSsrc: 0x87654321,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        expect(fir1, isNot(equals(fir2)));
      });

      test('different entries means not equal', () {
        final fir1 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );
        final fir2 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 2)],
        );

        expect(fir1, isNot(equals(fir2)));
      });

      test('different number of entries means not equal', () {
        final fir1 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [FirEntry(ssrc: 0x11111111, sequenceNumber: 1)],
        );
        final fir2 = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [],
        );

        expect(fir1, isNot(equals(fir2)));
      });
    });

    group('toString', () {
      test('includes sender SSRC, media SSRC, and entry count', () {
        final fir = FullIntraRequest(
          senderSsrc: 0x12345678,
          mediaSsrc: 0xABCDEF00,
          entries: [
            FirEntry(ssrc: 0x11111111, sequenceNumber: 1),
            FirEntry(ssrc: 0x22222222, sequenceNumber: 2),
          ],
        );

        final str = fir.toString();

        expect(str, contains('12345678'));
        expect(str, contains('abcdef00'));
        expect(str, contains('2')); // entry count
        expect(str, contains('FullIntraRequest'));
      });
    });
  });
}
