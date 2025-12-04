import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/common/crypto.dart';

/// Certificate information
class CertificateInfo {
  final String commonName;
  final DateTime notBefore;
  final DateTime notAfter;
  final List<String>? subjectAltNames;

  CertificateInfo({
    required this.commonName,
    DateTime? notBefore,
    DateTime? notAfter,
    this.subjectAltNames,
  })  : notBefore = notBefore ?? DateTime.now(),
        notAfter = notAfter ?? DateTime.now().add(const Duration(days: 365));
}

/// Generated certificate and private key pair
class CertificateKeyPair {
  /// X.509 certificate (DER encoded)
  final Uint8List certificate;

  /// Private key
  final ECPrivateKey privateKey;

  /// Public key
  final ECPublicKey publicKey;

  CertificateKeyPair({
    required this.certificate,
    required this.privateKey,
    required this.publicKey,
  });
}

/// Generate a self-signed ECDSA certificate for DTLS
///
/// This creates a minimal X.509v3 certificate suitable for DTLS.
/// The certificate is self-signed and uses ECDSA with P-256.
Future<CertificateKeyPair> generateSelfSignedCertificate({
  CertificateInfo? info,
}) async {
  info ??= CertificateInfo(commonName: 'WebRTC DTLS');

  // Generate ECDSA key pair using P-256
  final keyGen = ECKeyGenerator();
  final params = ECKeyGeneratorParameters(ECCurve_secp256r1());

  final random = FortunaRandom();
  final seed = randomBytes(32);
  random.seed(KeyParameter(seed));

  keyGen.init(ParametersWithRandom(params, random));
  final keyPair = keyGen.generateKeyPair();

  final privateKey = keyPair.privateKey as ECPrivateKey;
  final publicKey = keyPair.publicKey as ECPublicKey;

  // Create a minimal self-signed certificate
  // For production, you'd want to use a proper ASN.1 library
  // This is a simplified version for WebRTC DTLS
  final certificate = _createMinimalCertificate(
    info: info,
    publicKey: publicKey,
    privateKey: privateKey,
  );

  return CertificateKeyPair(
    certificate: certificate,
    privateKey: privateKey,
    publicKey: publicKey,
  );
}

