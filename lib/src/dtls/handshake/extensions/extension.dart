import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';

/// Base class for TLS extensions
abstract class Extension {
  ExtensionType get type;

  /// Serialize extension data (without type and length header)
  Uint8List serializeData();

  /// Serialize complete extension (type + length + data)
  Uint8List serialize() {
    final data = serializeData();
    final result = Uint8List(4 + data.length);
    final buffer = ByteData.sublistView(result);

    // Extension type (2 bytes)
    buffer.setUint16(0, type.value);

    // Extension length (2 bytes)
    buffer.setUint16(2, data.length);

    // Extension data
    result.setRange(4, result.length, data);

    return result;
  }

  /// Get total serialized length
  int get length => 4 + serializeData().length;
}

/// Parse extensions from buffer
class ExtensionParser {
  /// Parse all extensions from buffer
  static List<Extension> parseExtensions(Uint8List data) {
    final extensions = <Extension>[];
    var offset = 0;

    while (offset < data.length) {
      if (offset + 4 > data.length) {
        throw FormatException('Incomplete extension header');
      }

      final buffer = ByteData.sublistView(data);
      final typeValue = buffer.getUint16(offset);
      final length = buffer.getUint16(offset + 2);

      if (offset + 4 + length > data.length) {
        throw FormatException('Incomplete extension data');
      }

      final extensionData = data.sublist(offset + 4, offset + 4 + length);
      final type = ExtensionType.fromValue(typeValue);

      // Parse known extension types
      if (type != null) {
        final extension = _parseExtension(type, extensionData);
        if (extension != null) {
          extensions.add(extension);
        }
      }

      offset += 4 + length;
    }

    return extensions;
  }

  static Extension? _parseExtension(ExtensionType type, Uint8List data) {
    switch (type) {
      case ExtensionType.ellipticCurves:
        // TODO: implement if needed
        return null;
      case ExtensionType.signatureAlgorithms:
        // TODO: implement if needed
        return null;
      case ExtensionType.useSrtp:
        return UseSrtpExtension.parse(data);
      case ExtensionType.extendedMasterSecret:
        return ExtendedMasterSecretExtension.parse(data);
      default:
        return null;
    }
  }
}
