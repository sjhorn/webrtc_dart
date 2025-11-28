import 'dart:typed_data';

/// ServerHelloDone message
/// RFC 5246 Section 7.4.5
///
/// The ServerHelloDone message is sent by the server to indicate the
/// end of the ServerHello and associated messages. This message means
/// that the server is done sending messages to support the key exchange,
/// and the client can proceed with its phase of the key exchange.
///
/// struct { } ServerHelloDone;
class ServerHelloDone {
  const ServerHelloDone();

  /// Serialize to bytes (empty message)
  Uint8List serialize() {
    return Uint8List(0);
  }

  /// Parse from bytes
  static ServerHelloDone parse(Uint8List data) {
    if (data.isNotEmpty) {
      throw FormatException('ServerHelloDone should be empty, got ${data.length} bytes');
    }

    return const ServerHelloDone();
  }

  @override
  String toString() {
    return 'ServerHelloDone()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ServerHelloDone;
  }

  @override
  int get hashCode => 0;
}
