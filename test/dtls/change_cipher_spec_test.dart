import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/change_cipher_spec.dart';

void main() {
  group('ChangeCipherSpec', () {
    test('typeValue is 1', () {
      expect(ChangeCipherSpec.typeValue, equals(1));
    });

    test('can be constructed', () {
      const ccs = ChangeCipherSpec();
      expect(ccs, isNotNull);
    });

    test('serialize returns single byte with value 1', () {
      const ccs = ChangeCipherSpec();
      final bytes = ccs.serialize();

      expect(bytes.length, equals(1));
      expect(bytes[0], equals(1));
    });

    test('parse accepts valid bytes', () {
      final ccs = ChangeCipherSpec.parse(Uint8List.fromList([1]));

      expect(ccs, isA<ChangeCipherSpec>());
    });

    test('parse throws on empty bytes', () {
      expect(
        () => ChangeCipherSpec.parse(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on invalid value', () {
      expect(
        () => ChangeCipherSpec.parse(Uint8List.fromList([2])),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => ChangeCipherSpec.parse(Uint8List.fromList([0])),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse accepts bytes with extra data after first byte', () {
      // Only first byte is checked
      final ccs = ChangeCipherSpec.parse(Uint8List.fromList([1, 2, 3]));
      expect(ccs, isA<ChangeCipherSpec>());
    });

    test('roundtrip serialize/parse', () {
      const original = ChangeCipherSpec();
      final bytes = original.serialize();
      final parsed = ChangeCipherSpec.parse(bytes);

      expect(parsed, isA<ChangeCipherSpec>());
    });

    test('toString returns readable format', () {
      const ccs = ChangeCipherSpec();
      expect(ccs.toString(), equals('ChangeCipherSpec()'));
    });

    test('equality works correctly', () {
      const ccs1 = ChangeCipherSpec();
      const ccs2 = ChangeCipherSpec();

      expect(ccs1, equals(ccs2));
      expect(ccs1.hashCode, equals(ccs2.hashCode));
    });

    test('hashCode is based on typeValue', () {
      const ccs = ChangeCipherSpec();
      expect(ccs.hashCode, equals(1.hashCode));
    });
  });
}
