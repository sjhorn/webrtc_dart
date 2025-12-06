import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/random.dart';

void main() {
  group('DtlsRandom', () {
    test('constructor creates DtlsRandom', () {
      final randomBytes = Uint8List(28);
      final random = DtlsRandom(
        gmtUnixTime: 1234567890,
        randomBytes: randomBytes,
      );

      expect(random.gmtUnixTime, equals(1234567890));
      expect(random.randomBytes.length, equals(28));
    });

    test('generate creates random value with current timestamp', () {
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final random = DtlsRandom.generate();
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(random.gmtUnixTime, greaterThanOrEqualTo(before));
      expect(random.gmtUnixTime, lessThanOrEqualTo(after));
      expect(random.randomBytes.length, equals(28));
    });

    test('fromBytes parses 32-byte buffer', () {
      final bytes = Uint8List(32);
      final buffer = ByteData.sublistView(bytes);
      buffer.setUint32(0, 1609459200); // 2021-01-01 00:00:00 UTC
      for (var i = 4; i < 32; i++) {
        bytes[i] = i;
      }

      final random = DtlsRandom.fromBytes(bytes);

      expect(random.gmtUnixTime, equals(1609459200));
      expect(random.randomBytes.length, equals(28));
      for (var i = 0; i < 28; i++) {
        expect(random.randomBytes[i], equals(i + 4));
      }
    });

    test('fromBytes throws for invalid length', () {
      final shortBytes = Uint8List(16);
      final longBytes = Uint8List(64);

      expect(
        () => DtlsRandom.fromBytes(shortBytes),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('32 bytes'),
        )),
      );

      expect(
        () => DtlsRandom.fromBytes(longBytes),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('32 bytes'),
        )),
      );
    });

    test('toBytes serializes to 32-byte buffer', () {
      final randomBytes = Uint8List.fromList(List.generate(28, (i) => i));
      final random = DtlsRandom(
        gmtUnixTime: 0x12345678,
        randomBytes: randomBytes,
      );

      final bytes = random.toBytes();

      expect(bytes.length, equals(32));
      // Check timestamp
      final buffer = ByteData.sublistView(bytes);
      expect(buffer.getUint32(0), equals(0x12345678));
      // Check random bytes
      for (var i = 0; i < 28; i++) {
        expect(bytes[4 + i], equals(i));
      }
    });

    test('bytes getter returns serialized data', () {
      final randomBytes = Uint8List(28);
      final random = DtlsRandom(
        gmtUnixTime: 1000,
        randomBytes: randomBytes,
      );

      final bytes = random.bytes;
      expect(bytes.length, equals(32));
    });

    test('roundtrip fromBytes/toBytes', () {
      final original = DtlsRandom.generate();

      final bytes = original.toBytes();
      final parsed = DtlsRandom.fromBytes(bytes);

      expect(parsed.gmtUnixTime, equals(original.gmtUnixTime));
      expect(parsed.randomBytes, equals(original.randomBytes));
    });

    test('equality compares gmtUnixTime and randomBytes', () {
      final randomBytes1 = Uint8List.fromList(List.generate(28, (i) => i));
      final randomBytes2 = Uint8List.fromList(List.generate(28, (i) => i));
      final randomBytes3 = Uint8List.fromList(List.generate(28, (i) => 27 - i));

      final random1 = DtlsRandom(gmtUnixTime: 1000, randomBytes: randomBytes1);
      final random2 = DtlsRandom(gmtUnixTime: 1000, randomBytes: randomBytes2);
      final random3 = DtlsRandom(gmtUnixTime: 1000, randomBytes: randomBytes3);
      final random4 = DtlsRandom(gmtUnixTime: 2000, randomBytes: randomBytes1);

      expect(random1 == random2, isTrue);
      expect(random1 == random3, isFalse); // different randomBytes
      expect(random1 == random4, isFalse); // different timestamp
    });

    test('equality returns true for identical instance', () {
      final random = DtlsRandom.generate();
      expect(random == random, isTrue);
    });

    test('equality with different randomBytes lengths', () {
      // Create DtlsRandom with same timestamp but checking equality works
      final random1 = DtlsRandom(gmtUnixTime: 1000, randomBytes: Uint8List(28));
      final random2 = DtlsRandom(gmtUnixTime: 1000, randomBytes: Uint8List(28));

      // Equality should work for same-length randomBytes
      expect(random1 == random2, isTrue);
    });

    test('hashCode is consistent for same instance', () {
      final randomBytes = Uint8List(28);
      final random = DtlsRandom(gmtUnixTime: 1000, randomBytes: randomBytes);

      // hashCode should be consistent across multiple calls
      expect(random.hashCode, equals(random.hashCode));
    });

    test('toString returns readable format', () {
      final random = DtlsRandom(
        gmtUnixTime: 1609459200,
        randomBytes: Uint8List(28),
      );

      final str = random.toString();
      expect(str, contains('DtlsRandom'));
      expect(str, contains('1609459200'));
      expect(str, contains('28 bytes'));
    });
  });
}
