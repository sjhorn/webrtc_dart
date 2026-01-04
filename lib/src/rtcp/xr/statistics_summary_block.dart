import 'dart:typed_data';

import 'xr_block.dart';

/// Statistics Summary Report Block
/// RFC 3611 Section 4.6
///
/// Provides aggregate statistics for a sequence number range.
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |     BT=6      |L|D|J|ToH|rsvd.|       block length = 9        |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        SSRC of source                         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |          begin_seq            |             end_seq           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        lost_packets                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        dup_packets                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         min_jitter                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         max_jitter                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        mean_jitter                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        dev_jitter                             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |     min_ttl   |     max_ttl   |    mean_ttl   |    dev_ttl    |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class StatisticsSummaryBlock extends XrBlock {
  /// Flags
  final bool lossReportFlag; // L: lost_packets field is valid
  final bool duplicateReportFlag; // D: dup_packets field is valid
  final bool jitterFlag; // J: jitter fields are valid
  final int ttlOrHopLimit; // ToH: 0=none, 1=IPv4 TTL, 2=IPv6 Hop Limit, 3=both

  /// SSRC of the source being reported
  final int ssrcOfSource;

  /// Sequence number range
  final int beginSeq;
  final int endSeq;

  /// Lost packets count
  final int lostPackets;

  /// Duplicate packets count
  final int dupPackets;

  /// Jitter statistics (in RTP timestamp units)
  final int minJitter;
  final int maxJitter;
  final int meanJitter;
  final int devJitter;

  /// TTL/Hop Limit statistics
  final int minTtl;
  final int maxTtl;
  final int meanTtl;
  final int devTtl;

  /// Block size: 4 (header) + 36 (data) = 40 bytes
  static const int blockSize = 40;

  /// Block length in 32-bit words (excluding header)
  static const int blockLengthWords = 9;

  StatisticsSummaryBlock({
    this.lossReportFlag = true,
    this.duplicateReportFlag = true,
    this.jitterFlag = true,
    this.ttlOrHopLimit = 0,
    required this.ssrcOfSource,
    required this.beginSeq,
    required this.endSeq,
    this.lostPackets = 0,
    this.dupPackets = 0,
    this.minJitter = 0,
    this.maxJitter = 0,
    this.meanJitter = 0,
    this.devJitter = 0,
    this.minTtl = 0,
    this.maxTtl = 0,
    this.meanTtl = 0,
    this.devTtl = 0,
  });

  @override
  XrBlockType get blockType => XrBlockType.statisticsSummary;

  @override
  Uint8List serialize() {
    final result = Uint8List(blockSize);
    final buffer = ByteData.sublistView(result);

    // Build type-specific byte
    var typeSpecific = 0;
    if (lossReportFlag) typeSpecific |= 0x80;
    if (duplicateReportFlag) typeSpecific |= 0x40;
    if (jitterFlag) typeSpecific |= 0x20;
    typeSpecific |= ((ttlOrHopLimit & 0x03) << 3);

    // Header
    XrBlock.writeHeader(
        buffer, 0, XrBlockType.statisticsSummary, typeSpecific, blockLengthWords);

    // SSRC of source
    buffer.setUint32(4, ssrcOfSource);

    // Sequence range
    buffer.setUint16(8, beginSeq);
    buffer.setUint16(10, endSeq);

    // Packet counts
    buffer.setUint32(12, lostPackets);
    buffer.setUint32(16, dupPackets);

    // Jitter stats
    buffer.setUint32(20, minJitter);
    buffer.setUint32(24, maxJitter);
    buffer.setUint32(28, meanJitter);
    buffer.setUint32(32, devJitter);

    // TTL stats
    buffer.setUint8(36, minTtl);
    buffer.setUint8(37, maxTtl);
    buffer.setUint8(38, meanTtl);
    buffer.setUint8(39, devTtl);

    return result;
  }

  /// Parse from bytes
  static StatisticsSummaryBlock? parse(Uint8List data) {
    if (data.length < blockSize) return null;

    final buffer = ByteData.sublistView(data);

    // Verify block type
    final bt = buffer.getUint8(0);
    if (bt != XrBlockType.statisticsSummary.value) return null;

    // Parse type-specific byte
    final typeSpecific = buffer.getUint8(1);
    final lossReportFlag = (typeSpecific & 0x80) != 0;
    final duplicateReportFlag = (typeSpecific & 0x40) != 0;
    final jitterFlag = (typeSpecific & 0x20) != 0;
    final ttlOrHopLimit = (typeSpecific >> 3) & 0x03;

    // Verify block length
    final blockLength = buffer.getUint16(2);
    if (blockLength != blockLengthWords) return null;

    return StatisticsSummaryBlock(
      lossReportFlag: lossReportFlag,
      duplicateReportFlag: duplicateReportFlag,
      jitterFlag: jitterFlag,
      ttlOrHopLimit: ttlOrHopLimit,
      ssrcOfSource: buffer.getUint32(4),
      beginSeq: buffer.getUint16(8),
      endSeq: buffer.getUint16(10),
      lostPackets: buffer.getUint32(12),
      dupPackets: buffer.getUint32(16),
      minJitter: buffer.getUint32(20),
      maxJitter: buffer.getUint32(24),
      meanJitter: buffer.getUint32(28),
      devJitter: buffer.getUint32(32),
      minTtl: buffer.getUint8(36),
      maxTtl: buffer.getUint8(37),
      meanTtl: buffer.getUint8(38),
      devTtl: buffer.getUint8(39),
    );
  }

  @override
  String toString() {
    return 'StatisticsSummaryBlock(ssrc=0x${ssrcOfSource.toRadixString(16)}, '
        'seq=$beginSeq-$endSeq, lost=$lostPackets, dup=$dupPackets)';
  }
}
