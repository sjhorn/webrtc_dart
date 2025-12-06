import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';
import 'package:webrtc_dart/src/dtls/handshake/random.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// ClientHello message
/// RFC 5246 Section 7.4.1.2
///
/// struct {
///   ProtocolVersion client_version;
///   Random random;
///   SessionID session_id;
///   opaque cookie<0..2^8-1>;                             // DTLS only
///   CipherSuite cipher_suites<2..2^16-2>;
///   CompressionMethod compression_methods<1..2^8-1>;
///   Extension extensions<0..2^16-1>;
/// } ClientHello;
class ClientHello {
  final ProtocolVersion clientVersion;
  final DtlsRandom random;
  final Uint8List sessionId;
  final Uint8List cookie; // DTLS-specific
  final List<CipherSuite> cipherSuites;
  final List<CompressionMethod> compressionMethods;
  final List<Extension> extensions;

  ClientHello({
    required this.clientVersion,
    required this.random,
    required this.sessionId,
    Uint8List? cookie,
    required this.cipherSuites,
    required this.compressionMethods,
    List<Extension>? extensions,
  })  : cookie = cookie ?? Uint8List(0),
        extensions = extensions ?? [];

  /// Create a default ClientHello for DTLS 1.2
  factory ClientHello.create({
    Uint8List? sessionId,
    Uint8List? cookie,
    List<CipherSuite>? cipherSuites,
    List<Extension>? extensions,
  }) {
    return ClientHello(
      clientVersion: ProtocolVersion.dtls12,
      random: DtlsRandom.generate(),
      sessionId: sessionId ?? Uint8List(0),
      cookie: cookie ?? Uint8List(0),
      cipherSuites: cipherSuites ??
          [
            CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
            CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
          ],
      compressionMethods: [CompressionMethod.none],
      extensions: extensions ?? [],
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    // Calculate total length
    var totalLength = 2 + // client_version
        32 + // random
        1 +
        sessionId.length + // session_id
        1 +
        cookie.length + // cookie (DTLS)
        2 +
        cipherSuites.length * 2 + // cipher_suites
        1 +
        compressionMethods.length; // compression_methods

    // Serialize extensions
    final extensionBytes = <Uint8List>[];
    for (final extension in extensions) {
      extensionBytes.add(extension.serialize());
    }
    final extensionsLength =
        extensionBytes.fold<int>(0, (sum, b) => sum + b.length);

    if (extensionsLength > 0) {
      totalLength += 2 + extensionsLength; // extensions length + data
    }

    final result = Uint8List(totalLength);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // Client version (2 bytes)
    buffer.setUint8(offset, clientVersion.major);
    buffer.setUint8(offset + 1, clientVersion.minor);
    offset += 2;

    // Random (32 bytes)
    result.setRange(offset, offset + 32, random.bytes);
    offset += 32;

    // Session ID length (1 byte) + data
    buffer.setUint8(offset, sessionId.length);
    offset++;
    if (sessionId.isNotEmpty) {
      result.setRange(offset, offset + sessionId.length, sessionId);
      offset += sessionId.length;
    }

    // Cookie length (1 byte) + data (DTLS-specific)
    buffer.setUint8(offset, cookie.length);
    offset++;
    if (cookie.isNotEmpty) {
      result.setRange(offset, offset + cookie.length, cookie);
      offset += cookie.length;
    }

    // Cipher suites length (2 bytes) + data
    buffer.setUint16(offset, cipherSuites.length * 2);
    offset += 2;
    for (final suite in cipherSuites) {
      buffer.setUint16(offset, suite.value);
      offset += 2;
    }

    // Compression methods length (1 byte) + data
    buffer.setUint8(offset, compressionMethods.length);
    offset++;
    for (final method in compressionMethods) {
      buffer.setUint8(offset, method.value);
      offset++;
    }

    // Extensions length (2 bytes) + data
    if (extensionsLength > 0) {
      buffer.setUint16(offset, extensionsLength);
      offset += 2;
      for (final extBytes in extensionBytes) {
        result.setRange(offset, offset + extBytes.length, extBytes);
        offset += extBytes.length;
      }
    }

    return result;
  }

  /// Parse from bytes
  static ClientHello parse(Uint8List data) {
    if (data.length < 39) {
      // Minimum: 2 (version) + 32 (random) + 1 (session_id len) + 1 (cookie len) + 2 (cipher_suites len) + 1 (compression len)
      throw FormatException('ClientHello too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // Client version (2 bytes)
    final clientVersion = ProtocolVersion(
      buffer.getUint8(offset),
      buffer.getUint8(offset + 1),
    );
    offset += 2;

    // Random (32 bytes)
    final random = DtlsRandom.fromBytes(data.sublist(offset, offset + 32));
    offset += 32;

    // Session ID
    final sessionIdLength = buffer.getUint8(offset);
    offset++;
    final sessionId = data.sublist(offset, offset + sessionIdLength);
    offset += sessionIdLength;

    // Cookie (DTLS-specific)
    final cookieLength = buffer.getUint8(offset);
    offset++;
    final cookie = data.sublist(offset, offset + cookieLength);
    offset += cookieLength;

    // Cipher suites
    final cipherSuitesLength = buffer.getUint16(offset);
    offset += 2;
    final cipherSuites = <CipherSuite>[];
    for (var i = 0; i < cipherSuitesLength; i += 2) {
      final suiteValue = buffer.getUint16(offset);
      final suite = CipherSuite.fromValue(suiteValue);
      if (suite != null) {
        cipherSuites.add(suite);
      }
      offset += 2;
    }

    // Compression methods
    final compressionMethodsLength = buffer.getUint8(offset);
    offset++;
    final compressionMethods = <CompressionMethod>[];
    for (var i = 0; i < compressionMethodsLength; i++) {
      final methodValue = buffer.getUint8(offset);
      final method = CompressionMethod.fromValue(methodValue);
      if (method != null) {
        compressionMethods.add(method);
      }
      offset++;
    }

    // Extensions (optional)
    final extensions = <Extension>[];
    if (offset < data.length) {
      final extensionsLength = buffer.getUint16(offset);
      offset += 2;
      final extensionsData = data.sublist(offset, offset + extensionsLength);
      extensions.addAll(ExtensionParser.parseExtensions(extensionsData));
    }

    return ClientHello(
      clientVersion: clientVersion,
      random: random,
      sessionId: sessionId,
      cookie: cookie,
      cipherSuites: cipherSuites,
      compressionMethods: compressionMethods,
      extensions: extensions,
    );
  }

  /// Check if extended master secret extension is present
  bool get hasExtendedMasterSecret {
    return extensions
        .any((ext) => ext.type == ExtensionType.extendedMasterSecret);
  }

  @override
  String toString() {
    return 'ClientHello(version=$clientVersion, suites=${cipherSuites.length}, extensions=${extensions.length})';
  }
}
