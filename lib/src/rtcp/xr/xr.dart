import 'dart:typed_data';

import '../../srtp/rtcp_packet.dart';
import 'dlrr_block.dart';
import 'rrtr_block.dart';
import 'statistics_summary_block.dart';
import 'xr_block.dart';

export 'dlrr_block.dart';
export 'rrtr_block.dart';
export 'statistics_summary_block.dart';
export 'xr_block.dart';

/// RTCP Extended Report (XR) Packet
/// RFC 3611
///
/// Provides extended reporting capabilities beyond standard RTCP.
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|reserved |   PT=207      |             length            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                              SSRC                             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// :                         report blocks                         :
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RtcpExtendedReport {
  /// SSRC of the sender generating this XR packet
  final int ssrc;

  /// Report blocks
  final List<XrBlock> blocks;

  RtcpExtendedReport({
    required this.ssrc,
    required this.blocks,
  });

  /// Create from an RtcpPacket
  static RtcpExtendedReport? fromPacket(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.extendedReport) {
      return null;
    }

    final blocks = <XrBlock>[];
    final payload = packet.payload;
    var offset = 0;

    while (offset < payload.length) {
      if (payload.length - offset < XrBlock.headerSize) break;

      // Read block length from header
      final buffer = ByteData.sublistView(payload, offset);
      final blockLength = buffer.getUint16(2);
      final totalBlockSize = XrBlock.headerSize + (blockLength * 4);

      if (offset + totalBlockSize > payload.length) break;

      final blockData = payload.sublist(offset, offset + totalBlockSize);
      final block = _parseBlock(blockData);
      if (block != null) {
        blocks.add(block);
      }

      offset += totalBlockSize;
    }

    return RtcpExtendedReport(
      ssrc: packet.ssrc,
      blocks: blocks,
    );
  }

  /// Parse a single block from bytes
  static XrBlock? _parseBlock(Uint8List data) {
    if (data.length < XrBlock.headerSize) return null;

    final bt = data[0];
    final blockType = XrBlockType.fromValue(bt);

    if (blockType == null) return null;

    switch (blockType) {
      case XrBlockType.receiverReferenceTime:
        return ReceiverReferenceTimeBlock.parse(data);
      case XrBlockType.dlrr:
        return DlrrBlock.parse(data);
      case XrBlockType.statisticsSummary:
        return StatisticsSummaryBlock.parse(data);
      default:
        return null; // Unsupported block type
    }
  }

  /// Convert to RtcpPacket
  RtcpPacket toRtcpPacket() {
    // Serialize all blocks
    final blockBytes = <Uint8List>[];
    var totalPayloadSize = 0;

    for (final block in blocks) {
      final serialized = block.serialize();
      blockBytes.add(serialized);
      totalPayloadSize += serialized.length;
    }

    // Build payload
    final payload = Uint8List(totalPayloadSize);
    var offset = 0;
    for (final bytes in blockBytes) {
      payload.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
    }

    // Calculate length field (total packet size in 32-bit words minus 1)
    // Total = 8 (header) + payload
    final totalSize = RtcpPacket.headerSize + payload.length;
    final length = (totalSize ~/ 4) - 1;

    return RtcpPacket(
      reportCount: 0, // reserved for XR
      packetType: RtcpPacketType.extendedReport,
      length: length,
      ssrc: ssrc,
      payload: payload,
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    return toRtcpPacket().serialize();
  }

  /// Get blocks of a specific type
  List<T> blocksOfType<T extends XrBlock>() {
    return blocks.whereType<T>().toList();
  }

  @override
  String toString() {
    return 'RtcpExtendedReport(ssrc=0x${ssrc.toRadixString(16)}, ${blocks.length} blocks)';
  }
}
