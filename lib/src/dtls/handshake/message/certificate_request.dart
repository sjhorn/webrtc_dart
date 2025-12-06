import 'dart:typed_data';

import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// CertificateRequest message
/// RFC 5246 Section 7.4.4
///
/// When client authentication is desired, the server sends a
/// CertificateRequest message to request a certificate from the client.
///
/// struct {
///   ClientCertificateType certificate_types<1..2^8-1>;
///   SignatureAndHashAlgorithm
///     supported_signature_algorithms<2..2^16-2>;
///   DistinguishedName certificate_authorities<0..2^16-1>;
/// } CertificateRequest;
class CertificateRequest {
  /// Types of certificates the client can present
  /// (e.g., RSA sign, ECDSA sign)
  final List<ClientCertificateType> certificateTypes;

  /// Supported signature algorithms
  final List<SignatureHashAlgorithm> signatureAlgorithms;

  /// List of distinguished names of acceptable certificate authorities
  /// (empty list means any CA is acceptable)
  final List<Uint8List> certificateAuthorities;

  const CertificateRequest({
    required this.certificateTypes,
    required this.signatureAlgorithms,
    this.certificateAuthorities = const [],
  });

  /// Create a default CertificateRequest matching werift's defaults
  /// werift uses: certificateTypes = [RSA_SIGN, ECDSA_SIGN]
  ///              signatures = [SHA256+RSA, SHA256+ECDSA]
  ///              authorities = []
  factory CertificateRequest.createDefault() {
    return CertificateRequest(
      certificateTypes: [
        ClientCertificateType.rsaSign,
        ClientCertificateType.ecdsaSign,
      ],
      signatureAlgorithms: [
        SignatureHashAlgorithm(
          hash: HashAlgorithm.sha256,
          signature: SignatureAlgorithm.rsa,
        ),
        SignatureHashAlgorithm(
          hash: HashAlgorithm.sha256,
          signature: SignatureAlgorithm.ecdsa,
        ),
      ],
      certificateAuthorities: [],
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    // Calculate sizes
    final certTypesLength = certificateTypes.length;

    // Signature algorithms: 2 bytes per algorithm
    final sigAlgosLength = signatureAlgorithms.length * 2;

    // Certificate authorities: each is length-prefixed (2 bytes + data)
    var authoritiesDataLength = 0;
    for (final authority in certificateAuthorities) {
      authoritiesDataLength += 2 + authority.length;
    }

    // Total message size:
    // 1 byte (cert types length) + cert types
    // + 2 bytes (sig algos length) + sig algos
    // + 2 bytes (authorities length) + authorities data
    final totalLength =
        1 + certTypesLength + 2 + sigAlgosLength + 2 + authoritiesDataLength;
    final result = Uint8List(totalLength);
    var offset = 0;

    // Certificate types (length-prefixed with 1 byte)
    result[offset++] = certTypesLength;
    for (final certType in certificateTypes) {
      result[offset++] = certType.value;
    }

    // Signature algorithms (length-prefixed with 2 bytes)
    result[offset++] = (sigAlgosLength >> 8) & 0xFF;
    result[offset++] = sigAlgosLength & 0xFF;
    for (final sigAlgo in signatureAlgorithms) {
      result[offset++] = sigAlgo.hash.value;
      result[offset++] = sigAlgo.signature.value;
    }

    // Certificate authorities (length-prefixed with 2 bytes)
    result[offset++] = (authoritiesDataLength >> 8) & 0xFF;
    result[offset++] = authoritiesDataLength & 0xFF;
    for (final authority in certificateAuthorities) {
      // Each authority is length-prefixed with 2 bytes
      result[offset++] = (authority.length >> 8) & 0xFF;
      result[offset++] = authority.length & 0xFF;
      result.setRange(offset, offset + authority.length, authority);
      offset += authority.length;
    }

    return result;
  }

  /// Parse from bytes
  static CertificateRequest parse(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('CertificateRequest data is empty');
    }

    var offset = 0;

    // Certificate types (1-byte length prefix)
    final certTypesLength = data[offset++];
    if (offset + certTypesLength > data.length) {
      throw FormatException('Invalid certificate types length');
    }

    final certificateTypes = <ClientCertificateType>[];
    for (var i = 0; i < certTypesLength; i++) {
      final type = ClientCertificateType.fromValue(data[offset++]);
      if (type != null) {
        certificateTypes.add(type);
      }
    }

    // Signature algorithms (2-byte length prefix)
    if (offset + 2 > data.length) {
      throw FormatException('Missing signature algorithms length');
    }
    final sigAlgosLength = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    if (offset + sigAlgosLength > data.length) {
      throw FormatException('Invalid signature algorithms length');
    }

    final signatureAlgorithms = <SignatureHashAlgorithm>[];
    final sigAlgosEnd = offset + sigAlgosLength;
    while (offset < sigAlgosEnd) {
      final hash = HashAlgorithm.fromValue(data[offset++]);
      final sig = SignatureAlgorithm.fromValue(data[offset++]);
      if (hash != null && sig != null) {
        signatureAlgorithms
            .add(SignatureHashAlgorithm(hash: hash, signature: sig));
      }
    }

    // Certificate authorities (2-byte length prefix)
    if (offset + 2 > data.length) {
      throw FormatException('Missing certificate authorities length');
    }
    final authoritiesLength = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    if (offset + authoritiesLength > data.length) {
      throw FormatException('Invalid certificate authorities length');
    }

    final certificateAuthorities = <Uint8List>[];
    final authoritiesEnd = offset + authoritiesLength;
    while (offset < authoritiesEnd) {
      // Each authority is length-prefixed with 2 bytes
      final authorityLength = (data[offset] << 8) | data[offset + 1];
      offset += 2;
      if (offset + authorityLength > authoritiesEnd) {
        throw FormatException('Invalid authority length');
      }
      certificateAuthorities.add(Uint8List.fromList(
        data.sublist(offset, offset + authorityLength),
      ));
      offset += authorityLength;
    }

    return CertificateRequest(
      certificateTypes: certificateTypes,
      signatureAlgorithms: signatureAlgorithms,
      certificateAuthorities: certificateAuthorities,
    );
  }

