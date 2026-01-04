import 'dart:typed_data';

/// RTCP XR Block Types
/// RFC 3611 Section 4
enum XrBlockType {
  lossRle(1),
  duplicateRle(2),
  packetReceiptTimes(3),
  receiverReferenceTime(4), // RRTR
  dlrr(5),
  statisticsSummary(6),
  voipMetrics(7);

  final int value;
  const XrBlockType(this.value);

  static XrBlockType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Base class for RTCP XR Report Blocks
/// RFC 3611 Section 3
///
/// Block header format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |      BT       |type-specific  |         block length          |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
abstract class XrBlock {
  /// Block type identifier
  XrBlockType get blockType;

  /// Serialize block to bytes (including 4-byte header)
  Uint8List serialize();

  /// Block header size in bytes
  static const int headerSize = 4;

  /// Helper to write block header
  static void writeHeader(
      ByteData buffer, int offset, XrBlockType type, int typeSpecific, int blockLength) {
    buffer.setUint8(offset, type.value);
    buffer.setUint8(offset + 1, typeSpecific);
    buffer.setUint16(offset + 2, blockLength);
  }

}
