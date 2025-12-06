import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';
import 'package:webrtc_dart/src/dtls/handshake/random.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// ServerHello message
/// RFC 5246 Section 7.4.1.3
///
/// struct {
///   ProtocolVersion server_version;
///   Random random;
///   SessionID session_id;
///   CipherSuite cipher_suite;
///   CompressionMethod compression_method;
///   Extension extensions<0..2^16-1>;
/// } ServerHello;
class ServerHello {
  final ProtocolVersion serverVersion;
  final DtlsRandom random;
  final Uint8List sessionId;
  final CipherSuite cipherSuite;
  final CompressionMethod compressionMethod;
  final List<Extension> extensions;

  ServerHello({
    required this.serverVersion,
    required this.random,
    required this.sessionId,
    required this.cipherSuite,
    required this.compressionMethod,
    List<Extension>? extensions,
  }) : extensions = extensions ?? [];

  /// Create a ServerHello response to ClientHello
  factory ServerHello.create({
    required Uint8List sessionId,
    required CipherSuite cipherSuite,
    List<Extension>? extensions,
  }) {
    return ServerHello(
      serverVersion: ProtocolVersion.dtls12,
      random: DtlsRandom.generate(),
      sessionId: sessionId,
      cipherSuite: cipherSuite,
      compressionMethod: CompressionMethod.none,
      extensions: extensions ?? [],
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    // Calculate total length
    var totalLength = 2 + // server_version
        32 + // random
        1 +
        sessionId.length + // session_id
        2 + // cipher_suite
        1; // compression_method

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

    // Server version (2 bytes)
    buffer.setUint8(offset, serverVersion.major);
    buffer.setUint8(offset + 1, serverVersion.minor);
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

    // Cipher suite (2 bytes)
    buffer.setUint16(offset, cipherSuite.value);
    offset += 2;

    // Compression method (1 byte)
    buffer.setUint8(offset, compressionMethod.value);
    offset++;

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
  static ServerHello parse(Uint8List data) {
    if (data.length < 38) {
      // Minimum: 2 (version) + 32 (random) + 1 (session_id len) + 2 (cipher_suite) + 1 (compression)
      throw FormatException('ServerHello too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // Server version (2 bytes)
    final serverVersion = ProtocolVersion(
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

    // Cipher suite
    final cipherSuiteValue = buffer.getUint16(offset);
    offset += 2;
    final cipherSuite = CipherSuite.fromValue(cipherSuiteValue);
    if (cipherSuite == null) {
      throw FormatException(
          'Unknown cipher suite: 0x${cipherSuiteValue.toRadixString(16)}');
    }

    // Compression method
    final compressionMethodValue = buffer.getUint8(offset);
    offset++;
    final compressionMethod =
        CompressionMethod.fromValue(compressionMethodValue);
    if (compressionMethod == null) {
      throw FormatException(
          'Unknown compression method: $compressionMethodValue');
    }

    // Extensions (optional)
    final extensions = <Extension>[];
    if (offset < data.length) {
      final extensionsLength = buffer.getUint16(offset);
      offset += 2;
      final extensionsData = data.sublist(offset, offset + extensionsLength);
      extensions.addAll(ExtensionParser.parseExtensions(extensionsData));
    }

    return ServerHello(
      serverVersion: serverVersion,
      random: random,
      sessionId: sessionId,
      cipherSuite: cipherSuite,
      compressionMethod: compressionMethod,
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
    return 'ServerHello(version=$serverVersion, suite=$cipherSuite, extensions=${extensions.length})';
  }
}