/// Create a minimal self-signed certificate (simplified DER encoding)
///
/// This creates a basic X.509v3 certificate structure.
/// For WebRTC DTLS, we need:
/// - Version: v3 (2)
/// - Serial number: random
/// - Signature algorithm: ECDSA with SHA-256
/// - Issuer: CN=`<commonName>`
/// - Validity: notBefore/notAfter
/// - Subject: CN=`<commonName>`
/// - Subject public key info
/// - Extensions: basic constraints, key usage
/// - Signature
Uint8List _createMinimalCertificate({
  required CertificateInfo info,
  required ECPublicKey publicKey,
  required ECPrivateKey privateKey,
}) {
  // This is a placeholder implementation
  // In production, you would use a proper X.509 library or asn1lib package
  //
  // For now, we'll create a minimal DER-encoded certificate structure
  // that's sufficient for DTLS handshake testing

  final builder = _Asn1Builder();

  // Certificate ::= SEQUENCE {
  builder.startSequence();

  // TBSCertificate ::= SEQUENCE {
  builder.startSequence();

  // Version [0] EXPLICIT Version DEFAULT v1
  builder.startContext(0);
  builder.writeInteger(2); // v3
  builder.endContext();

  // Serial number
  final serialNumber = randomBytes(20);
  builder.writeInteger(serialNumber);

  // Signature algorithm (ECDSA with SHA-256)
  builder.startSequence();
  builder.writeOid([1, 2, 840, 10045, 4, 3, 2]); // ecdsaWithSHA256
  builder.endSequence();

  // Issuer (CN=commonName)
  builder.startSequence();
  builder.startSet();
  builder.startSequence();
  builder.writeOid([2, 5, 4, 3]); // commonName
  builder.writeUtf8String(info.commonName);
  builder.endSequence();
  builder.endSet();
  builder.endSequence();

  // Validity
  builder.startSequence();
  builder.writeUtcTime(info.notBefore);
  builder.writeUtcTime(info.notAfter);
  builder.endSequence();

  // Subject (same as issuer for self-signed)
  builder.startSequence();
  builder.startSet();
  builder.startSequence();
  builder.writeOid([2, 5, 4, 3]); // commonName
  builder.writeUtf8String(info.commonName);
  builder.endSequence();
  builder.endSet();
  builder.endSequence();

  // Subject Public Key Info
  _writePublicKeyInfo(builder, publicKey);

  // Extensions [3] EXPLICIT Extensions OPTIONAL
  builder.startContext(3);
  builder.startSequence();

  // Basic Constraints
  builder.startSequence();
  builder.writeOid([2, 5, 29, 19]); // basicConstraints
  builder.writeBoolean(true); // critical
  builder.writeOctetString(_encodeBasicConstraints());
  builder.endSequence();

  // Key Usage
  builder.startSequence();
  builder.writeOid([2, 5, 29, 15]); // keyUsage
  builder.writeBoolean(true); // critical
  builder.writeOctetString(_encodeKeyUsage());
  builder.endSequence();

  builder.endSequence();
  builder.endContext();

  builder.endSequence(); // End TBSCertificate

  // Sign the TBSCertificate
  final tbsCertificate = builder.getBytes();
  final signature = _signCertificate(tbsCertificate, privateKey);

  // Signature algorithm
  builder.startSequence();
  builder.writeOid([1, 2, 840, 10045, 4, 3, 2]); // ecdsaWithSHA256
  builder.endSequence();

  // Signature value
  builder.writeBitString(signature);

  builder.endSequence(); // End Certificate

  return builder.getBytes();
}

/// Write public key info to ASN.1 builder
void _writePublicKeyInfo(_Asn1Builder builder, ECPublicKey publicKey) {
  builder.startSequence();

  // Algorithm
  builder.startSequence();
  builder.writeOid([1, 2, 840, 10045, 2, 1]); // ecPublicKey
  builder.writeOid([1, 2, 840, 10045, 3, 1, 7]); // secp256r1
  builder.endSequence();

  // Public key (uncompressed point)
  final qBytes = publicKey.Q!.getEncoded(false);
  builder.writeBitString(qBytes);

  builder.endSequence();
}

/// Sign the TBSCertificate
Uint8List _signCertificate(Uint8List tbsCertificate, ECPrivateKey privateKey) {
  // Create SHA-256 digest
  final digest = Digest('SHA-256');
  final hash = digest.process(tbsCertificate);

  // Sign the hash using ECDSA
  final signer = ECDSASigner(null, HMac(digest, 64));
  signer.init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
  final signature = signer.generateSignature(hash) as ECSignature;

  // Encode signature as DER SEQUENCE of two INTEGERs
  final builder = _Asn1Builder();
  builder.startSequence();
  builder.writeInteger(signature.r.toRadixString(16));
  builder.writeInteger(signature.s.toRadixString(16));
  builder.endSequence();

  return builder.getBytes();
}

/// Encode basic constraints extension
Uint8List _encodeBasicConstraints() {
  final builder = _Asn1Builder();
  builder.startSequence();
  builder.writeBoolean(false); // CA:FALSE
  builder.endSequence();
  return builder.getBytes();
}

/// Encode key usage extension
Uint8List _encodeKeyUsage() {
  final builder = _Asn1Builder();
  // Digital signature and key agreement
  builder.writeBitString(Uint8List.fromList([0x80 | 0x08])); // bits 0 and 4
  return builder.getBytes();
}

/// Simple ASN.1 DER builder
/// This is a minimal implementation for certificate generation
class _Asn1Builder {
  final List<int> _bytes = [];
  final List<List<int>> _stack = [];

