import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';

/// SignatureAlgorithms extension
/// RFC 5246 Section 7.4.1.4.1
///
/// enum {
///   rsa(1), dsa(2), ecdsa(3)
/// } SignatureAlgorithm;
///
/// enum {
///   sha256(4), sha384(5), sha512(6)
/// } HashAlgorithm;
class SignatureAlgorithmsExtension extends Extension {
  final List<SignatureScheme> algorithms;

  SignatureAlgorithmsExtension(this.algorithms);

  @override
  ExtensionType get type => ExtensionType.signatureAlgorithms;

  @override
  Uint8List serializeData() {
    final result = Uint8List(2 + algorithms.length * 2);
    final buffer = ByteData.sublistView(result);

    // Algorithms length (2 bytes)
    buffer.setUint16(0, algorithms.length * 2);

    // Write each algorithm (2 bytes each)
    var offset = 2;
    for (final algorithm in algorithms) {
      buffer.setUint16(offset, algorithm.value);
      offset += 2;
    }

    return result;
  }

  /// Parse from extension data
  static SignatureAlgorithmsExtension parse(Uint8List data) {
    if (data.length < 2) {
      throw FormatException('SignatureAlgorithms extension too short');
    }

    final buffer = ByteData.sublistView(data);
    final algosLength = buffer.getUint16(0);

    if (data.length < 2 + algosLength) {
      throw FormatException('Incomplete SignatureAlgorithms data');
    }

    final algorithms = <SignatureScheme>[];
    var offset = 2;

    while (offset < 2 + algosLength) {
      final algoValue = buffer.getUint16(offset);
      final algo = SignatureScheme.fromValue(algoValue);
      if (algo != null) {
        algorithms.add(algo);
      }
      offset += 2;
    }

    return SignatureAlgorithmsExtension(algorithms);
  }

  @override
  String toString() {
    return 'SignatureAlgorithmsExtension(algorithms=$algorithms)';
  }
}
