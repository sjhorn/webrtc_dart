import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_key_exchange.dart';

void main() {
  group('ClientKeyExchange', () {
    test('constructor creates instance', () {
      final publicKey = Uint8List.fromList([1, 2, 3, 4, 5]);
      final cke = ClientKeyExchange(publicKey: publicKey);
      expect(cke.publicKey, equals(publicKey));
    });

    test('fromPublicKey factory creates instance', () {
      final publicKey = Uint8List.fromList([10, 20, 30]);
      final cke = ClientKeyExchange.fromPublicKey(publicKey);
      expect(cke.publicKey, equals(publicKey));
    });

    test('serialize produces length-prefixed format', () {
      final publicKey = Uint8List.fromList([1, 2, 3, 4, 5]);
      final cke = ClientKeyExchange(publicKey: publicKey);
      final bytes = cke.serialize();

      expect(bytes.length, equals(6)); // 1 byte length + 5 bytes key
      expect(bytes[0], equals(5)); // Length byte
      expect(bytes.sublist(1), equals(publicKey)); // Key data
    });

    test('parse from valid bytes', () {
      final data =
          Uint8List.fromList([3, 0xAA, 0xBB, 0xCC]); // Length 3, then 3 bytes
      final cke = ClientKeyExchange.parse(data);

      expect(cke.publicKey.length, equals(3));
      expect(cke.publicKey, equals(Uint8List.fromList([0xAA, 0xBB, 0xCC])));
    });

    test('parse throws on empty data', () {
      expect(
        () => ClientKeyExchange.parse(Uint8List(0)),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('too short'),
        )),
      );
    });

    test('parse throws on incomplete public key', () {
      // Says length is 10, but only 3 bytes follow
      final data = Uint8List.fromList([10, 1, 2, 3]);
      expect(
        () => ClientKeyExchange.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Incomplete'),
        )),
      );
    });

    test('roundtrip serialize/parse', () {
      final publicKey = Uint8List.fromList(List.generate(32, (i) => i));
      final original = ClientKeyExchange(publicKey: publicKey);

      final bytes = original.serialize();
      final parsed = ClientKeyExchange.parse(bytes);

      expect(parsed.publicKey, equals(original.publicKey));
    });

    test('toString returns readable format', () {
      final publicKey = Uint8List.fromList([1, 2, 3, 4, 5]);
      final cke = ClientKeyExchange(publicKey: publicKey);
      final str = cke.toString();

      expect(str, contains('ClientKeyExchange'));
      expect(str, contains('5 bytes'));
    });

    test('equality compares public keys', () {
      final key1 = Uint8List.fromList([1, 2, 3]);
      final key2 = Uint8List.fromList([1, 2, 3]);
      final key3 = Uint8List.fromList([4, 5, 6]);
      final key4 = Uint8List.fromList([1, 2]); // Different length

      final cke1 = ClientKeyExchange(publicKey: key1);
      final cke2 = ClientKeyExchange(publicKey: key2);
      final cke3 = ClientKeyExchange(publicKey: key3);
      final cke4 = ClientKeyExchange(publicKey: key4);

      expect(cke1 == cke2, isTrue);
      expect(cke1 == cke3, isFalse);
      expect(cke1 == cke4, isFalse);
    });

    test('equality returns true for identical instance', () {
      final cke = ClientKeyExchange(publicKey: Uint8List.fromList([1, 2, 3]));
      expect(cke == cke, isTrue);
    });

    test('hashCode is consistent', () {
      final cke = ClientKeyExchange(publicKey: Uint8List.fromList([1, 2, 3]));
      expect(cke.hashCode, equals(cke.hashCode));
    });

    test('parse handles zero-length public key', () {
      final data = Uint8List.fromList([0]); // Length 0
      final cke = ClientKeyExchange.parse(data);
      expect(cke.publicKey.length, equals(0));
    });

    test('serialize handles max length public key', () {
      // Max length that fits in 1 byte = 255
      final publicKey = Uint8List(255);
      for (var i = 0; i < 255; i++) {
        publicKey[i] = i & 0xFF;
      }

      final cke = ClientKeyExchange(publicKey: publicKey);
      final bytes = cke.serialize();

      expect(bytes.length, equals(256)); // 1 + 255
      expect(bytes[0], equals(255));
    });
  });
}
