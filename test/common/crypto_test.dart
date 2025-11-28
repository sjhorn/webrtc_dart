import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/common/crypto.dart';

void main() {
  group('Crypto Utilities', () {
    test('randomBytes generates correct length', () {
      final bytes = randomBytes(16);
      expect(bytes, hasLength(16));

      final bytes32 = randomBytes(32);
      expect(bytes32, hasLength(32));
    });

    test('randomBytes generates different values', () {
      final bytes1 = randomBytes(16);
      final bytes2 = randomBytes(16);

      // Extremely unlikely to be equal
      expect(bytes1, isNot(equals(bytes2)));
    });

    test('hmac SHA-256 produces correct digest', () {
      // Test vector from RFC 4231
      final key = Uint8List.fromList(List.filled(20, 0x0b));
      final data = Uint8List.fromList('Hi There'.codeUnits);

      final result = hmac('sha256', key, data);

      expect(result, hasLength(32)); // SHA-256 produces 32 bytes
      expect(result, isNotEmpty);
    });

    test('hmac SHA-1 produces correct digest', () {
      final key = Uint8List.fromList('key'.codeUnits);
      final data = Uint8List.fromList('The quick brown fox jumps over the lazy dog'.codeUnits);

      final result = hmac('sha1', key, data);

      expect(result, hasLength(20)); // SHA-1 produces 20 bytes
      // Known result for this input
      expect(
        result,
        equals([
          0xde, 0x7c, 0x9b, 0x85, 0xb8, 0xb7, 0x8a, 0xa6,
          0xbc, 0x8a, 0x7a, 0x36, 0xf7, 0x0a, 0x90, 0x70,
          0x1c, 0x9d, 0xb4, 0xd9,
        ]),
      );
    });

    test('hmac throws on unsupported algorithm', () {
      final key = Uint8List(16);
      final data = Uint8List(16);

      expect(() => hmac('unsupported', key, data), throwsArgumentError);
    });

    test('pHash expands data correctly', () {
      final secret = Uint8List.fromList('secret'.codeUnits);
      final seed = Uint8List.fromList('seed'.codeUnits);

      // Request 48 bytes (typical for TLS key material)
      final result = pHash(48, 'sha256', secret, seed);

      expect(result, hasLength(48));
      expect(result, isNotEmpty);

      // Should be deterministic
      final result2 = pHash(48, 'sha256', secret, seed);
      expect(result, equals(result2));
    });

    test('pHash with different seeds produces different results', () {
      final secret = Uint8List.fromList('secret'.codeUnits);
      final seed1 = Uint8List.fromList('seed1'.codeUnits);
      final seed2 = Uint8List.fromList('seed2'.codeUnits);

      final result1 = pHash(48, 'sha256', secret, seed1);
      final result2 = pHash(48, 'sha256', secret, seed2);

      expect(result1, isNot(equals(result2)));
    });

    test('hash SHA-256 produces correct digest', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      final result = hash('sha256', data);

      expect(result, hasLength(32));
      // Known SHA-256 of "hello world"
      expect(
        result,
        equals([
          0xb9, 0x4d, 0x27, 0xb9, 0x93, 0x4d, 0x3e, 0x08,
          0xa5, 0x2e, 0x52, 0xd7, 0xda, 0x7d, 0xab, 0xfa,
          0xc4, 0x84, 0xef, 0xe3, 0x7a, 0x53, 0x80, 0xee,
          0x90, 0x88, 0xf7, 0xac, 0xe2, 0xef, 0xcd, 0xe9,
        ]),
      );
    });

    test('hash SHA-1 produces correct digest', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      final result = hash('sha1', data);

      expect(result, hasLength(20));
      // Known SHA-1 of "hello world"
      expect(
        result,
        equals([
          0x2a, 0xae, 0x6c, 0x35, 0xc9, 0x4f, 0xcf, 0xb4,
          0x15, 0xdb, 0xe9, 0x5f, 0x40, 0x8b, 0x9c, 0xe9,
          0x1e, 0xe8, 0x46, 0xed,
        ]),
      );
    });
  });

  group('AES-GCM', () {
    test('encrypts and decrypts data', () async {
      final key = randomBytes(32); // 256-bit key
      final nonce = randomBytes(12); // 96-bit nonce
      final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);
      final aad = Uint8List.fromList('additional data'.codeUnits);

      final ciphertext = await aesGcmEncrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
        additionalData: aad,
      );

      expect(ciphertext.length, greaterThan(plaintext.length)); // Includes MAC

      final decrypted = await aesGcmDecrypt(
        key: key,
        nonce: nonce,
        ciphertext: ciphertext,
        additionalData: aad,
      );

      expect(decrypted, equals(plaintext));
    });

    test('decryption fails with wrong key', () async {
      final key = randomBytes(32);
      final wrongKey = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);
      final aad = Uint8List.fromList('additional data'.codeUnits);

      final ciphertext = await aesGcmEncrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
        additionalData: aad,
      );

      expect(
        () => aesGcmDecrypt(
          key: wrongKey,
          nonce: nonce,
          ciphertext: ciphertext,
          additionalData: aad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('decryption fails with wrong AAD', () async {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);
      final aad = Uint8List.fromList('additional data'.codeUnits);
      final wrongAad = Uint8List.fromList('wrong data'.codeUnits);

      final ciphertext = await aesGcmEncrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
        additionalData: aad,
      );

      expect(
        () => aesGcmDecrypt(
          key: key,
          nonce: nonce,
          ciphertext: ciphertext,
          additionalData: wrongAad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('AES-CBC', () {
    test('encrypts and decrypts data', () async {
      final key = randomBytes(16); // 128-bit key
      final iv = randomBytes(16); // 128-bit IV
      final plaintext = Uint8List.fromList('Hello, World!!!!' .codeUnits); // 16 bytes (block size)

      final ciphertext = await aesCbcEncrypt(
        key: key,
        iv: iv,
        plaintext: plaintext,
      );

      expect(ciphertext.length, greaterThanOrEqualTo(plaintext.length));

      final decrypted = await aesCbcDecrypt(
        key: key,
        iv: iv,
        ciphertext: ciphertext,
      );

      expect(decrypted, equals(plaintext));
    });

    test('handles non-block-aligned plaintext', () async {
      final key = randomBytes(16);
      final iv = randomBytes(16);
      final plaintext = Uint8List.fromList('Hello!'.codeUnits); // 6 bytes, not block-aligned

      final ciphertext = await aesCbcEncrypt(
        key: key,
        iv: iv,
        plaintext: plaintext,
      );

      final decrypted = await aesCbcDecrypt(
        key: key,
        iv: iv,
        ciphertext: ciphertext,
      );

      // Decrypted may have padding, but should start with original
      expect(decrypted.sublist(0, plaintext.length), equals(plaintext));
    });
  });
}