  @override
  String toString() {
    return 'CertificateRequest('
        'certificateTypes: $certificateTypes, '
        'signatureAlgorithms: $signatureAlgorithms, '
        'certificateAuthorities: ${certificateAuthorities.length} entries)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CertificateRequest) return false;
    if (certificateTypes.length != other.certificateTypes.length) return false;
    if (signatureAlgorithms.length != other.signatureAlgorithms.length) {
      return false;
    }
    if (certificateAuthorities.length != other.certificateAuthorities.length) {
      return false;
    }
    for (var i = 0; i < certificateTypes.length; i++) {
      if (certificateTypes[i] != other.certificateTypes[i]) return false;
    }
    for (var i = 0; i < signatureAlgorithms.length; i++) {
      if (signatureAlgorithms[i] != other.signatureAlgorithms[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(certificateTypes),
        Object.hashAll(signatureAlgorithms),
        Object.hashAll(certificateAuthorities),
      );
}

/// Client certificate types (RFC 5246 Section 7.4.4)
enum ClientCertificateType {
  rsaSign(1),
  dssSign(2),
  rsaFixedDh(3),
  dssFixedDh(4),
  rsaEphemeralDh(5),
  dssEphemeralDh(6),
  fortezzaDms(20),
  ecdsaSign(64),
  rsaFixedEcdh(65),
  ecdsaFixedEcdh(66);

  final int value;
  const ClientCertificateType(this.value);

  static ClientCertificateType? fromValue(int value) {
    for (final type in ClientCertificateType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Signature and hash algorithm pair (RFC 5246 Section 7.4.1.4.1)
class SignatureHashAlgorithm {
  final HashAlgorithm hash;
  final SignatureAlgorithm signature;

  const SignatureHashAlgorithm({
    required this.hash,
    required this.signature,
  });

  @override
  String toString() => '${hash.name}+${signature.name}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SignatureHashAlgorithm) return false;
    return hash == other.hash && signature == other.signature;
  }

  @override
  int get hashCode => Object.hash(hash, signature);
}
