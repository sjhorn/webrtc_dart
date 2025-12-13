import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// SRTP Key Derivation
/// RFC 3711 Section 4.3 - Key Derivation
///
/// SRTP uses a Key Derivation Function (KDF) to derive session keys
/// from the master key and salt.
///
/// This implementation matches werift-webrtc's approach:
/// - XOR labelAndIndexOverKdr with the end of masterSalt
/// - Pad to 16 bytes
/// - Encrypt with AES-ECB
class SrtpKeyDerivation {
  /// Key derivation labels (RFC 3711 Section 4.3.1)
  static const int labelSrtpEncryption = 0x00;
  static const int labelSrtpAuthentication = 0x01;
  static const int labelSrtpSalt = 0x02;
  static const int labelSrtcpEncryption = 0x03;
  static const int labelSrtcpAuthentication = 0x04;
  static const int labelSrtcpSalt = 0x05;

  /// Generate session key (16 bytes)
  /// Matches werift's generateSessionKey
  static Uint8List generateSessionKey({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int label,
  }) {
    // Pad masterSalt to 14 bytes if needed
    final paddedSalt = _padSaltTo14Bytes(masterSalt);

    // Create sessionKey as copy of padded salt
    final sessionKey = Uint8List.fromList(paddedSalt);

    // labelAndIndexOverKdr: [label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    final labelAndIndexOverKdr = Uint8List.fromList([
      label,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

    // XOR from the end: sessionKey[j] ^= labelAndIndexOverKdr[i]
    var i = labelAndIndexOverKdr.length - 1;
    var j = sessionKey.length - 1;
    while (i >= 0) {
      sessionKey[j] = sessionKey[j] ^ labelAndIndexOverKdr[i];
      i--;
      j--;
    }

    // Pad to 16 bytes with [0x00, 0x00]
    final block = Uint8List(16);
    block.setRange(0, 14, sessionKey);
    block[14] = 0x00;
    block[15] = 0x00;

    // Encrypt with AES-ECB
    final aes = AESEngine();
    aes.init(true, KeyParameter(masterKey));
    final output = Uint8List(16);
    aes.processBlock(block, 0, output, 0);

    return output;
  }

  /// Generate session salt (14 bytes)
  /// Matches werift's generateSessionSalt
  static Uint8List generateSessionSalt({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int label,
  }) {
    // Pad masterSalt to 14 bytes if needed
    final paddedSalt = _padSaltTo14Bytes(masterSalt);

    // Create sessionSalt as copy of padded salt
    final sessionSalt = Uint8List.fromList(paddedSalt);

    // labelAndIndexOverKdr: [label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    final labelAndIndexOverKdr = Uint8List.fromList([
      label,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

    // XOR from the end
    var i = labelAndIndexOverKdr.length - 1;
    var j = sessionSalt.length - 1;
    while (i >= 0) {
      sessionSalt[j] = sessionSalt[j] ^ labelAndIndexOverKdr[i];
      i--;
      j--;
    }

    // Pad to 16 bytes with [0x00, 0x00]
    final block = Uint8List(16);
    block.setRange(0, 14, sessionSalt);
    block[14] = 0x00;
    block[15] = 0x00;

    // Encrypt with AES-ECB
    final aes = AESEngine();
    aes.init(true, KeyParameter(masterKey));
    final output = Uint8List(16);
    aes.processBlock(block, 0, output, 0);

    // Return only first 14 bytes
    return output.sublist(0, 14);
  }

