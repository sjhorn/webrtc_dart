import 'dart:typed_data';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

/// RTCP Sender Report (SR)
/// RFC 3550 Section 6.4.1
///
/// Sender info block:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |            NTP timestamp, most significant word               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |            NTP timestamp, least significant word              |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                      RTP timestamp                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                      sender's packet count                    |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                       sender's octet count                    |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RtcpSenderReport {
  /// SSRC of sender
  final int ssrc;

  /// NTP timestamp (64-bit)
  final int ntpTimestamp;

  /// RTP timestamp
  final int rtpTimestamp;

  /// Sender's packet count
  final int packetCount;

  /// Sender's octet count
  final int octetCount;

  /// Reception report blocks
  final List<RtcpReceptionReportBlock> receptionReports;

  const RtcpSenderReport({
    required this.ssrc,
    required this.ntpTimestamp,
    required this.rtpTimestamp,
    required this.packetCount,
    required this.octetCount,
    this.receptionReports = const [],
  });

  /// Convert to RTCP packet
  RtcpPacket toPacket() {
    final payload = _serializePayload();
    final length = (payload.length ~/ 4) + 1; // Length in 32-bit words minus 1

    return RtcpPacket(
      reportCount: receptionReports.length,
      packetType: RtcpPacketType.senderReport,
      length: length,
      ssrc: ssrc,
      payload: payload,
    );
  }

  /// Serialize SR payload
  Uint8List _serializePayload() {
    final reportSize = 24 * receptionReports.length;
    final totalSize = 20 + reportSize; // Sender info (20) + reports
    final result = Uint8List(totalSize);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // NTP timestamp (64-bit)
    buffer.setUint32(offset, (ntpTimestamp >> 32) & 0xFFFFFFFF);
    offset += 4;
    buffer.setUint32(offset, ntpTimestamp & 0xFFFFFFFF);
    offset += 4;

    // RTP timestamp
    buffer.setUint32(offset, rtpTimestamp);
    offset += 4;

    // Packet count
    buffer.setUint32(offset, packetCount);
    offset += 4;

    // Octet count
    buffer.setUint32(offset, octetCount);
    offset += 4;

    // Reception reports
    for (final report in receptionReports) {
      final reportData = report.serialize();
      result.setRange(offset, offset + reportData.length, reportData);
      offset += reportData.length;
    }

    return result;
  }

  /// Parse SR from RTCP packet
  static RtcpSenderReport fromPacket(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.senderReport) {
      throw FormatException('Not a Sender Report packet');
    }

    if (packet.payload.length < 20) {
      throw FormatException('SR payload too short');
    }

    final buffer = ByteData.sublistView(packet.payload);
    var offset = 0;

    // NTP timestamp
    final ntpHigh = buffer.getUint32(offset);
    offset += 4;
    final ntpLow = buffer.getUint32(offset);
    offset += 4;
    final ntpTimestamp = (ntpHigh << 32) | ntpLow;

    // RTP timestamp
    final rtpTimestamp = buffer.getUint32(offset);
    offset += 4;

    // Packet count
    final packetCount = buffer.getUint32(offset);
    offset += 4;

    // Octet count
    final octetCount = buffer.getUint32(offset);
    offset += 4;

    // Reception reports
    final reports = <RtcpReceptionReportBlock>[];
    for (var i = 0; i < packet.reportCount; i++) {
      if (offset + 24 > packet.payload.length) break;
      final reportData = packet.payload.sublist(offset, offset + 24);
      reports.add(RtcpReceptionReportBlock.parse(reportData));
      offset += 24;
    }

    return RtcpSenderReport(
      ssrc: packet.ssrc,
      ntpTimestamp: ntpTimestamp,
      rtpTimestamp: rtpTimestamp,
      packetCount: packetCount,
      octetCount: octetCount,
      receptionReports: reports,
    );
  }

  @override
  String toString() {
    return 'RtcpSenderReport(ssrc=0x${ssrc.toRadixString(16)}, packets=$packetCount, octets=$octetCount, reports=${receptionReports.length})';
  }
}

/// RTCP Receiver Report (RR)
/// RFC 3550 Section 6.4.2
class RtcpReceiverReport {
  /// SSRC of receiver
  final int ssrc;

  /// Reception report blocks
  final List<RtcpReceptionReportBlock> receptionReports;

  const RtcpReceiverReport({
    required this.ssrc,
    required this.receptionReports,
  });

  /// Convert to RTCP packet
  RtcpPacket toPacket() {
    final payload = _serializePayload();
    final length = (payload.length ~/ 4) + 1;

    return RtcpPacket(
      reportCount: receptionReports.length,
      packetType: RtcpPacketType.receiverReport,
      length: length,
      ssrc: ssrc,
      payload: payload,
    );
  }

