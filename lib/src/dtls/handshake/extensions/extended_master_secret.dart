import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';

/// ExtendedMasterSecret Extension
/// RFC 7627
///
/// This extension is empty (no data), just its presence indicates support
/// for the extended master secret computation which provides better security
/// by binding the master secret to the handshake transcript.
class ExtendedMasterSecretExtension extends Extension {
  ExtendedMasterSecretExtension();

  @override
  ExtensionType get type => ExtensionType.extendedMasterSecret;

  @override
  Uint8List serializeData() {
    // This extension has no data
    return Uint8List(0);
  }

  /// Parse from extension data
  static ExtendedMasterSecretExtension parse(Uint8List data) {
    // Extension should be empty
    if (data.isNotEmpty) {
      throw FormatException('ExtendedMasterSecret should have no data');
    }
    return ExtendedMasterSecretExtension();
  }

  @override
  String toString() {
    return 'ExtendedMasterSecretExtension()';
  }
}
