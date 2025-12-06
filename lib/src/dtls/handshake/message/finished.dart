import 'dart:typed_data';

/// Finished message
/// RFC 5246 Section 7.4.9
///
/// The Finished message is sent immediately after ChangeCipherSpec
/// to verify that the key exchange and authentication processes were successful.
///
/// struct {
///   opaque verify_data[verify_data_length];
/// } Finished;
///
/// verify_data = PRF(master_secret, finished_label, Hash(handshake_messages))
/// verify_data_length = 12 for TLS 1.2
class Finished {
  final Uint8List verifyData;

  const Finished({required this.verifyData});

  /// Create a Finished message with verify data
  factory Finished.create(Uint8List verifyData) {
    if (verifyData.length != 12) {
      throw ArgumentError(
          'Finished verify_data must be 12 bytes, got ${verifyData.length}');
    }
    return Finished(verifyData: verifyData);
  }

  /// Serialize to bytes
  Uint8List serialize() {
    return Uint8List.fromList(verifyData);
  }

  /// Parse from bytes
  static Finished parse(Uint8List data) {
    if (data.length != 12) {
      throw FormatException('Finished must be 12 bytes, got ${data.length}');
    }

    return Finished(verifyData: data);
  }

  @override
  String toString() {
    return 'Finished(verifyData=${verifyData.length} bytes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Finished) return false;

    if (verifyData.length != other.verifyData.length) return false;
    for (var i = 0; i < verifyData.length; i++) {
      if (verifyData[i] != other.verifyData[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(verifyData);
}
