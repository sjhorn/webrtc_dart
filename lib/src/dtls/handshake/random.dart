import 'dart:typed_data';
import 'package:webrtc_dart/src/common/crypto.dart' as crypto;

/// TLS/DTLS Random value (32 bytes)
/// RFC 5246 Section 7.4.1.2
///
/// struct {
///   uint32 gmt_unix_time;
///   opaque random_bytes[28];
/// } Random;
class DtlsRandom {
  /// GMT Unix time (4 bytes)
  final int gmtUnixTime;

  /// Random bytes (28 bytes)
  final Uint8List randomBytes;

  const DtlsRandom({
    required this.gmtUnixTime,
    required this.randomBytes,
  });

  /// Generate a new random value with current timestamp
  factory DtlsRandom.generate() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final random = crypto.randomBytes(28);
    return DtlsRandom(
      gmtUnixTime: now,
      randomBytes: random,
    );
  }

  /// Parse from 32-byte buffer
  factory DtlsRandom.fromBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError('Random must be exactly 32 bytes, got ${bytes.length}');
    }

    final buffer = ByteData.sublistView(bytes);
    final gmtUnixTime = buffer.getUint32(0);
    final randomBytes = bytes.sublist(4, 32);

    return DtlsRandom(
      gmtUnixTime: gmtUnixTime,
      randomBytes: randomBytes,
    );
  }

  /// Serialize to 32-byte buffer
  Uint8List toBytes() {
    final result = Uint8List(32);
    final buffer = ByteData.sublistView(result);

    // Write GMT Unix time (4 bytes)
    buffer.setUint32(0, gmtUnixTime);

    // Write random bytes (28 bytes)
    result.setRange(4, 32, randomBytes);

    return result;
  }

  /// Get the full 32-byte random value
  Uint8List get bytes => toBytes();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DtlsRandom) return false;

    return gmtUnixTime == other.gmtUnixTime &&
        _bytesEqual(randomBytes, other.randomBytes);
  }

  @override
  int get hashCode => Object.hash(gmtUnixTime, randomBytes);

  @override
  String toString() {
    return 'DtlsRandom(time=$gmtUnixTime, random=${randomBytes.length} bytes)';
  }

  /// Compare two byte arrays for equality
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
