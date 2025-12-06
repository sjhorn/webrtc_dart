import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// CertificateVerify handshake message
/// RFC 5246 Section 7.4.8
///
/// Structure:
///   struct {
///       SignatureAndHashAlgorithm algorithm;
///       opaque signature<0..2^16-1>;
///   } CertificateVerify;
///
/// The signature is computed over all handshake messages sent and received
/// up to but not including this message.
class CertificateVerify {
  /// Signature scheme used
  final SignatureScheme signatureScheme;

  /// The signature over the handshake messages
  final Uint8List signature;

  const CertificateVerify({
    required this.signatureScheme,
    required this.signature,
  });

  /// Create a CertificateVerify with a signature scheme and signature
  factory CertificateVerify.create(
    SignatureScheme signatureScheme,
    Uint8List signature,
  ) {
    return CertificateVerify(
      signatureScheme: signatureScheme,
      signature: signature,
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    // 2 bytes signature scheme + 2 bytes signature length + signature
    final result = Uint8List(2 + 2 + signature.length);
    final buffer = ByteData.sublistView(result);

    // Signature scheme (2 bytes, big-endian)
    buffer.setUint16(0, signatureScheme.value);

    // Signature length (2 bytes)
    buffer.setUint16(2, signature.length);

    // Signature
    result.setRange(4, 4 + signature.length, signature);

    return result;
  }

  /// Parse from bytes
  static CertificateVerify parse(Uint8List data) {
    if (data.length < 4) {
      throw FormatException(
          'CertificateVerify too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);

    // Signature scheme (2 bytes)
    final schemeValue = buffer.getUint16(0);
    final signatureScheme = SignatureScheme.fromValue(schemeValue);
    if (signatureScheme == null) {
      throw FormatException(
          'Unknown signature scheme: 0x${schemeValue.toRadixString(16)}');
    }

    // Signature length (2 bytes)
    final signatureLength = buffer.getUint16(2);

    if (data.length < 4 + signatureLength) {
      throw FormatException(
        'CertificateVerify truncated: expected ${4 + signatureLength}, got ${data.length}',
      );
    }

    // Signature
    final signature = Uint8List.fromList(data.sublist(4, 4 + signatureLength));

    return CertificateVerify(
      signatureScheme: signatureScheme,
      signature: signature,
    );
  }

  @override
  String toString() {
    return 'CertificateVerify(scheme=$signatureScheme, signature=${signature.length} bytes)';
  }
}
