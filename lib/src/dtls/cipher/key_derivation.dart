import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';

final _log = WebRtcLogging.dtlsKeys;

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
    _log.fine(
        'Pre-master secret (first 16): ${preMasterSecret.sublist(0, preMasterSecret.length > 16 ? 16 : preMasterSecret.length).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

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
      _log.fine(
          'Extended master secret: hashing ${handshakeMessages.length} bytes');
      _log.fine(
          'First 32 bytes: ${handshakeMessages.sublist(0, handshakeMessages.length > 32 ? 32 : handshakeMessages.length).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      _log.fine(
          'Last 32 bytes: ${handshakeMessages.sublist(handshakeMessages.length > 32 ? handshakeMessages.length - 32 : 0).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
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

    _log.fine('deriveEncryptionKeys: isClient=${cipherContext.isClient}');
    _log.fine(
        'clientRandom (first 8): ${clientRandom.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'serverRandom (first 8): ${serverRandom.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'masterSecret (first 16): ${masterSecret.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    final keys = prfEncryptionKeys(
      masterSecret,
      clientRandom,
      serverRandom,
      keyLen,
      ivLen,
      0, // Nonce length (not used for AEAD)
    );

    _log.fine(
        'clientWriteKey: ${keys.clientWriteKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'serverWriteKey: ${keys.serverWriteKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'clientNonce: ${keys.clientNonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'serverNonce: ${keys.serverNonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    return keys;
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
    _log.fine(
        'Computing verify_data for ${isClient ? "client" : "server"}, buffer has ${dtlsContext.handshakeMessages.length} messages, ${handshakeMessages.length} bytes total');

    // Debug: show ALL bytes of each message in buffer (for smaller messages)
    for (var i = 0; i < dtlsContext.handshakeMessages.length; i++) {
      final msg = dtlsContext.handshakeMessages[i];
      if (msg.length >= 12) {
        final msgType = msg[0];
        final msgLen = (msg[1] << 16) | (msg[2] << 8) | msg[3];
        final msgSeq = (msg[4] << 8) | msg[5];
        final fragOff = (msg[6] << 16) | (msg[7] << 8) | msg[8];
        final fragLen = (msg[9] << 16) | (msg[10] << 8) | msg[11];
        _log.fine(
            '  [$i] type=$msgType len=$msgLen seq=$msgSeq fragOff=$fragOff fragLen=$fragLen totalBytes=${msg.length}');
        // For small messages, show all bytes
        if (msg.length <= 50) {
          _log.fine(
              '      FULL: ${msg.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        } else {
          _log.fine(
              '      first32: ${msg.sublist(0, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
        }
      }
    }

    // Debug: show hash of handshake messages
    final digest = Digest('SHA-256');
    final handshakeHash = digest.process(handshakeMessages);
    _log.fine(
        'handshake_hash FULL: ${handshakeHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _log.fine(
        'masterSecret FULL: ${masterSecret.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // Dump full concatenated buffer
    _log.fine(
        '=== FULL HANDSHAKE BUFFER (${handshakeMessages.length} bytes) ===');
    for (var i = 0; i < handshakeMessages.length; i += 32) {
      final end = (i + 32) < handshakeMessages.length
          ? i + 32
          : handshakeMessages.length;
      _log.fine(
          '${i.toString().padLeft(4, '0')}: ${handshakeMessages.sublist(i, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }

    final verifyData = isClient
        ? prfVerifyDataClient(masterSecret, handshakeMessages)
        : prfVerifyDataServer(masterSecret, handshakeMessages);
    _log.fine(
        'verify_data: ${verifyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    return verifyData;
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

    // Pass localRandom and remoteRandom directly - exportKeyingMaterial
    // handles the client/server swap internally based on isClient flag
    return exportKeyingMaterial(
      'EXTRACTOR-dtls_srtp',
      keyMaterialLength,
      masterSecret,
      dtlsContext.localRandom!,
      dtlsContext.remoteRandom!,
      isClient,
    );
  }
}