  /// Generate session auth tag (20 bytes)
  /// Matches werift's generateSessionAuthTag
  static Uint8List generateSessionAuthTag({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int label,
  }) {
    // Pad masterSalt to 14 bytes if needed
    final paddedSalt = _padSaltTo14Bytes(masterSalt);

    // Create sessionAuthTag as copy of padded salt
    final sessionAuthTag = Uint8List.fromList(paddedSalt);

    // labelAndIndexOverKdr: [label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    final labelAndIndexOverKdr = Uint8List.fromList([
      label,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

    // XOR from the end
    var i = labelAndIndexOverKdr.length - 1;
    var j = sessionAuthTag.length - 1;
    while (i >= 0) {
      sessionAuthTag[j] = sessionAuthTag[j] ^ labelAndIndexOverKdr[i];
      i--;
      j--;
    }

    // First run: pad with [0x00, 0x00]
    final firstBlock = Uint8List(16);
    firstBlock.setRange(0, 14, sessionAuthTag);
    firstBlock[14] = 0x00;
    firstBlock[15] = 0x00;

    // Second run: pad with [0x00, 0x01]
    final secondBlock = Uint8List(16);
    secondBlock.setRange(0, 14, sessionAuthTag);
    secondBlock[14] = 0x00;
    secondBlock[15] = 0x01;

    // Encrypt both with AES-ECB
    final aes = AESEngine();
    aes.init(true, KeyParameter(masterKey));

    final firstOutput = Uint8List(16);
    aes.processBlock(firstBlock, 0, firstOutput, 0);

    final secondOutput = Uint8List(16);
    aes.processBlock(secondBlock, 0, secondOutput, 0);

    // Concatenate: firstOutput (16 bytes) + secondOutput first 4 bytes = 20 bytes
    final result = Uint8List(20);
    result.setRange(0, 16, firstOutput);
    result.setRange(16, 20, secondOutput);

    return result;
  }

  /// Pad salt to 14 bytes (required for werift compatibility)
  static Uint8List _padSaltTo14Bytes(Uint8List salt) {
    if (salt.length >= 14) {
      return salt.sublist(0, 14);
    }
    final padded = Uint8List(14);
    padded.setRange(0, salt.length, salt);
    return padded;
  }

  /// Legacy method for backwards compatibility
  /// Uses new algorithm internally
  static Uint8List deriveKey({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int label,
    required int indexOverKdr,
    required int keyLength,
  }) {
    // Route to appropriate new method based on label
    if (label == labelSrtpEncryption || label == labelSrtcpEncryption) {
      return generateSessionKey(
        masterKey: masterKey,
        masterSalt: masterSalt,
        label: label,
      );
    } else if (label == labelSrtpSalt || label == labelSrtcpSalt) {
      return generateSessionSalt(
        masterKey: masterKey,
        masterSalt: masterSalt,
        label: label,
      );
    } else {
      return generateSessionAuthTag(
        masterKey: masterKey,
        masterSalt: masterSalt,
        label: label,
      );
    }
  }

  /// Derive all session keys for SRTP
  /// Uses werift-compatible algorithm
  static SrtpSessionKeys deriveSrtpKeys({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int ssrc,
    required int index,
    int keyDerivationRate = 0, // 0 means derive once
  }) {
    // Derive encryption key (label 0)
    final encryptionKey = generateSessionKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpEncryption,
    );

    // Derive authentication key (label 1)
    final authenticationKey = generateSessionAuthTag(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpAuthentication,
    );

    // Derive salting key (label 2)
    final saltingKey = generateSessionSalt(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtpSalt,
    );

    return SrtpSessionKeys(
      encryptionKey: encryptionKey,
      authenticationKey: authenticationKey,
      saltingKey: saltingKey,
    );
  }

  /// Derive all session keys for SRTCP
  /// Uses werift-compatible algorithm
  static SrtpSessionKeys deriveSrtcpKeys({
    required Uint8List masterKey,
    required Uint8List masterSalt,
    required int ssrc,
    required int index,
  }) {
    // Derive encryption key (label 3)
    final encryptionKey = generateSessionKey(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpEncryption,
    );

    // Derive authentication key (label 4)
    final authenticationKey = generateSessionAuthTag(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpAuthentication,
    );

    // Derive salting key (label 5)
    final saltingKey = generateSessionSalt(
      masterKey: masterKey,
      masterSalt: masterSalt,
      label: labelSrtcpSalt,
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
