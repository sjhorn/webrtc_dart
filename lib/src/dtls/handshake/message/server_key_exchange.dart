import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// ServerKeyExchange message for ECDHE
/// RFC 4492 Section 5.4
///
/// struct {
///   ECParameters curve_params;
///   ECPoint public;
///   digitally-signed struct {
///     select (SignatureAlgorithm) {
///       case ecdsa:
///         ECDSASignature;
///       case rsa:
///         RSASignature;
///     } signature;
///   };
/// } ServerECDHParams;
class ServerKeyExchange {
  final NamedCurve curve;
  final Uint8List publicKey;
  final SignatureScheme? signatureScheme; // TLS 1.2+
  final Uint8List signature;

  const ServerKeyExchange({
    required this.curve,
    required this.publicKey,
    this.signatureScheme,
    required this.signature,
  });

  /// Serialize to bytes
  Uint8List serialize() {
    // Calculate total length
    var totalLength = 1 + // ECCurveType (named_curve = 3)
        2 + // NamedCurve
        1 +
        publicKey.length; // public key length + data

    if (signatureScheme != null) {
      totalLength += 2; // SignatureScheme (TLS 1.2+)
    }

    totalLength += 2 + signature.length; // signature length + data

    final result = Uint8List(totalLength);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // ECCurveType: named_curve (3)
    buffer.setUint8(offset, 3);
    offset++;

    // NamedCurve (2 bytes)
    buffer.setUint16(offset, curve.value);
    offset += 2;

    // Public key length (1 byte)
    buffer.setUint8(offset, publicKey.length);
    offset++;

    // Public key data
    result.setRange(offset, offset + publicKey.length, publicKey);
    offset += publicKey.length;

    // SignatureScheme (TLS 1.2+)
    if (signatureScheme != null) {
      buffer.setUint16(offset, signatureScheme!.value);
      offset += 2;
    }

    // Signature length (2 bytes)
    buffer.setUint16(offset, signature.length);
    offset += 2;

    // Signature data
    result.setRange(offset, offset + signature.length, signature);

    return result;
  }

  /// Parse from bytes
  static ServerKeyExchange parse(Uint8List data, {bool hasTls12Signature = true}) {
    if (data.length < 4) {
      throw FormatException('ServerKeyExchange too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // ECCurveType (1 byte)
    final curveType = buffer.getUint8(offset);
    offset++;

    if (curveType != 3) {
      // named_curve
      throw FormatException('Only named_curve supported, got $curveType');
    }

    // NamedCurve (2 bytes)
    final curveValue = buffer.getUint16(offset);
    offset += 2;

    final curve = NamedCurve.fromValue(curveValue);
    if (curve == null) {
      throw FormatException('Unknown curve: $curveValue');
    }

    // Public key length (1 byte)
    final publicKeyLength = buffer.getUint8(offset);
    offset++;

    if (offset + publicKeyLength > data.length) {
      throw FormatException('Incomplete public key data');
    }

    // Public key data
    final publicKey = data.sublist(offset, offset + publicKeyLength);
    offset += publicKeyLength;

    // SignatureScheme (TLS 1.2+)
    SignatureScheme? signatureScheme;
    if (hasTls12Signature) {
      if (offset + 2 > data.length) {
        throw FormatException('Missing signature scheme');
      }

      final schemeValue = buffer.getUint16(offset);
      offset += 2;

      signatureScheme = SignatureScheme.fromValue(schemeValue);
    }

    // Signature length (2 bytes)
    if (offset + 2 > data.length) {
      throw FormatException('Missing signature length');
    }

    final signatureLength = buffer.getUint16(offset);
    offset += 2;

    if (offset + signatureLength > data.length) {
      throw FormatException('Incomplete signature data');
    }

    // Signature data
    final signature = data.sublist(offset, offset + signatureLength);

    return ServerKeyExchange(
      curve: curve,
      publicKey: publicKey,
      signatureScheme: signatureScheme,
      signature: signature,
    );
  }

  @override
  String toString() {
    return 'ServerKeyExchange(curve=$curve, publicKey=${publicKey.length} bytes, signature=${signature.length} bytes)';
  }
}
