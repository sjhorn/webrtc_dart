import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Abstract interface for AES-GCM encryption/decryption.
///
/// This abstraction allows switching between pure Dart and native FFI
/// implementations. Use [CryptoConfig] to select the implementation.
abstract class AesGcmCipher {
  /// Encrypt plaintext using AES-GCM.
  ///
  /// Returns ciphertext with 16-byte authentication tag appended.
  Future<Uint8List> encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  });

  /// Decrypt ciphertext using AES-GCM.
  ///
  /// The [ciphertext] must include the 16-byte authentication tag at the end.
  /// Throws if authentication fails.
  Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  });

  /// Release any resources held by this cipher.
  void dispose();
}

/// Pure Dart AES-GCM implementation using package:cryptography.
///
/// This is the default implementation that works on all platforms.
/// For better performance, use [FfiAesGcmCipher] when available.
class DartAesGcmCipher implements AesGcmCipher {
  /// Cached cipher instances (one per key length)
  AesGcm? _cipher128;
  AesGcm? _cipher256;

  /// Get or create cipher for the given key length.
  AesGcm _getCipher(int keyLength) {
    if (keyLength == 16) {
      return _cipher128 ??= AesGcm.with128bits();
    } else if (keyLength == 32) {
      return _cipher256 ??= AesGcm.with256bits();
    } else {
      throw ArgumentError('Invalid AES key length: $keyLength');
    }
  }

  @override
  Future<Uint8List> encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    final cipher = _getCipher(key.length);
    final secretKey = SecretKey(key);

    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    // Concatenate ciphertext and MAC
    final result =
        Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
    result.setAll(0, secretBox.cipherText);
    result.setAll(secretBox.cipherText.length, secretBox.mac.bytes);

    return result;
  }

  @override
  Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List aad,
  }) async {
    const macLength = 16;
    if (ciphertext.length < macLength) {
      throw ArgumentError('Ciphertext too short');
    }

    final cipher = _getCipher(key.length);

    // Split ciphertext and MAC
    final actualCiphertext =
        Uint8List.sublistView(ciphertext, 0, ciphertext.length - macLength);
    final mac =
        Uint8List.sublistView(ciphertext, ciphertext.length - macLength);

    final secretKey = SecretKey(key);
    final secretBox = SecretBox(
      actualCiphertext,
      nonce: nonce,
      mac: Mac(mac),
    );

    final plaintext = await cipher.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: aad,
    );

    return Uint8List.fromList(plaintext);
  }

  @override
  void dispose() {
    // No resources to release for pure Dart implementation
    _cipher128 = null;
    _cipher256 = null;
  }
}