  void startSequence() => _startConstructed(0x30);
  void startSet() => _startConstructed(0x31);
  void startContext(int tag) => _startConstructed(0xA0 | tag);

  void _startConstructed(int tag) {
    _stack.add([tag]);
  }

  void endSequence() => _endConstructed();
  void endSet() => _endConstructed();
  void endContext() => _endConstructed();

  void _endConstructed() {
    final content = _stack.removeLast();
    final tag = content[0];
    final data = content.sublist(1);
    _writeTagLengthValue(tag, Uint8List.fromList(data));
  }

  void writeInteger(dynamic value) {
    Uint8List bytes;
    if (value is Uint8List) {
      bytes = value;
    } else if (value is String) {
      bytes = Uint8List.fromList(
        BigInt.parse(value, radix: 16).toRadixString(16).padLeft(
          (value.length / 2).ceil() * 2, '0').codeUnits.map((c) {
            return int.parse(String.fromCharCode(c), radix: 16);
          }).toList(),
      );
    } else {
      bytes = Uint8List.fromList([value as int]);
    }
    _writeTagLengthValue(0x02, bytes);
  }

  void writeOid(List<int> oid) {
    final bytes = <int>[];
    bytes.add(oid[0] * 40 + oid[1]);
    for (var i = 2; i < oid.length; i++) {
      var value = oid[i];
      if (value < 128) {
        bytes.add(value);
      } else {
        final temp = <int>[];
        while (value > 0) {
          temp.insert(0, (value & 0x7F) | (temp.isEmpty ? 0 : 0x80));
          value >>= 7;
        }
        bytes.addAll(temp);
      }
    }
    _writeTagLengthValue(0x06, Uint8List.fromList(bytes));
  }

  void writeUtf8String(String value) {
    _writeTagLengthValue(0x0C, Uint8List.fromList(value.codeUnits));
  }

  void writeUtcTime(DateTime dateTime) {
    final year = dateTime.year.toString().substring(2);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final formatted = '$year$month$day$hour$minute${second}Z';
    _writeTagLengthValue(0x17, Uint8List.fromList(formatted.codeUnits));
  }

  void writeBoolean(bool value) {
    _writeTagLengthValue(0x01, Uint8List.fromList([value ? 0xFF : 0x00]));
  }

  void writeOctetString(Uint8List value) {
    _writeTagLengthValue(0x04, value);
  }

  void writeBitString(Uint8List value) {
    final bytes = Uint8List(value.length + 1);
    bytes[0] = 0; // no unused bits
    bytes.setRange(1, bytes.length, value);
    _writeTagLengthValue(0x03, bytes);
  }

  void _writeTagLengthValue(int tag, Uint8List value) {
    if (_stack.isNotEmpty) {
      _stack.last.add(tag);
      _stack.last.addAll(_encodeLength(value.length));
      _stack.last.addAll(value);
    } else {
      _bytes.add(tag);
      _bytes.addAll(_encodeLength(value.length));
      _bytes.addAll(value);
    }
  }

  List<int> _encodeLength(int length) {
    if (length < 128) {
      return [length];
    } else {
      final bytes = <int>[];
      var temp = length;
      while (temp > 0) {
        bytes.insert(0, temp & 0xFF);
        temp >>= 8;
      }
      return [0x80 | bytes.length, ...bytes];
    }
  }

  Uint8List getBytes() {
    return Uint8List.fromList(_bytes);
  }
}

/// Compute the SHA-256 fingerprint of a certificate
/// Returns the fingerprint in the format "sha-256 XX:XX:XX:..."
String computeCertificateFingerprint(Uint8List certificate) {
  final digest = hash('sha256', certificate);

  // Format as colon-separated uppercase hex pairs
  final hexPairs = <String>[];
  for (var i = 0; i < digest.length; i++) {
    hexPairs.add(digest[i].toRadixString(16).padLeft(2, '0').toUpperCase());
  }

  return 'sha-256 ${hexPairs.join(':')}';
}