  /// Serialize RR payload
  Uint8List _serializePayload() {
    final totalSize = 24 * receptionReports.length;
    final result = Uint8List(totalSize);
    var offset = 0;

    for (final report in receptionReports) {
      final reportData = report.serialize();
      result.setRange(offset, offset + reportData.length, reportData);
      offset += reportData.length;
    }

    return result;
  }

  /// Parse RR from RTCP packet
  static RtcpReceiverReport fromPacket(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.receiverReport) {
      throw FormatException('Not a Receiver Report packet');
    }

    final reports = <RtcpReceptionReportBlock>[];
    var offset = 0;

    for (var i = 0; i < packet.reportCount; i++) {
      if (offset + 24 > packet.payload.length) break;
      final reportData = packet.payload.sublist(offset, offset + 24);
      reports.add(RtcpReceptionReportBlock.parse(reportData));
      offset += 24;
    }

    return RtcpReceiverReport(
      ssrc: packet.ssrc,
      receptionReports: reports,
    );
  }

  @override
  String toString() {
    return 'RtcpReceiverReport(ssrc=0x${ssrc.toRadixString(16)}, reports=${receptionReports.length})';
  }
}

/// RTCP Reception Report Block
/// RFC 3550 Section 6.4.1
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                 SSRC_n (SSRC of source n)                     |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// | fraction lost |       cumulative number of packets lost       |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |           extended highest sequence number received           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                      interarrival jitter                      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         last SR (LSR)                         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                   delay since last SR (DLSR)                  |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RtcpReceptionReportBlock {
  /// SSRC of source
  final int ssrc;

  /// Fraction lost (0-255)
  final int fractionLost;

  /// Cumulative packets lost
  final int cumulativeLost;

  /// Extended highest sequence number
  final int extendedHighestSequence;

  /// Interarrival jitter
  final int jitter;

  /// Last SR timestamp
  final int lastSr;

  /// Delay since last SR (in 1/65536 seconds)
  final int delaySinceLastSr;

  const RtcpReceptionReportBlock({
    required this.ssrc,
    required this.fractionLost,
    required this.cumulativeLost,
    required this.extendedHighestSequence,
    required this.jitter,
    required this.lastSr,
    required this.delaySinceLastSr,
  });

  /// Serialize reception report block (24 bytes)
  Uint8List serialize() {
    final result = Uint8List(24);
    final buffer = ByteData.sublistView(result);

    buffer.setUint32(0, ssrc);

    // Fraction lost (8 bits) + cumulative lost (24 bits)
    // Cumulative lost is 24-bit signed, so mask to 24 bits
    final cumulativeLost24 = cumulativeLost & 0xFFFFFF;
    buffer.setUint8(4, fractionLost & 0xFF);
    buffer.setUint8(5, (cumulativeLost24 >> 16) & 0xFF);
    buffer.setUint8(6, (cumulativeLost24 >> 8) & 0xFF);
    buffer.setUint8(7, cumulativeLost24 & 0xFF);

    buffer.setUint32(8, extendedHighestSequence);
    buffer.setUint32(12, jitter);
    buffer.setUint32(16, lastSr);
    buffer.setUint32(20, delaySinceLastSr);

    return result;
  }

  /// Parse reception report block
  static RtcpReceptionReportBlock parse(Uint8List data) {
    if (data.length < 24) {
      throw FormatException('Reception report block too short');
    }

    final buffer = ByteData.sublistView(data);

    final ssrc = buffer.getUint32(0);
    final fractionLost = buffer.getUint8(4);

    // Cumulative lost is 24 bits (signed)
    var cumulativeLost = (buffer.getUint8(5) << 16) |
        (buffer.getUint8(6) << 8) |
        buffer.getUint8(7);
    // Convert to signed if necessary (sign extend from 24-bit to 64-bit)
    if (cumulativeLost & 0x800000 != 0) {
      // Negative number - sign extend to full int
      cumulativeLost -= 0x1000000; // Convert from 24-bit two's complement
    }

    final extendedHighestSequence = buffer.getUint32(8);
    final jitter = buffer.getUint32(12);
    final lastSr = buffer.getUint32(16);
    final delaySinceLastSr = buffer.getUint32(20);

    return RtcpReceptionReportBlock(
      ssrc: ssrc,
      fractionLost: fractionLost,
      cumulativeLost: cumulativeLost,
      extendedHighestSequence: extendedHighestSequence,
      jitter: jitter,
      lastSr: lastSr,
      delaySinceLastSr: delaySinceLastSr,
    );
  }

  @override
  String toString() {
    return 'RtcpReceptionReportBlock(ssrc=0x${ssrc.toRadixString(16)}, lost=$cumulativeLost, jitter=$jitter)';
  }
}
