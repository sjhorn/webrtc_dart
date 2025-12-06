import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';

/// SRTP keying material and configuration
/// RFC 5764 - SRTP Extension for DTLS
class SrtpContext {
  /// Selected SRTP protection profile
  SrtpProtectionProfile? profile;

  /// Local SRTP master key
  Uint8List? localMasterKey;

  /// Local SRTP master salt
  Uint8List? localMasterSalt;

  /// Remote SRTP master key
  Uint8List? remoteMasterKey;

  /// Remote SRTP master salt
  Uint8List? remoteMasterSalt;

  /// Master Key Identifier (optional)
  Uint8List? mki;

  /// Raw keying material (for extraction)
  Uint8List? _keyMaterial;

  SrtpContext({
    this.profile,
    this.localMasterKey,
    this.localMasterSalt,
    this.remoteMasterKey,
    this.remoteMasterSalt,
    this.mki,
  });

  /// Set key material and extract keys
  set keyMaterial(Uint8List material) {
    _keyMaterial = material;
  }

  /// Get key material (returns empty if not set)
  Uint8List get keyMaterial => _keyMaterial ?? Uint8List(0);

  /// Get key material length for the selected profile
  int get keyMaterialLength {
    if (profile == null) return 0;

    switch (profile!) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
        // 16-byte key + 14-byte salt for each side = 60 bytes total
        return 60;
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
        // 16-byte key + 12-byte salt for each side = 56 bytes total
        return 56;
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        // 32-byte key + 12-byte salt for each side = 88 bytes total
        return 88;
    }
  }

  /// Get key length for the selected profile
  int get keyLength {
    if (profile == null) return 0;

    switch (profile!) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
        return 16; // AES-128
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        return 32; // AES-256
    }
  }

  /// Get salt length for the selected profile
  int get saltLength {
    if (profile == null) return 0;

    switch (profile!) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
        return 14; // HMAC-SHA1 uses 14-byte salt
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        return 12; // GCM uses 12-byte salt
    }
  }

  /// Extract SRTP keys from exported keying material
  /// RFC 5764 Section 4.2
  void extractKeys(Uint8List keyingMaterial, bool isClient) {
    if (profile == null) {
      throw StateError('No SRTP profile selected');
    }

    final keyLen = keyLength;
    final saltLen = saltLength;

    if (keyingMaterial.length < keyLen * 2 + saltLen * 2) {
      throw ArgumentError(
          'Insufficient keying material: ${keyingMaterial.length} bytes');
    }

    var offset = 0;

    // Client write key
    final clientKey = keyingMaterial.sublist(offset, offset + keyLen);
    offset += keyLen;

    // Server write key
    final serverKey = keyingMaterial.sublist(offset, offset + keyLen);
    offset += keyLen;

    // Client write salt
    final clientSalt = keyingMaterial.sublist(offset, offset + saltLen);
    offset += saltLen;

    // Server write salt
    final serverSalt = keyingMaterial.sublist(offset, offset + saltLen);

    // Assign based on role
    if (isClient) {
      localMasterKey = clientKey;
      localMasterSalt = clientSalt;
      remoteMasterKey = serverKey;
      remoteMasterSalt = serverSalt;
    } else {
      localMasterKey = serverKey;
      localMasterSalt = serverSalt;
      remoteMasterKey = clientKey;
      remoteMasterSalt = clientSalt;
    }
  }

  /// Check if SRTP keys are available
  bool get hasKeys =>
      localMasterKey != null &&
      localMasterSalt != null &&
      remoteMasterKey != null &&
      remoteMasterSalt != null;

  /// Reset SRTP context
  void reset() {
    profile = null;
    localMasterKey = null;
    localMasterSalt = null;
    remoteMasterKey = null;
    remoteMasterSalt = null;
    mki = null;
  }

  @override
  String toString() {
    return 'SrtpContext(profile=$profile, hasKeys=$hasKeys)';
  }
}
