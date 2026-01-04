import 'dart:typed_data';

import 'xr_block.dart';

/// Receiver Reference Time Report Block (RRTR)
/// RFC 3611 Section 4.4
///
/// Enables RTT measurement for receivers that don't send RTP (SR).
/// The receiver sends this block, and the sender responds with DLRR.
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |     BT=4      |   reserved    |       block length = 2        |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |              NTP timestamp, most significant word             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |             NTP timestamp, least significant word             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class ReceiverReferenceTimeBlock extends XrBlock {
  /// NTP timestamp (64-bit) - most significant word
  final int ntpTimestampMsw;

  /// NTP timestamp (64-bit) - least significant word
  final int ntpTimestampLsw;

  /// Block size: 4 (header) + 8 (NTP) = 12 bytes
  static const int blockSize = 12;

  /// Block length in 32-bit words (excluding header)
  static const int blockLengthWords = 2;

  ReceiverReferenceTimeBlock({
    required this.ntpTimestampMsw,
    required this.ntpTimestampLsw,
  });

  /// Create from a 64-bit NTP timestamp
  factory ReceiverReferenceTimeBlock.fromNtpTimestamp(int ntpTimestamp) {
    return ReceiverReferenceTimeBlock(
      ntpTimestampMsw: (ntpTimestamp >> 32) & 0xFFFFFFFF,
      ntpTimestampLsw: ntpTimestamp & 0xFFFFFFFF,
    );
  }

  /// Create from current time
  factory ReceiverReferenceTimeBlock.now() {
    final now = DateTime.now();
    // NTP epoch is Jan 1, 1900; Unix epoch is Jan 1, 1970
    // Difference is 2208988800 seconds
    const ntpUnixDiff = 2208988800;
    final seconds = (now.millisecondsSinceEpoch ~/ 1000) + ntpUnixDiff;
    final fraction =
        ((now.millisecondsSinceEpoch % 1000) * 0x100000000 ~/ 1000);
    return ReceiverReferenceTimeBlock(
      ntpTimestampMsw: seconds,
      ntpTimestampLsw: fraction,
    );
  }

  @override
  XrBlockType get blockType => XrBlockType.receiverReferenceTime;

  /// Get full 64-bit NTP timestamp
  int get ntpTimestamp => (ntpTimestampMsw << 32) | ntpTimestampLsw;

  /// Get middle 32 bits of NTP timestamp (used in DLRR)
  int get ntpMiddle32 =>
      ((ntpTimestampMsw & 0xFFFF) << 16) | ((ntpTimestampLsw >> 16) & 0xFFFF);

  @override
  Uint8List serialize() {
    final result = Uint8List(blockSize);
    final buffer = ByteData.sublistView(result);

    // Header
    XrBlock.writeHeader(
        buffer, 0, XrBlockType.receiverReferenceTime, 0, blockLengthWords);

    // NTP timestamp
    buffer.setUint32(4, ntpTimestampMsw);
    buffer.setUint32(8, ntpTimestampLsw);

    return result;
  }

  /// Parse from bytes
  static ReceiverReferenceTimeBlock? parse(Uint8List data) {
    if (data.length < blockSize) return null;

    final buffer = ByteData.sublistView(data);

    // Verify block type
    final bt = buffer.getUint8(0);
    if (bt != XrBlockType.receiverReferenceTime.value) return null;

    // Verify block length
    final blockLength = buffer.getUint16(2);
    if (blockLength != blockLengthWords) return null;

    return ReceiverReferenceTimeBlock(
      ntpTimestampMsw: buffer.getUint32(4),
      ntpTimestampLsw: buffer.getUint32(8),
    );
  }

  @override
  String toString() {
    return 'ReceiverReferenceTimeBlock(ntp=0x${ntpTimestamp.toRadixString(16)})';
  }
}
