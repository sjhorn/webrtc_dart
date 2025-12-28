/// Cipher suite constants for DTLS
/// Based on RFC 5246 (TLS 1.2) and RFC 5289 (ECC cipher suites)
library;

import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// Cipher suite identifiers
enum CipherSuite {
  /// TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
  /// RFC 5289
  tlsEcdheEcdsaWithAes128GcmSha256(0xC02B),

  /// TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
  /// RFC 5289
  tlsEcdheEcdsaWithAes256GcmSha384(0xC02C),

  /// TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
  /// RFC 5289
  tlsEcdheRsaWithAes128GcmSha256(0xC02F),

  /// TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
  /// RFC 5289
  tlsEcdheRsaWithAes256GcmSha384(0xC030),

  /// TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
  /// RFC 7905
  tlsEcdheEcdsaWithChacha20Poly1305Sha256(0xCCA9),

  /// TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
  /// RFC 7905
  tlsEcdheRsaWithChacha20Poly1305Sha256(0xCCA8);

  final int value;
  const CipherSuite(this.value);

  static CipherSuite? fromValue(int value) {
    for (final suite in CipherSuite.values) {
      if (suite.value == value) return suite;
    }
    return null;
  }
}

/// All supported cipher suites
final List<CipherSuite> supportedCipherSuites = CipherSuite.values;

/// Named curve algorithms (Elliptic Curves)
/// RFC 8422 (ECC cipher suites for TLS)
enum NamedCurve {
  /// Curve25519
  x25519(29),

  /// secp256r1 (NIST P-256)
  secp256r1(23);

  final int value;
  const NamedCurve(this.value);

  static NamedCurve? fromValue(int value) {
    for (final curve in NamedCurve.values) {
      if (curve.value == value) return curve;
    }
    return null;
  }
}

/// All supported named curves
final List<NamedCurve> supportedNamedCurves = NamedCurve.values;

/// EC curve type
enum CurveType {
  namedCurve(3);

  final int value;
  const CurveType(this.value);

  static CurveType? fromValue(int value) {
    for (final type in CurveType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Certificate types
/// RFC 5246 Section 7.4.4
const List<int> supportedCertificateTypes = [
  1, // RSA sign
  64, // ECDSA sign
];

/// Signature hash pair
class SignatureHash {
  final int hash;
  final int signature;

  const SignatureHash({
    required this.hash,
    required this.signature,
  });

  @override
  bool operator ==(Object other) =>
      other is SignatureHash &&
      hash == other.hash &&
      signature == other.signature;

  @override
  int get hashCode => Object.hash(hash, signature);

  /// Convert to signature scheme
  SignatureScheme? toScheme() {
    // hash=4 (SHA256), signature=1 (RSA) -> 0x0401
    if (hash == 4 && signature == 1) {
      return SignatureScheme.rsaPkcs1Sha256;
    }
    // hash=4 (SHA256), signature=3 (ECDSA) -> 0x0403
    if (hash == 4 && signature == 3) {
      return SignatureScheme.ecdsaSecp256r1Sha256;
    }
    return null;
  }

  static SignatureHash fromScheme(SignatureScheme scheme) {
    switch (scheme) {
      case SignatureScheme.rsaPkcs1Sha256:
        return const SignatureHash(hash: 4, signature: 1);
      case SignatureScheme.ecdsaSecp256r1Sha256:
        return const SignatureHash(hash: 4, signature: 3);
      default:
        throw ArgumentError('Unsupported signature scheme: $scheme');
    }
  }
}

/// Supported signature algorithms
/// Using SHA-256 with RSA and ECDSA
final List<SignatureHash> supportedSignatureAlgorithms = [
  const SignatureHash(hash: 4, signature: 1), // SHA256 + RSA
  const SignatureHash(hash: 4, signature: 3), // SHA256 + ECDSA
];

/// Key exchange algorithm
enum KeyExchangeAlgorithm {
  ecdhe,
  rsa,
}

/// Bulk cipher algorithm
enum BulkCipherAlgorithm {
  aes128Gcm,
  aes256Gcm,
  chacha20Poly1305,
}

/// MAC algorithm
enum MacAlgorithm {
  sha256,
  sha384,
}

/// Get key exchange algorithm for cipher suite
KeyExchangeAlgorithm getKeyExchangeAlgorithm(CipherSuite suite) {
  switch (suite) {
    case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
    case CipherSuite.tlsEcdheEcdsaWithAes256GcmSha384:
    case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
    case CipherSuite.tlsEcdheRsaWithAes256GcmSha384:
    case CipherSuite.tlsEcdheEcdsaWithChacha20Poly1305Sha256:
    case CipherSuite.tlsEcdheRsaWithChacha20Poly1305Sha256:
      return KeyExchangeAlgorithm.ecdhe;
  }
}

/// Get bulk cipher algorithm for cipher suite
BulkCipherAlgorithm getBulkCipherAlgorithm(CipherSuite suite) {
  switch (suite) {
    case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
    case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
      return BulkCipherAlgorithm.aes128Gcm;
    case CipherSuite.tlsEcdheEcdsaWithAes256GcmSha384:
    case CipherSuite.tlsEcdheRsaWithAes256GcmSha384:
      return BulkCipherAlgorithm.aes256Gcm;
    case CipherSuite.tlsEcdheEcdsaWithChacha20Poly1305Sha256:
    case CipherSuite.tlsEcdheRsaWithChacha20Poly1305Sha256:
      return BulkCipherAlgorithm.chacha20Poly1305;
  }
}

/// Get MAC algorithm for cipher suite
MacAlgorithm getMacAlgorithm(CipherSuite suite) {
  switch (suite) {
    case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
    case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
    case CipherSuite.tlsEcdheEcdsaWithChacha20Poly1305Sha256:
    case CipherSuite.tlsEcdheRsaWithChacha20Poly1305Sha256:
      return MacAlgorithm.sha256;
    case CipherSuite.tlsEcdheEcdsaWithAes256GcmSha384:
    case CipherSuite.tlsEcdheRsaWithAes256GcmSha384:
      return MacAlgorithm.sha384;
  }
}

/// Master secret length
const int masterSecretLength = 48;

/// Premaster secret length
const int premasterSecretLength = 48;

/// Verify data length for Finished message
const int verifyDataLength = 12;

/// Random value length
const int randomLength = 32;

/// Session ID maximum length
const int sessionIdMaxLength = 32;
