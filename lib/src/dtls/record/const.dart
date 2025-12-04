/// DTLS record layer constants
/// Based on RFC 6347 (DTLS 1.2)
library;

/// Content type for DTLS records
enum ContentType {
  changeCipherSpec(20),
  alert(21),
  handshake(22),
  applicationData(23);

  final int value;
  const ContentType(this.value);

  static ContentType? fromValue(int value) {
    for (final type in ContentType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Alert description codes
/// RFC 5246 Section 7.2
enum AlertDesc {
  closeNotify(0),
  unexpectedMessage(10),
  badRecordMac(20),
  decryptionFailed(21),
  recordOverflow(22),
  decompressionFailure(30),
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
  const AlertDesc(this.value);

  static AlertDesc? fromValue(int value) {
    for (final desc in AlertDesc.values) {
      if (desc.value == value) return desc;
    }
    return null;
  }
}

// AlertLevel moved to lib/src/dtls/handshake/const.dart

/// Protocol version
class ProtocolVersion {
  final int major;
  final int minor;

  const ProtocolVersion(this.major, this.minor);

  /// DTLS 1.0 (version 254.255 in wire format due to TLS legacy)
  static const dtls10 = ProtocolVersion(254, 255);

  /// DTLS 1.2 (version 254.253 in wire format)
  static const dtls12 = ProtocolVersion(254, 253);

  @override
  bool operator ==(Object other) =>
      other is ProtocolVersion && major == other.major && minor == other.minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => 'DTLS $major.$minor';
}

/// Record header length (13 bytes for DTLS)
const int dtlsRecordHeaderLength = 13;

/// Maximum record payload length
const int dtlsMaxRecordLength = 16384; // 2^14 bytes

/// Maximum fragment length
const int dtlsMaxFragmentLength = 16384;

/// Minimum record size
const int dtlsMinRecordSize = dtlsRecordHeaderLength + 1;
