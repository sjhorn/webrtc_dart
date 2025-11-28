import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';

/// SupportedGroups extension (formerly EllipticCurves)
/// RFC 8422 Section 5.1.1
///
/// enum {
///   secp256r1(23), secp384r1(24), x25519(29), ...
/// } NamedGroup;
class EllipticCurvesExtension extends Extension {
  final List<NamedCurve> curves;

  EllipticCurvesExtension(this.curves);

  @override
  ExtensionType get type => ExtensionType.ellipticCurves;

  @override
  Uint8List serializeData() {
    final result = Uint8List(2 + curves.length * 2);
    final buffer = ByteData.sublistView(result);

    // Curves length (2 bytes)
    buffer.setUint16(0, curves.length * 2);

    // Write each curve (2 bytes each)
    var offset = 2;
    for (final curve in curves) {
      buffer.setUint16(offset, curve.value);
      offset += 2;
    }

    return result;
  }

  /// Parse from extension data
  static EllipticCurvesExtension parse(Uint8List data) {
    if (data.length < 2) {
      throw FormatException('EllipticCurves extension too short');
    }

    final buffer = ByteData.sublistView(data);
    final curvesLength = buffer.getUint16(0);

    if (data.length < 2 + curvesLength) {
      throw FormatException('Incomplete EllipticCurves data');
    }

    final curves = <NamedCurve>[];
    var offset = 2;

    while (offset < 2 + curvesLength) {
      final curveValue = buffer.getUint16(offset);
      final curve = NamedCurve.fromValue(curveValue);
      if (curve != null) {
        curves.add(curve);
      }
      offset += 2;
    }

    return EllipticCurvesExtension(curves);
  }

  @override
  String toString() {
    return 'EllipticCurvesExtension(curves=$curves)';
  }
}
