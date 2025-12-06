import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';

void main() {
  group('Finished', () {
    test('constructor creates Finished with verifyData', () {
      final verifyData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final finished = Finished(verifyData: verifyData);

      expect(finished.verifyData, equals(verifyData));
    });

    test('create factory validates 12-byte verify data', () {
      final verifyData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final finished = Finished.create(verifyData);

      expect(finished.verifyData, equals(verifyData));
    });

    test('create factory throws for invalid length', () {
      final shortData = Uint8List(10);
      final longData = Uint8List(15);

      expect(
        () => Finished.create(shortData),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must be 12 bytes'),
        )),
      );

      expect(
        () => Finished.create(longData),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must be 12 bytes'),
        )),
      );
    });

    test('serialize returns verify data bytes', () {
      final verifyData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final finished = Finished(verifyData: verifyData);

      final serialized = finished.serialize();
      expect(serialized, equals(verifyData));
    });

    test('parse creates Finished from 12-byte data', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]);
      final finished = Finished.parse(data);

      expect(finished.verifyData, equals(data));
    });

    test('parse throws for invalid length', () {
      final shortData = Uint8List(8);
      final longData = Uint8List(20);

      expect(
        () => Finished.parse(shortData),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('must be 12 bytes'),
        )),
      );

      expect(
        () => Finished.parse(longData),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('must be 12 bytes'),
        )),
      );
    });

    test('roundtrip serialize/parse', () {
      final verifyData = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78]);
      final original = Finished(verifyData: verifyData);

      final serialized = original.serialize();
      final parsed = Finished.parse(serialized);

      expect(parsed.verifyData, equals(original.verifyData));
    });

    test('toString returns readable format', () {
      final verifyData = Uint8List(12);
      final finished = Finished(verifyData: verifyData);

      final str = finished.toString();
      expect(str, contains('Finished'));
      expect(str, contains('12 bytes'));
    });

    test('equality compares verifyData', () {
      final data1 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final data2 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final data3 = Uint8List.fromList([12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);

      final finished1 = Finished(verifyData: data1);
      final finished2 = Finished(verifyData: data2);
      final finished3 = Finished(verifyData: data3);

      expect(finished1 == finished2, isTrue);
      expect(finished1 == finished3, isFalse);
    });

    test('equality returns true for identical instances', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final finished = Finished(verifyData: data);

      expect(finished == finished, isTrue);
    });

    test('equality returns false for different lengths', () {
      final data1 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final data2 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);

      final finished1 = Finished(verifyData: data1);
      final finished2 = Finished(verifyData: data2);

      expect(finished1 == finished2, isFalse);
    });

    test('hashCode is consistent', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final finished1 = Finished(verifyData: data);
      final finished2 = Finished(verifyData: Uint8List.fromList(data));

      expect(finished1.hashCode, equals(finished2.hashCode));
    });
  });
}
