import 'dart:typed_data';

/// Picture Loss Indication (PLI)
/// RFC 4585 Section 6.3.1
///
/// Payload-Specific Feedback message used to request a keyframe
/// when packet loss or corruption has occurred.
///
/// Simpler alternative to FIR (Full Intra Request) for requesting keyframes.
class PictureLossIndication {
  /// FMT (Feedback Message Type) value for PLI in PSFB packets
  static const int fmt = 1;

  /// Fixed length in 32-bit words (8 bytes / 4 = 2)
  static const int length = 2;

  /// SSRC of the PLI sender (receiver reporting loss)
  final int senderSsrc;

  /// SSRC of the media stream with loss
  final int mediaSsrc;

  const PictureLossIndication({
    required this.senderSsrc,
    required this.mediaSsrc,
  });

  /// Serialize PLI to bytes
  ///
  /// Format (8 bytes total):
  ///  0                   1                   2                   3
  ///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                    Sender SSRC (32 bits)                      |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                     Media SSRC (32 bits)                      |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  Uint8List serialize() {
    final buffer = ByteData(8);
    buffer.setUint32(0, senderSsrc);
    buffer.setUint32(4, mediaSsrc);
    return buffer.buffer.asUint8List();
  }

  /// Deserialize PLI from bytes
  static PictureLossIndication deserialize(Uint8List data) {
    if (data.length < 8) {
      throw ArgumentError(
          'PLI data too short: ${data.length} bytes, expected 8');
    }

    final buffer = ByteData.view(data.buffer, data.offsetInBytes);
    final senderSsrc = buffer.getUint32(0);
    final mediaSsrc = buffer.getUint32(4);

    return PictureLossIndication(
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
    );
  }

  @override
  String toString() {
    return 'PictureLossIndication(sender: 0x${senderSsrc.toRadixString(16)}, '
        'media: 0x${mediaSsrc.toRadixString(16)})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PictureLossIndication &&
          runtimeType == other.runtimeType &&
          senderSsrc == other.senderSsrc &&
          mediaSsrc == other.mediaSsrc;

  @override
  int get hashCode => Object.hash(senderSsrc, mediaSsrc);
}
