import 'dart:typed_data';

import 'xr_block.dart';

/// DLRR Sub-Block
/// RFC 3611 Section 4.5
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         SSRC_i                                |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         LRR (i)                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         DLRR (i)                              |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class DlrrSubBlock {
  /// SSRC of receiver that sent the RRTR
  final int ssrc;

  /// Last Receiver Report timestamp (middle 32 bits of NTP from RRTR)
  final int lastRr;

  /// Delay since Last RR (in 1/65536 seconds)
  final int delaySinceLastRr;

  /// Sub-block size: 12 bytes
  static const int subBlockSize = 12;

  const DlrrSubBlock({
    required this.ssrc,
    required this.lastRr,
    required this.delaySinceLastRr,
  });

  /// Create from timestamps
  factory DlrrSubBlock.fromTimestamps({
    required int ssrc,
    required int rrtrNtpMiddle32,
    required Duration delay,
  }) {
    // Convert delay to 1/65536 seconds
    final delayUnits = (delay.inMicroseconds * 65536 ~/ 1000000);
    return DlrrSubBlock(
      ssrc: ssrc,
      lastRr: rrtrNtpMiddle32,
      delaySinceLastRr: delayUnits,
    );
  }

  /// Get delay as Duration
  Duration get delay =>
      Duration(microseconds: delaySinceLastRr * 1000000 ~/ 65536);

  void serialize(ByteData buffer, int offset) {
    buffer.setUint32(offset, ssrc);
    buffer.setUint32(offset + 4, lastRr);
    buffer.setUint32(offset + 8, delaySinceLastRr);
  }

  static DlrrSubBlock parse(ByteData buffer, int offset) {
    return DlrrSubBlock(
      ssrc: buffer.getUint32(offset),
      lastRr: buffer.getUint32(offset + 4),
      delaySinceLastRr: buffer.getUint32(offset + 8),
    );
  }

  @override
  String toString() {
    return 'DlrrSubBlock(ssrc=0x${ssrc.toRadixString(16)}, lrr=0x${lastRr.toRadixString(16)}, dlrr=$delaySinceLastRr)';
  }
}

/// DLRR Report Block (Delay since Last Receiver Report)
/// RFC 3611 Section 4.5
///
/// Sent by RTP sender in response to RRTR blocks from receivers.
/// Enables receivers to calculate RTT.
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |     BT=5      |   reserved    |         block length          |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                 DLRR Sub-block 1 (12 bytes)                   |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// :                              ...                              :
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class DlrrBlock extends XrBlock {
  /// List of DLRR sub-blocks
  final List<DlrrSubBlock> subBlocks;

  DlrrBlock(this.subBlocks);

  @override
  XrBlockType get blockType => XrBlockType.dlrr;

  /// Block length in 32-bit words (excluding header)
  int get blockLengthWords => subBlocks.length * 3; // 12 bytes = 3 words each

  /// Total size in bytes
  int get size => XrBlock.headerSize + (subBlocks.length * DlrrSubBlock.subBlockSize);

  @override
  Uint8List serialize() {
    final result = Uint8List(size);
    final buffer = ByteData.sublistView(result);

    // Header
    XrBlock.writeHeader(buffer, 0, XrBlockType.dlrr, 0, blockLengthWords);

    // Sub-blocks
    var offset = XrBlock.headerSize;
    for (final subBlock in subBlocks) {
      subBlock.serialize(buffer, offset);
      offset += DlrrSubBlock.subBlockSize;
    }

    return result;
  }

  /// Parse from bytes
  static DlrrBlock? parse(Uint8List data) {
    if (data.length < XrBlock.headerSize) return null;

    final buffer = ByteData.sublistView(data);

    // Verify block type
    final bt = buffer.getUint8(0);
    if (bt != XrBlockType.dlrr.value) return null;

    // Get block length
    final blockLength = buffer.getUint16(2);
    final totalSize = XrBlock.headerSize + (blockLength * 4);

    if (data.length < totalSize) return null;

    // Parse sub-blocks (block length should be multiple of 3 words)
    if (blockLength % 3 != 0) return null;

    final subBlocks = <DlrrSubBlock>[];
    var offset = XrBlock.headerSize;
    final numSubBlocks = blockLength ~/ 3;

    for (var i = 0; i < numSubBlocks; i++) {
      subBlocks.add(DlrrSubBlock.parse(buffer, offset));
      offset += DlrrSubBlock.subBlockSize;
    }

    return DlrrBlock(subBlocks);
  }

  @override
  String toString() {
    return 'DlrrBlock(${subBlocks.length} sub-blocks)';
  }
}
