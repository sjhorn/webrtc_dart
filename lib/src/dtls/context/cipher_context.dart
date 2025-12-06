import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/cipher/suites/aead.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// Cipher state for DTLS connection
/// Manages keys, certificates, and cipher suite
class CipherContext {
  /// Selected cipher suite
  CipherSuite? cipherSuite;

  /// Local private key (for ECDH)
  KeyPair? localKeyPair;

  /// Local public key bytes (serialized)
  Uint8List? localPublicKey;

  /// Remote public key bytes (from peer)
  Uint8List? remotePublicKey;

  /// Named curve being used (X25519, P-256, etc.)
  NamedCurve? namedCurve;

  /// Signature algorithm being used
  SignatureScheme? signatureScheme;

  /// Local certificate (X.509 DER encoded)
  Uint8List? localCertificate;

  /// Remote certificate (X.509 DER encoded)
  Uint8List? remoteCertificate;

  /// Local signing private key (for CertificateVerify)
  pc.ECPrivateKey? localSigningKey;

  /// Local certificate fingerprint (for SDP)
  String? localFingerprint;

  /// Remote certificate fingerprint (for SDP)
  String? remoteFingerprint;

  /// Encryption keys derived from master secret
  EncryptionKeys? encryptionKeys;

  /// Cipher suite instance for encryption/decryption
  AEADCipherSuite? localCipher;

  /// Cipher suite instance for remote encryption/decryption
  AEADCipherSuite? remoteCipher;

  /// Whether we are the client
  bool isClient;

  CipherContext({
    this.cipherSuite,
    this.localKeyPair,
    this.localPublicKey,
    this.remotePublicKey,
    this.namedCurve,
    this.signatureScheme,
    this.localCertificate,
    this.remoteCertificate,
    this.localSigningKey,
    this.localFingerprint,
    this.remoteFingerprint,
    this.encryptionKeys,
    this.localCipher,
    this.remoteCipher,
    this.isClient = true,
  });

  /// Initialize cipher suite for encryption/decryption
  void initializeCiphers(EncryptionKeys keys, CipherSuite suite) {
    encryptionKeys = keys;
    cipherSuite = suite;

    // Create cipher instances
    localCipher = AEADCipherSuite.fromKeys(suite, keys, isClient);
    remoteCipher = AEADCipherSuite.fromKeys(suite, keys, !isClient);
  }

  /// Check if cipher is ready for encryption
  bool get canEncrypt => localCipher != null;

  /// Check if cipher is ready for decryption
  bool get canDecrypt => remoteCipher != null;

  /// Check if encryption is ready (alias for canEncrypt)
  bool get isEncryptionReady => canEncrypt;

  /// Check if decryption is ready (alias for canDecrypt)
  bool get isDecryptionReady => canDecrypt;

  /// Get client write cipher
  AEADCipherSuite? get clientWriteCipher =>
      isClient ? localCipher : remoteCipher;

  /// Get server write cipher
  AEADCipherSuite? get serverWriteCipher =>
      isClient ? remoteCipher : localCipher;

  /// Get client write IV (implicit nonce)
  Uint8List? get clientWriteIV => encryptionKeys?.clientNonce;

  /// Get server write IV (implicit nonce)
  Uint8List? get serverWriteIV => encryptionKeys?.serverNonce;

  /// Check if we have a valid key pair
  bool get hasKeyPair => localKeyPair != null;

  /// Check if we have remote public key
  bool get hasRemotePublicKey => remotePublicKey != null;

  /// Reset cipher context
  void reset() {
    cipherSuite = null;
    localKeyPair = null;
    localPublicKey = null;
    remotePublicKey = null;
    namedCurve = null;
    signatureScheme = null;
    localCertificate = null;
    remoteCertificate = null;
    localSigningKey = null;
    localFingerprint = null;
    remoteFingerprint = null;
    encryptionKeys = null;
    localCipher = null;
    remoteCipher = null;
  }

  @override
  String toString() {
    return 'CipherContext(suite=$cipherSuite, curve=$namedCurve, '
        'canEncrypt=$canEncrypt, canDecrypt=$canDecrypt)';
  }
}
