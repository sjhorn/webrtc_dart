import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';

/// Key derivation coordinator
/// Handles master secret and encryption key derivation
class KeyDerivation {
  /// Derive master secret from pre-master secret
  static Uint8List deriveMasterSecret(
    DtlsContext dtlsContext,
    CipherContext cipherContext,
    bool useExtendedMasterSecret,
  ) {
    final preMasterSecret = dtlsContext.preMasterSecret;
    if (preMasterSecret == null) {
      throw StateError('Pre-master secret not computed');
    }

    // Determine which random is which based on endpoint role
    // Master secret always uses client_random + server_random (in that order)
    final clientRandom = cipherContext.isClient
        ? dtlsContext.localRandom
        : dtlsContext.remoteRandom;

    final serverRandom = cipherContext.isClient
        ? dtlsContext.remoteRandom
        : dtlsContext.localRandom;

    if (clientRandom == null || serverRandom == null) {
      throw StateError('Random values not exchanged');
    }

    if (useExtendedMasterSecret) {
      // Extended master secret (RFC 7627)
      final handshakeMessages = dtlsContext.getAllHandshakeMessages();
      return prfExtendedMasterSecret(preMasterSecret, handshakeMessages);
    } else {
      // Standard master secret
      return prfMasterSecret(preMasterSecret, clientRandom, serverRandom);
    }
  }

  /// Derive encryption keys from master secret
  static EncryptionKeys deriveEncryptionKeys(
    DtlsContext dtlsContext,
    CipherContext cipherContext,
  ) {
    final masterSecret = dtlsContext.masterSecret;
    if (masterSecret == null) {
      throw StateError('Master secret not derived');
    }

    final cipherSuite = cipherContext.cipherSuite;
    if (cipherSuite == null) {
      throw StateError('Cipher suite not selected');
    }

    // Get key lengths for the cipher suite
    final keyLen = _getKeyLength(cipherSuite);
    final ivLen = _getIvLength(cipherSuite);

    // Client and server randoms (note the order for key expansion)
    final clientRandom = cipherContext.isClient
        ? dtlsContext.localRandom!
        : dtlsContext.remoteRandom!;

    final serverRandom = cipherContext.isClient
        ? dtlsContext.remoteRandom!
        : dtlsContext.localRandom!;

    return prfEncryptionKeys(
      masterSecret,
      clientRandom,
      serverRandom,
      keyLen,
      ivLen,
      0, // Nonce length (not used for AEAD)
    );
  }

  /// Compute verify_data for Finished message
  static Uint8List computeVerifyData(
    DtlsContext dtlsContext,
    bool isClient,
  ) {
    final masterSecret = dtlsContext.masterSecret;
    if (masterSecret == null) {
      throw StateError('Master secret not derived');
    }

    final handshakeMessages = dtlsContext.getAllHandshakeMessages();

    if (isClient) {
      return prfVerifyDataClient(masterSecret, handshakeMessages);
    } else {
      return prfVerifyDataServer(masterSecret, handshakeMessages);
    }
  }

  /// Verify the verify_data in a Finished message
  static bool verifyFinishedMessage(
    DtlsContext dtlsContext,
    Uint8List receivedVerifyData,
    bool isClient,
  ) {
    final expectedVerifyData = computeVerifyData(dtlsContext, isClient);

    if (receivedVerifyData.length != expectedVerifyData.length) {
      return false;
    }

    for (var i = 0; i < expectedVerifyData.length; i++) {
      if (receivedVerifyData[i] != expectedVerifyData[i]) {
        return false;
      }
    }

    return true;
  }

  /// Get key length for cipher suite
  static int _getKeyLength(CipherSuite suite) {
    switch (suite) {
      case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
      case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
        return 16; // AES-128 = 16 bytes
    }
  }

  /// Get IV length for cipher suite (implicit nonce for AEAD)
  static int _getIvLength(CipherSuite suite) {
    switch (suite) {
      case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
      case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
        return 4; // Implicit nonce for GCM = 4 bytes
    }
  }

  /// Export keying material for SRTP (RFC 5764)
  static Uint8List exportSrtpKeys(
    DtlsContext dtlsContext,
    int keyMaterialLength,
    bool isClient,
  ) {
    final masterSecret = dtlsContext.masterSecret;
    if (masterSecret == null) {
      throw StateError('Master secret not derived');
    }

    final clientRandom = isClient
        ? dtlsContext.localRandom!
        : dtlsContext.remoteRandom!;

    final serverRandom = isClient
        ? dtlsContext.remoteRandom!
        : dtlsContext.localRandom!;

    return exportKeyingMaterial(
      'EXTRACTOR-dtls_srtp',
      keyMaterialLength,
      masterSecret,
      clientRandom,
      serverRandom,
      isClient,
    );
  }
}
