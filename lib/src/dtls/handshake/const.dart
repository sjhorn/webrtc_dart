/// DTLS handshake constants
/// Based on RFC 6347 (DTLS 1.2) and RFC 5246 (TLS 1.2)

/// Handshake message types
enum HandshakeType {
  helloRequest(0),
  clientHello(1),
  serverHello(2),
  helloVerifyRequest(3),
  certificate(11),
  serverKeyExchange(12),
  certificateRequest(13),
  serverHelloDone(14),
  certificateVerify(15),
  clientKeyExchange(16),
  finished(20);

  final int value;
  const HandshakeType(this.value);

  static HandshakeType? fromValue(int value) {
    for (final type in HandshakeType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Compression methods
enum CompressionMethod {
  none(0);

  final int value;
  const CompressionMethod(this.value);

  static CompressionMethod? fromValue(int value) {
    for (final method in CompressionMethod.values) {
      if (method.value == value) return method;
    }
    return null;
  }
}

/// Extension types
enum ExtensionType {
  serverName(0),
  maxFragmentLength(1),
  clientCertificateUrl(2),
  trustedCaKeys(3),
  truncatedHmac(4),
  statusRequest(5),
  userMapping(6),
  clientAuthz(7),
  serverAuthz(8),
  certType(9),
  ellipticCurves(10), // Renamed from supportedGroups, aka supported_groups
  ecPointFormats(11),
  srp(12),
  signatureAlgorithms(13),
  useSrtp(14),
  heartbeat(15),
  applicationLayerProtocolNegotiation(16),
  statusRequestV2(17),
  signedCertificateTimestamp(18),
  clientCertificateType(19),
  serverCertificateType(20),
  padding(21),
  extendedMasterSecret(23),
  sessionTicket(35),
  renegotiationInfo(65281); // 0xFF01

  final int value;
  const ExtensionType(this.value);

  static ExtensionType? fromValue(int value) {
    for (final type in ExtensionType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Certificate types
enum CertificateType {
  x509(0),
  openPGP(1);

  final int value;
  const CertificateType(this.value);

  static CertificateType? fromValue(int value) {
    for (final type in CertificateType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Hash algorithms for signatures
enum HashAlgorithm {
  none(0),
  md5(1),
  sha1(2),
  sha224(3),
  sha256(4),
  sha384(5),
  sha512(6);

  final int value;
  const HashAlgorithm(this.value);

  static HashAlgorithm? fromValue(int value) {
    for (final algo in HashAlgorithm.values) {
      if (algo.value == value) return algo;
    }
    return null;
  }
}

/// Signature algorithms
enum SignatureAlgorithm {
  anonymous(0),
  rsa(1),
  dsa(2),
  ecdsa(3);

  final int value;
  const SignatureAlgorithm(this.value);

  static SignatureAlgorithm? fromValue(int value) {
    for (final algo in SignatureAlgorithm.values) {
      if (algo.value == value) return algo;
    }
    return null;
  }
}

/// EC point format
enum ECPointFormat {
  uncompressed(0),
  ansix962CompressedPrime(1),
  ansix962CompressedChar2(2);

  final int value;
  const ECPointFormat(this.value);

  static ECPointFormat? fromValue(int value) {
    for (final format in ECPointFormat.values) {
      if (format.value == value) return format;
    }
    return null;
  }
}

/// Handshake message header length (12 bytes for DTLS)
const int dtlsHandshakeHeaderLength = 12;

/// Finished message verify data length
const int dtlsFinishedVerifyDataLength = 12;

/// Alert Level
/// RFC 5246 Section 7.2
enum AlertLevel {
  warning(1),
  fatal(2);

  final int value;
  const AlertLevel(this.value);

  static AlertLevel? fromValue(int value) {
    for (final level in AlertLevel.values) {
      if (level.value == value) return level;
    }
    return null;
  }
}

/// Alert Description
/// RFC 5246 Section 7.2
enum AlertDescription {
  closeNotify(0),
  unexpectedMessage(10),
  badRecordMac(20),
  decryptionFailed(21),
  recordOverflow(22),
  decompressFailed(30),
  handshakeFailure(40),
  noCertificate(41),
  badCertificate(42),
  unsupportedCertificate(43),
  certificateRevoked(44),
  certificateExpired(45),
  certificateUnknown(46),
  illegalParameter(47),
  unknownCa(48),
  accessDenied(49),
  decodeError(50),
  decryptError(51),
  exportRestriction(60),
  protocolVersion(70),
  insufficientSecurity(71),
  internalError(80),
  userCanceled(90),
  noRenegotiation(100),
  unsupportedExtension(110);

  final int value;
  const AlertDescription(this.value);

  static AlertDescription? fromValue(int value) {
    for (final desc in AlertDescription.values) {
      if (desc.value == value) return desc;
    }
    return null;
  }
}

/// Signature Scheme (TLS 1.2+)
/// RFC 8446 Section 4.2.3
enum SignatureScheme {
  // ECDSA algorithms
  ecdsaSecp256r1Sha256(0x0403),
  ecdsaSecp384r1Sha384(0x0503),
  ecdsaSecp521r1Sha512(0x0603),

  // RSA-PSS algorithms
  rsaPssRsaeSha256(0x0804),
  rsaPssRsaeSha384(0x0805),
  rsaPssRsaeSha512(0x0806),

  // Legacy RSA
  rsaPkcs1Sha256(0x0401),
  rsaPkcs1Sha384(0x0501),
  rsaPkcs1Sha512(0x0601);

  final int value;
  const SignatureScheme(this.value);

  static SignatureScheme? fromValue(int value) {
    for (final scheme in SignatureScheme.values) {
      if (scheme.value == value) return scheme;
    }
    return null;
  }
}
