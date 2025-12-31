import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/container/webm/container.dart';

void main() {
  group('WebM Encryption', () {
    group('WebmContainer with encryption', () {
      test('constructor accepts 16-byte encryption key', () {
        final key = randomBytes(16);
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
          encryptionKey: key,
        );

        expect(container.isEncrypted, isTrue);
        expect(container.encryptionKey, equals(key));
      });

      test('constructor rejects non-16-byte encryption key', () {
        expect(
          () => WebmContainer(
            [
              WebmTrack(
                  trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
            ],
            encryptionKey: Uint8List(8), // Too short
          ),
          throwsArgumentError,
        );

        expect(
          () => WebmContainer(
            [
              WebmTrack(
                  trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
            ],
            encryptionKey: Uint8List(32), // Too long
          ),
          throwsArgumentError,
        );
      });

      test('isEncrypted is false without key', () {
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
        );

        expect(container.isEncrypted, isFalse);
      });

      test('createSimpleBlock throws when encrypted', () {
        final key = randomBytes(16);
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
          encryptionKey: key,
        );

        expect(
          () => container.createSimpleBlock(Uint8List(100), true, 1, 0),
          throwsStateError,
        );
      });

      test('createSimpleBlockAsync works without encryption', () async {
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
        );

        final frame = Uint8List.fromList(List.generate(100, (i) => i));
        final block = await container.createSimpleBlockAsync(frame, true, 1, 0);

        expect(block.isNotEmpty, isTrue);
        // Should contain the frame data
        expect(block.length, greaterThan(frame.length));
      });

      test('createSimpleBlockAsync encrypts frame data', () async {
        final key = randomBytes(16);
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
          encryptionKey: key,
        );

        final frame = Uint8List.fromList(List.generate(100, (i) => i));
        final block = await container.createSimpleBlockAsync(frame, true, 1, 0);

        expect(block.isNotEmpty, isTrue);
        // Encrypted block should be larger (signal byte + IV + encrypted data)
        // Original: element ID + size + track + timestamp + flags + frame
        // Encrypted: element ID + size + track + timestamp + flags + signal + IV + encrypted
        expect(
            block.length, greaterThan(frame.length + 9)); // +9 for signal + IV
      });

      test('encrypted blocks have unique IVs', () async {
        final key = randomBytes(16);
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
          encryptionKey: key,
        );

        final frame = Uint8List.fromList([1, 2, 3, 4, 5]);
        final block1 =
            await container.createSimpleBlockAsync(frame, true, 1, 0);
        final block2 =
            await container.createSimpleBlockAsync(frame, true, 1, 10);

        // Blocks should be different due to different IVs
        expect(block1, isNot(equals(block2)));
      });
    });

    group('Segment with encryption metadata', () {
      test('segment includes ContentEncodings for encrypted tracks', () {
        final key = randomBytes(16);
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
          encryptionKey: key,
        );

        final segment = container.createSegment();

        // Check for ContentEncodings element (0x6d80)
        expect(_containsBytes(segment, [0x6d, 0x80]), isTrue);
        // Check for ContentEncryption element (0x5035)
        expect(_containsBytes(segment, [0x50, 0x35]), isTrue);
        // Check for AES algorithm value (5)
        expect(_containsBytes(segment, [0x47, 0xe1]), isTrue);
      });

      test('segment does not include ContentEncodings without encryption', () {
        final container = WebmContainer(
          [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8)
          ],
        );

        final segment = container.createSegment();

        // Should not contain ContentEncodings element (0x6d80)
        expect(_containsBytes(segment, [0x6d, 0x80]), isFalse);
      });
    });

    group('AES-128-CTR encryption', () {
      test('encrypts and decrypts correctly', () async {
        final key = randomBytes(16);
        final iv = randomBytes(16);
        final plaintext = Uint8List.fromList(
          List.generate(256, (i) => i % 256),
        );

        final encrypted = await aesCtrEncrypt(
          key: key,
          iv: iv,
          plaintext: plaintext,
        );

        // Encrypted should be same length as plaintext (stream cipher)
        expect(encrypted.length, equals(plaintext.length));
        // Encrypted should be different from plaintext
        expect(encrypted, isNot(equals(plaintext)));

        final decrypted = await aesCtrDecrypt(
          key: key,
          iv: iv,
          ciphertext: encrypted,
        );

        expect(decrypted, equals(plaintext));
      });

      test('same key/iv produces same ciphertext', () async {
        final key = randomBytes(16);
        final iv = randomBytes(16);
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final encrypted1 =
            await aesCtrEncrypt(key: key, iv: iv, plaintext: plaintext);
        final encrypted2 =
            await aesCtrEncrypt(key: key, iv: iv, plaintext: plaintext);

        expect(encrypted1, equals(encrypted2));
      });

      test('different IVs produce different ciphertext', () async {
        final key = randomBytes(16);
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final encrypted1 = await aesCtrEncrypt(
          key: key,
          iv: randomBytes(16),
          plaintext: plaintext,
        );
        final encrypted2 = await aesCtrEncrypt(
          key: key,
          iv: randomBytes(16),
          plaintext: plaintext,
        );

        expect(encrypted1, isNot(equals(encrypted2)));
      });
    });

    group('ContentEncAlgorithm constants', () {
      test('AES has correct value', () {
        expect(ContentEncAlgorithm.aes, equals(5));
      });
    });

    group('AesCipherMode constants', () {
      test('CTR has correct value', () {
        expect(AesCipherMode.ctr, equals(1));
      });
    });
  });
}

/// Helper to check if a byte sequence exists within data
bool _containsBytes(Uint8List data, List<int> bytes) {
  outer:
  for (var i = 0; i <= data.length - bytes.length; i++) {
    for (var j = 0; j < bytes.length; j++) {
      if (data[i + j] != bytes[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}
