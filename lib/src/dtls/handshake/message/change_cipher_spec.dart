import 'dart:typed_data';

/// ChangeCipherSpec message
/// RFC 5246 Section 7.1
///
/// Note: ChangeCipherSpec is technically not a handshake message,
/// it's a separate protocol with ContentType.changeCipherSpec (20).
/// However, it's used within the handshake flow.
///
/// struct {
///   enum { change_cipher_spec(1), (255) } type;
/// } ChangeCipherSpec;
class ChangeCipherSpec {
  static const int typeValue = 1;

  const ChangeCipherSpec();

  /// Serialize to bytes (always [1])
  Uint8List serialize() {
    return Uint8List.fromList([typeValue]);
  }

  /// Parse from bytes
  static ChangeCipherSpec parse(Uint8List data) {
    if (data.length < 1) {
      throw FormatException('ChangeCipherSpec too short: ${data.length} bytes');
    }

    if (data[0] != typeValue) {
      throw FormatException('Invalid ChangeCipherSpec value: ${data[0]}');
    }

    return const ChangeCipherSpec();
  }

  @override
  String toString() {
    return 'ChangeCipherSpec()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ChangeCipherSpec;
  }

  @override
  int get hashCode => typeValue.hashCode;
}
