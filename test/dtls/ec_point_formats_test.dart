import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/ec_point_formats.dart';

void main() {
  group('ECPointFormat', () {
    test('values have correct codes', () {
      expect(ECPointFormat.uncompressed.value, equals(0));
      expect(ECPointFormat.ansix962CompressedPrime.value, equals(1));
      expect(ECPointFormat.ansix962CompressedChar2.value, equals(2));
    });

    test('fromValue returns correct format', () {
      expect(ECPointFormat.fromValue(0), equals(ECPointFormat.uncompressed));
      expect(ECPointFormat.fromValue(1),
          equals(ECPointFormat.ansix962CompressedPrime));
      expect(ECPointFormat.fromValue(2),
          equals(ECPointFormat.ansix962CompressedChar2));
    });

    test('fromValue returns null for unknown value', () {
      expect(ECPointFormat.fromValue(99), isNull);
    });
  });

  group('ECPointFormatsExtension', () {
    test('construction with formats', () {
      final ext = ECPointFormatsExtension([
        ECPointFormat.uncompressed,
        ECPointFormat.ansix962CompressedPrime,
      ]);

      expect(ext.formats.length, equals(2));
      expect(ext.formats, contains(ECPointFormat.uncompressed));
      expect(ext.formats, contains(ECPointFormat.ansix962CompressedPrime));
    });

    test('serialize creates valid bytes', () {
      final ext = ECPointFormatsExtension([
        ECPointFormat.uncompressed,
        ECPointFormat.ansix962CompressedPrime,
      ]);

      final bytes = ext.serializeData();

      // 1 byte length + 2 format bytes = 3 bytes
      expect(bytes.length, equals(3));
      expect(bytes[0], equals(2)); // Length of formats list
      expect(bytes[1], equals(0)); // uncompressed
      expect(bytes[2], equals(1)); // compressed prime
    });

    test('serialize single format', () {
      final ext = ECPointFormatsExtension([ECPointFormat.uncompressed]);

      final bytes = ext.serializeData();

      expect(bytes.length, equals(2));
      expect(bytes[0], equals(1)); // Length
      expect(bytes[1], equals(0)); // uncompressed
    });

    test('parse creates valid extension', () {
      final bytes = Uint8List.fromList([
        2, // Length
        0, // uncompressed
        2, // compressed char2
      ]);

      final ext = ECPointFormatsExtension.parse(bytes);

      expect(ext.formats.length, equals(2));
      expect(ext.formats[0], equals(ECPointFormat.uncompressed));
      expect(ext.formats[1], equals(ECPointFormat.ansix962CompressedChar2));
    });

    test('parse skips unknown formats', () {
      final bytes = Uint8List.fromList([
        3, // Length
        0, // uncompressed
        99, // unknown - should be skipped
        1, // compressed prime
      ]);

      final ext = ECPointFormatsExtension.parse(bytes);

      // Only known formats should be parsed
      expect(ext.formats.length, equals(2));
      expect(ext.formats[0], equals(ECPointFormat.uncompressed));
      expect(ext.formats[1], equals(ECPointFormat.ansix962CompressedPrime));
    });

    test('parse throws on empty data', () {
      expect(
        () => ECPointFormatsExtension.parse(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on truncated data', () {
      final bytes = Uint8List.fromList([
        5, // Length says 5 formats
        0, 1, // But only 2 bytes follow
      ]);

      expect(
        () => ECPointFormatsExtension.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('roundtrip serialize/parse', () {
      final original = ECPointFormatsExtension([
        ECPointFormat.uncompressed,
        ECPointFormat.ansix962CompressedPrime,
        ECPointFormat.ansix962CompressedChar2,
      ]);

      final bytes = original.serializeData();
      final parsed = ECPointFormatsExtension.parse(bytes);

      expect(parsed.formats.length, equals(original.formats.length));
      for (var i = 0; i < original.formats.length; i++) {
        expect(parsed.formats[i], equals(original.formats[i]));
      }
    });

    test('toString returns readable format', () {
      final ext = ECPointFormatsExtension([ECPointFormat.uncompressed]);

      final str = ext.toString();
      expect(str, contains('ECPointFormatsExtension'));
      expect(str, contains('uncompressed'));
    });
  });
}
