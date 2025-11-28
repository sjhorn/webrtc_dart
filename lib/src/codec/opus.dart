import 'dart:typed_data';

/// Opus RTP Payload
/// RFC 7587 - RTP Payload Format for the Opus Speech and Audio Codec
///
/// This implementation handles RTP payload framing for Opus.
/// Actual audio encoding/decoding should be done by external tools
/// (e.g., FFmpeg, opus_dart package) or platform-specific codecs.
class OpusRtpPayload {
  /// Raw Opus payload data
  final Uint8List payload;

  OpusRtpPayload({required this.payload});

  /// Deserialize from RTP payload
  /// For Opus, the entire RTP payload is the Opus frame
  static OpusRtpPayload deserialize(Uint8List buffer) {
    return OpusRtpPayload(payload: buffer);
  }

  /// Serialize to RTP payload
  Uint8List serialize() {
    return payload;
  }

  /// Opus frames are always considered keyframes for RTP purposes
  bool get isKeyframe => true;

  /// Create Opus codec private data for container formats (e.g., WebM)
  /// This generates the OpusHead identification header
  static Uint8List createCodecPrivate({int samplingFrequency = 48000}) {
    final result = Uint8List(19);
    final view = ByteData.sublistView(result);

    // Magic signature "OpusHead"
    result.setRange(0, 8, 'OpusHead'.codeUnits);

    // Version (1 byte) = 1
    result[8] = 1;

    // Channel count (1 byte) = 2 (stereo)
    result[9] = 2;

    // Pre-skip (2 bytes, little-endian) = 312 samples
    view.setUint16(10, 312, Endian.little);

    // Input sample rate (4 bytes, little-endian)
    view.setUint32(12, samplingFrequency, Endian.little);

    // Output gain (2 bytes, little-endian) = 0 (no gain)
    view.setUint16(16, 0, Endian.little);

    // Channel mapping family (1 byte) = 0 (mono or stereo)
    result[18] = 0;

    return result;
  }

  @override
  String toString() {
    return 'OpusRtpPayload(size=${payload.length})';
  }
}
