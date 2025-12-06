import 'dart:typed_data';

/// Certificate handshake message
/// RFC 5246 Section 7.4.2
///
/// Structure:
///   opaque ASN.1Cert<1..2^24-1>;
///
///   struct {
///       ASN.1Cert certificate_list<0..2^24-1>;
///   } Certificate;
class Certificate {
  /// List of certificates (DER encoded X.509)
  /// First certificate is the entity's certificate
  /// Remaining certificates form the certificate chain
  final List<Uint8List> certificates;

  const Certificate({
    required this.certificates,
  });

  /// Create a Certificate message with a single certificate
  factory Certificate.single(Uint8List certificate) {
    return Certificate(certificates: [certificate]);
  }

  /// Create a Certificate message with a certificate chain
  factory Certificate.chain(List<Uint8List> certificates) {
    return Certificate(certificates: certificates);
  }

  /// Serialize to bytes
  Uint8List serialize() {
    // Calculate total length
    var totalLength = 3; // 3-byte length field for certificate_list

    for (final cert in certificates) {
      totalLength += 3; // 3-byte length field for each certificate
      totalLength += cert.length;
    }

    final result = Uint8List(totalLength);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // Certificate list length (3 bytes)
    final certificateListLength = totalLength - 3;
    buffer.setUint8(offset++, (certificateListLength >> 16) & 0xFF);
    buffer.setUint8(offset++, (certificateListLength >> 8) & 0xFF);
    buffer.setUint8(offset++, certificateListLength & 0xFF);

    // Certificates
    for (final cert in certificates) {
      // Certificate length (3 bytes)
      buffer.setUint8(offset++, (cert.length >> 16) & 0xFF);
      buffer.setUint8(offset++, (cert.length >> 8) & 0xFF);
      buffer.setUint8(offset++, cert.length & 0xFF);

      // Certificate data
      result.setRange(offset, offset + cert.length, cert);
      offset += cert.length;
    }

    return result;
  }

  /// Parse from bytes
  static Certificate parse(Uint8List data) {
    if (data.length < 3) {
      throw FormatException(
          'Certificate message too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // Certificate list length (3 bytes)
    final certificateListLength = (buffer.getUint8(offset++) << 16) |
        (buffer.getUint8(offset++) << 8) |
        buffer.getUint8(offset++);

    if (data.length < 3 + certificateListLength) {
      throw FormatException(
        'Certificate message truncated: expected ${3 + certificateListLength}, got ${data.length}',
      );
    }

    // Parse certificates
    final certificates = <Uint8List>[];
    var remaining = certificateListLength;

    while (remaining > 0) {
      if (remaining < 3) {
        throw FormatException('Invalid certificate length field');
      }

      // Certificate length (3 bytes)
      final certLength = (buffer.getUint8(offset++) << 16) |
          (buffer.getUint8(offset++) << 8) |
          buffer.getUint8(offset++);
      remaining -= 3;

      if (remaining < certLength) {
        throw FormatException('Certificate data truncated');
      }

      // Certificate data
      final cert = Uint8List.fromList(
        data.sublist(offset, offset + certLength),
      );
      certificates.add(cert);

      offset += certLength;
      remaining -= certLength;
    }

    return Certificate(certificates: certificates);
  }

  /// Get the entity's certificate (first in the list)
  Uint8List? get entityCertificate {
    return certificates.isNotEmpty ? certificates.first : null;
  }

  /// Check if this is an empty certificate message
  bool get isEmpty => certificates.isEmpty;

  @override
  String toString() {
    return 'Certificate(certificates: ${certificates.length})';
  }
}
