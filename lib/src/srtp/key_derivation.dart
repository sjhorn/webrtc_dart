import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// SRTP Key Derivation
/// RFC 3711 Section 4.3 - Key Derivation
///
/// SRTP uses a Key Derivation Function (KDF) to derive session keys
/// from the master key and salt.
///
/// The KDF uses AES in Counter Mode to generate key material.
class SrtpKeyDerivation {
  /// Key derivation labels (RFC 3711 Section 4.3.1)
  static const int labelSrtpEncryption = 0x00;
  static const int labelSrtpAuthentication = 0x01;
  static const int labelSrtpSalt = 0x02;
  static const int labelSrtcpEncryption = 0x03;
  static const int labelSrtcpAuthentication = 0x04;
  static const int labelSrtcpSalt = 0x05;

  /// Derive session key
  /// RFC 3711 Section 4.3.1
  ///
  /// key_id = <label> || r
  /// x = key_id XOR master_salt
  /// session_key = AES(master_key, x)
  static Uint8List deriveKey({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int label,
    required int indexOverKdr,
    required int keyLength,
  }) {
    // Build key_id: label (8 bits) || index/key_derivation_rate (48 bits) || 0x00 (padding to 128 bits)
    final keyId = Uint8List(16);

    // Label at byte 7
    keyId[7] = label & 0xFF;

    // Index/KDR at bytes 8-13 (48 bits)
    keyId[8] = (indexOverKdr >> 40) & 0xFF;
    keyId[9] = (indexOverKdr >> 32) & 0xFF;
    keyId[10] = (indexOverKdr >> 24) & 0xFF;
    keyId[11] = (indexOverKdr >> 16) & 0xFF;
    keyId[12] = (indexOverKdr >> 8) & 0xFF;
    keyId[13] = indexOverKdr & 0xFF;

    // XOR with master_salt (first 14 bytes, as salt is 112 bits)
    for (var i = 0; i < masterSalt.length && i < 14; i++) {
      keyId[i] ^= masterSalt[i];
    }

    // Encrypt key_id with master_key using AES-CTR to generate session key
    final cipher = SICStreamCipher(AESEngine());
    cipher.init(
      true,
      ParametersWithIV(
        KeyParameter(masterKey),
        Uint8List(16), // Zero IV for key derivation
      ),
    );

    // Generate enough key material
    final numBlocks = (keyLength + 15) ~/ 16;
    final keyMaterial = Uint8List(numBlocks * 16);

    var offset = 0;
    for (var i = 0; i < numBlocks; i++) {
      // For each block, encrypt keyId with counter
      final block = Uint8List.fromList(keyId);

      // Increment counter in keyId (last 32 bits)
      final counter = ByteData.sublistView(block, 12, 16);
      counter.setUint32(0, i);

      cipher.processBytes(block, 0, 16, keyMaterial, offset);
      offset += 16;
    }

    // Return only the requested key length
    return keyMaterial.sublist(0, keyLength);
  }

  /// Derive all session keys for SRTP
  static SrtpSessionKeys deriveSrtpKeys({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int ssrc,
    required int index,
    int keyDerivationRate = 0, // 0 means derive once
  }) {
    // Calculate index/key_derivation_rate
    final indexOverKdr = keyDerivationRate == 0 ? 0 : index ~/ keyDerivationRate;

    // Derive encryption key (same size as master key)
    final encryptionKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpEncryption,
      indexOverKdr: indexOverKdr,
      keyLength: masterKey.length,
    );

    // Derive authentication key (160 bits for HMAC-SHA1)
    final authenticationKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpAuthentication,
      indexOverKdr: indexOverKdr,
      keyLength: 20, // 160 bits
    );

    // Derive salting key (112 bits, padded to 14 bytes)
    final saltingKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpSalt,
      indexOverKdr: indexOverKdr,
      keyLength: 14, // 112 bits
    );

    return SrtpSessionKeys(
      encryptionKey: encryptionKey,
      authenticationKey: authenticationKey,
      saltingKey: saltingKey,
    );
  }

  /// Derive all session keys for SRTCP
  static SrtpSessionKeys deriveSrtcpKeys({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int ssrc,
    required int index,
  }) {
    // SRTCP always uses index 0 for key derivation
    const indexOverKdr = 0;

    // Derive encryption key
    final encryptionKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpEncryption,
      indexOverKdr: indexOverKdr,
      keyLength: masterKey.length,
    );

    // Derive authentication key
    final authenticationKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpAuthentication,
      indexOverKdr: indexOverKdr,
      keyLength: 20,
    );

    // Derive salting key
    final saltingKey = deriveKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpSalt,
      indexOverKdr: indexOverKdr,
      keyLength: 14,
    );

    return SrtpSessionKeys(
      encryptionKey: encryptionKey,
      authenticationKey: authenticationKey,
      saltingKey: saltingKey,
    );
  }
}

/// SRTP/SRTCP Session Keys
class SrtpSessionKeys {
  /// Session encryption key
  final Uint8List encryptionKey;

  /// Session authentication key (for HMAC)
  final Uint8List authenticationKey;

  /// Session salting key
  final Uint8List saltingKey;

  const SrtpSessionKeys({
    required this.encryptionKey,
    required this.authenticationKey,
    required this.saltingKey,
  });

  @override
  String toString() {
    return 'SrtpSessionKeys(encKey=${encryptionKey.length}B, authKey=${authenticationKey.length}B, salt=${saltingKey.length}B)';
  }
}
