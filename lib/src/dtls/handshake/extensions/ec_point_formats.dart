import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';

/// EC Point Formats Extension
/// RFC 8422 Section 5.1.2
///
/// enum { uncompressed (0), ansiX962_compressed_prime (1),
///        ansiX962_compressed_char2 (2), (255) } ECPointFormat;
class ECPointFormatsExtension extends Extension {
  final List<ECPointFormat> formats;

  ECPointFormatsExtension(this.formats);

  @override
  ExtensionType get type => ExtensionType.ecPointFormats;

  @override
  Uint8List serializeData() {
    final result = Uint8List(1 + formats.length);

    // Formats length (1 byte)
    result[0] = formats.length;

    // Write each format (1 byte each)
    for (var i = 0; i < formats.length; i++) {
      result[1 + i] = formats[i].value;
    }

    return result;
  }

  /// Parse from extension data
  static ECPointFormatsExtension parse(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('ECPointFormats extension too short');
    }

    final formatsLength = data[0];

    if (data.length < 1 + formatsLength) {
      throw FormatException('Incomplete ECPointFormats data');
    }

    final formats = <ECPointFormat>[];
    for (var i = 0; i < formatsLength; i++) {
      final formatValue = data[1 + i];
      final format = ECPointFormat.fromValue(formatValue);
      if (format != null) {
        formats.add(format);
      }
    }

    return ECPointFormatsExtension(formats);
  }

  @override
  String toString() {
    return 'ECPointFormatsExtension(formats=$formats)';
  }
}
