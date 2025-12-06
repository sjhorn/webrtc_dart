import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// HelloVerifyRequest message
/// RFC 6347 Section 4.2.1
///
/// DTLS-specific message for cookie exchange to prevent DoS attacks.
/// The server sends this in response to the first ClientHello,
/// and the client must resend ClientHello with the cookie.
///
/// struct {
///   ProtocolVersion server_version;
///   opaque cookie<0..2^8-1>;
/// } HelloVerifyRequest;
class HelloVerifyRequest {
  final ProtocolVersion serverVersion;
  final Uint8List cookie;

  const HelloVerifyRequest({
    required this.serverVersion,
    required this.cookie,
  });

  /// Create a HelloVerifyRequest with DTLS 1.2 and generated cookie
  factory HelloVerifyRequest.create(Uint8List cookie) {
    return HelloVerifyRequest(
      serverVersion: ProtocolVersion.dtls12,
      cookie: cookie,
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    final result = Uint8List(3 + cookie.length);
    final buffer = ByteData.sublistView(result);

    // Server version (2 bytes)
    buffer.setUint8(0, serverVersion.major);
    buffer.setUint8(1, serverVersion.minor);

    // Cookie length (1 byte)
    buffer.setUint8(2, cookie.length);

    // Cookie data
    if (cookie.isNotEmpty) {
      result.setRange(3, 3 + cookie.length, cookie);
    }

    return result;
  }

  /// Parse from bytes
  static HelloVerifyRequest parse(Uint8List data) {
    if (data.length < 3) {
      throw FormatException(
          'HelloVerifyRequest too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);

    // Server version (2 bytes)
    final serverVersion = ProtocolVersion(
      buffer.getUint8(0),
      buffer.getUint8(1),
    );

    // Cookie length (1 byte)
    final cookieLength = buffer.getUint8(2);

    if (data.length < 3 + cookieLength) {
      throw FormatException('Incomplete HelloVerifyRequest cookie');
    }

    // Cookie data
    final cookie = data.sublist(3, 3 + cookieLength);

    return HelloVerifyRequest(
      serverVersion: serverVersion,
      cookie: cookie,
    );
  }

  @override
  String toString() {
    return 'HelloVerifyRequest(version=$serverVersion, cookie=${cookie.length} bytes)';
  }
}
