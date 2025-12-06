import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/ebml/ebml.dart';
import 'package:webrtc_dart/src/container/webm/ebml/id.dart';

void main() {
  group('EBML', () {
    group('numberToByteArray', () {
      test('1 byte numbers', () {
        expect(numberToByteArray(0), equals(Uint8List.fromList([0x00])));
        expect(numberToByteArray(1), equals(Uint8List.fromList([0x01])));
        expect(numberToByteArray(127), equals(Uint8List.fromList([0x7f])));
        expect(numberToByteArray(255), equals(Uint8List.fromList([0xff])));
      });

      test('2 byte numbers', () {
        expect(
            numberToByteArray(256), equals(Uint8List.fromList([0x01, 0x00])));
        expect(numberToByteArray(0x1234),
            equals(Uint8List.fromList([0x12, 0x34])));
        expect(numberToByteArray(0xffff),
            equals(Uint8List.fromList([0xff, 0xff])));
      });

      test('3 byte numbers', () {
        expect(numberToByteArray(0x10000),
            equals(Uint8List.fromList([0x01, 0x00, 0x00])));
        expect(numberToByteArray(0x123456),
            equals(Uint8List.fromList([0x12, 0x34, 0x56])));
      });

      test('4 byte numbers', () {
        expect(numberToByteArray(0x1000000),
            equals(Uint8List.fromList([0x01, 0x00, 0x00, 0x00])));
        expect(numberToByteArray(0x12345678),
            equals(Uint8List.fromList([0x12, 0x34, 0x56, 0x78])));
      });

      test('explicit byte length pads with zeros', () {
        expect(
            numberToByteArray(1, 2), equals(Uint8List.fromList([0x00, 0x01])));
        expect(numberToByteArray(1, 4),
            equals(Uint8List.fromList([0x00, 0x00, 0x00, 0x01])));
      });
    });

    group('getEbmlByteLength', () {
      test('returns correct VINT byte length', () {
        expect(getEbmlByteLength(0), equals(1));
        expect(getEbmlByteLength(0x7e), equals(1)); // Max 1 byte
        expect(getEbmlByteLength(0x7f), equals(2)); // Needs 2 bytes
        expect(getEbmlByteLength(0x3ffe), equals(2)); // Max 2 bytes
        expect(getEbmlByteLength(0x3fff), equals(3)); // Needs 3 bytes
        expect(getEbmlByteLength(0x1ffffe), equals(3)); // Max 3 bytes
        expect(getEbmlByteLength(0x1fffff), equals(4)); // Needs 4 bytes
      });
    });

    group('vintEncode', () {
      test('1 byte encoding', () {
        // For 1 byte, marker is 0x80
        expect(vintEncode(Uint8List.fromList([0x01])),
            equals(Uint8List.fromList([0x81])));
        expect(vintEncode(Uint8List.fromList([0x00])),
            equals(Uint8List.fromList([0x80])));
        expect(vintEncode(Uint8List.fromList([0x7f])),
            equals(Uint8List.fromList([0xff])));
      });

      test('2 byte encoding', () {
        // For 2 bytes, marker is 0x40
        expect(vintEncode(Uint8List.fromList([0x01, 0x00])),
            equals(Uint8List.fromList([0x41, 0x00])));
        expect(vintEncode(Uint8List.fromList([0x3f, 0xff])),
            equals(Uint8List.fromList([0x7f, 0xff])));
      });

      test('3 byte encoding', () {
        // For 3 bytes, marker is 0x20
        expect(vintEncode(Uint8List.fromList([0x01, 0x00, 0x00])),
            equals(Uint8List.fromList([0x21, 0x00, 0x00])));
      });
    });

    group('vintDecode', () {
      test('1 byte decoding', () {
        final result = vintDecode(Uint8List.fromList([0x81]));
        expect(result.value, equals(1));
        expect(result.length, equals(1));
        expect(result.unknown, isFalse);
      });

      test('2 byte decoding', () {
        final result = vintDecode(Uint8List.fromList([0x41, 0x00]));
        expect(result.value, equals(0x100));
        expect(result.length, equals(2));
        expect(result.unknown, isFalse);
      });

      test('unknown size detection', () {
        // 1 byte unknown: 0xFF (all value bits = 1, which is 0x7F)
        final result1 = vintDecode(Uint8List.fromList([0xff]));
        expect(result1.unknown, isTrue);
        expect(result1.value, isNull);

        // 2 byte unknown: 0x7F 0xFF
        final result2 = vintDecode(Uint8List.fromList([0x7f, 0xff]));
        expect(result2.unknown, isTrue);
        expect(result2.value, isNull);
      });

      test('throws on invalid input', () {
        expect(() => vintDecode(Uint8List.fromList([0x00])),
            throwsA(isA<FormatException>()));
      });
    });

    group('EbmlValue', () {
      test('writes bytes to buffer', () {
        final value = EbmlValue(Uint8List.fromList([0x01, 0x02, 0x03]));
        expect(value.countSize(), equals(3));

        final buf = Uint8List(10);
        final pos = value.write(buf, 2);
        expect(pos, equals(5));
        expect(
            buf.sublist(2, 5), equals(Uint8List.fromList([0x01, 0x02, 0x03])));
      });
    });

    group('EbmlElement', () {
      test('creates element with known size', () {
        final element = EbmlElement(
          Uint8List.fromList([0x42, 0x86]), // EBMLVersion ID
          [ebmlNumber(1)],
        );

        // ID (2) + size vint (1) + value (1) = 4 bytes
        expect(element.countSize(), equals(4));
      });

      test('creates element with unknown size', () {
        final element = EbmlElement(
          EbmlId.segment,
          [ebmlNumber(1)],
          isSizeUnknown: true,
        );

        // ID (4) + unknown size (8) + value (1) = 13 bytes
        expect(element.countSize(), equals(13));
      });

      test('nested elements', () {
        final inner = EbmlElement(
          EbmlId.ebmlVersion,
          [ebmlNumber(1)],
        );
        final outer = EbmlElement(
          EbmlId.ebml,
          [inner],
        );

        // Inner: ID(2) + size(1) + value(1) = 4
        // Outer: ID(4) + size(1) + inner(4) = 9
        expect(outer.countSize(), equals(9));
      });
    });

    group('ebmlBuild', () {
      test('builds simple value', () {
        final data = ebmlBuild(ebmlNumber(0x42));
        expect(data, equals(Uint8List.fromList([0x42])));
      });

      test('builds element', () {
        final element = ebmlElement(
          EbmlId.ebmlVersion,
          ebmlNumber(1),
        );
        final data = ebmlBuild(element);

        // ID: 0x42 0x86
        // Size: 0x81 (vint-encoded 1)
        // Value: 0x01
        expect(data, equals(Uint8List.fromList([0x42, 0x86, 0x81, 0x01])));
      });

      test('builds EBML header', () {
        final header = ebmlElement(EbmlId.ebml, [
          ebmlElement(EbmlId.ebmlVersion, ebmlNumber(1)),
          ebmlElement(EbmlId.ebmlReadVersion, ebmlNumber(1)),
          ebmlElement(EbmlId.ebmlMaxIdLength, ebmlNumber(4)),
          ebmlElement(EbmlId.ebmlMaxSizeLength, ebmlNumber(8)),
          ebmlElement(EbmlId.docType, ebmlString('webm')),
          ebmlElement(EbmlId.docTypeVersion, ebmlNumber(4)),
          ebmlElement(EbmlId.docTypeReadVersion, ebmlNumber(2)),
        ]);

        final data = ebmlBuild(header);

        // Verify it starts with EBML header ID
        expect(data.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));

        // Total size should be reasonable
        expect(data.length, greaterThan(20));
        expect(data.length, lessThan(100));
      });
    });

    group('stringToByteArray', () {
      test('converts ASCII string', () {
        expect(stringToByteArray('webm'),
            equals(Uint8List.fromList([0x77, 0x65, 0x62, 0x6d])));
        expect(stringToByteArray('VP8'),
            equals(Uint8List.fromList([0x56, 0x50, 0x38])));
      });
    });

    group('float32bit', () {
      test('converts floats', () {
        final zero = float32bit(0.0);
        expect(zero.length, equals(4));
        expect(zero, equals(Uint8List.fromList([0x00, 0x00, 0x00, 0x00])));

        final one = float32bit(1.0);
        expect(one.length, equals(4));
        // 1.0 in IEEE 754 single precision = 0x3F800000
        expect(one, equals(Uint8List.fromList([0x3f, 0x80, 0x00, 0x00])));
      });
    });

    group('round-trip', () {
      test('vint encode then decode preserves value', () {
        for (final value in [0, 1, 100, 1000, 10000, 100000]) {
          final encoded =
              vintEncode(numberToByteArray(value, getEbmlByteLength(value)));
          final decoded = vintDecode(encoded);
          expect(decoded.value, equals(value),
              reason: 'Failed for value $value');
          expect(decoded.unknown, isFalse);
        }
      });
    });

    group('EbmlId', () {
      test('EBML header IDs are correct', () {
        expect(
            EbmlId.ebml, equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
        expect(EbmlId.segment,
            equals(Uint8List.fromList([0x18, 0x53, 0x80, 0x67])));
        expect(EbmlId.cluster,
            equals(Uint8List.fromList([0x1f, 0x43, 0xb6, 0x75])));
        expect(EbmlId.simpleBlock, equals(Uint8List.fromList([0xa3])));
        expect(EbmlId.timecode, equals(Uint8List.fromList([0xe7])));
      });

      test('track element IDs are correct', () {
        expect(EbmlId.tracks,
            equals(Uint8List.fromList([0x16, 0x54, 0xae, 0x6b])));
        expect(EbmlId.trackEntry, equals(Uint8List.fromList([0xae])));
        expect(EbmlId.trackNumber, equals(Uint8List.fromList([0xd7])));
        expect(EbmlId.trackType, equals(Uint8List.fromList([0x83])));
        expect(EbmlId.codecId, equals(Uint8List.fromList([0x86])));
      });

      test('audio element IDs are correct', () {
        expect(EbmlId.audio, equals(Uint8List.fromList([0xe1])));
        expect(EbmlId.samplingFrequency, equals(Uint8List.fromList([0xb5])));
        expect(EbmlId.channels, equals(Uint8List.fromList([0x9f])));
      });

      test('video element IDs are correct', () {
        expect(EbmlId.video, equals(Uint8List.fromList([0xe0])));
        expect(EbmlId.pixelWidth, equals(Uint8List.fromList([0xb0])));
        expect(EbmlId.pixelHeight, equals(Uint8List.fromList([0xba])));
      });

      test('cue element IDs are correct', () {
        expect(
            EbmlId.cues, equals(Uint8List.fromList([0x1c, 0x53, 0xbb, 0x6b])));
        expect(EbmlId.cuePoint, equals(Uint8List.fromList([0xbb])));
        expect(EbmlId.cueTime, equals(Uint8List.fromList([0xb3])));
      });
    });
  });
}
