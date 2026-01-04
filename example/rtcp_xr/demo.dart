/// RTCP Extended Reports (XR) - RFC 3611 Demonstration
///
/// This example shows how to create, serialize, and parse RTCP XR packets
/// for advanced QoS metrics reporting.
///
/// Usage: dart run example/rtcp_xr/demo.dart
library;

import 'dart:typed_data';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() {
  print('=== RTCP Extended Reports (XR) Demo ===\n');

  // 1. Create a Receiver Reference Time Report (RRTR) block
  print('1. Receiver Reference Time Report (RRTR):');
  final rrtr = ReceiverReferenceTimeBlock.now();
  print('   NTP Timestamp MSW: 0x${rrtr.ntpTimestampMsw.toRadixString(16)}');
  print('   NTP Timestamp LSW: 0x${rrtr.ntpTimestampLsw.toRadixString(16)}');
  print('   Middle 32 bits: 0x${rrtr.ntpMiddle32.toRadixString(16)}');
  print('');

  // 2. Create a DLRR (Delay since Last Receiver Report) block
  print('2. DLRR (Delay since Last Receiver Report):');
  final dlrr = DlrrBlock([
    DlrrSubBlock.fromTimestamps(
      ssrc: 0x12345678,
      rrtrNtpMiddle32: rrtr.ntpMiddle32,
      delay: Duration(milliseconds: 50),
    ),
    DlrrSubBlock.fromTimestamps(
      ssrc: 0xABCDEF01,
      rrtrNtpMiddle32: 0x11223344,
      delay: Duration(milliseconds: 100),
    ),
  ]);
  print('   Sub-blocks: ${dlrr.subBlocks.length}');
  for (final sub in dlrr.subBlocks) {
    print('   - SSRC: 0x${sub.ssrc.toRadixString(16)}, '
        'delay: ${sub.delay.inMilliseconds}ms');
  }
  print('');

  // 3. Create a Statistics Summary block
  print('3. Statistics Summary:');
  final stats = StatisticsSummaryBlock(
    ssrcOfSource: 0x12345678,
    beginSeq: 1000,
    endSeq: 2000,
    lostPackets: 15,
    dupPackets: 2,
    minJitter: 50,
    maxJitter: 200,
    meanJitter: 100,
    devJitter: 30,
  );
  print('   SSRC: 0x${stats.ssrcOfSource.toRadixString(16)}');
  print('   Sequence range: ${stats.beginSeq} - ${stats.endSeq}');
  print('   Lost packets: ${stats.lostPackets}');
  print('   Duplicate packets: ${stats.dupPackets}');
  print('   Jitter (min/max/mean/dev): '
      '${stats.minJitter}/${stats.maxJitter}/${stats.meanJitter}/${stats.devJitter}');
  print('');

  // 4. Create an XR packet with multiple blocks
  print('4. Complete XR Packet:');
  final xr = RtcpExtendedReport(
    ssrc: 0xDEADBEEF,
    blocks: [rrtr, dlrr, stats],
  );
  print('   SSRC: 0x${xr.ssrc.toRadixString(16)}');
  print('   Blocks: ${xr.blocks.length}');
  print('');

  // 5. Serialize to bytes
  final bytes = xr.serialize();
  print('5. Serialized XR Packet:');
  print('   Size: ${bytes.length} bytes');
  print('   Hex: ${_bytesToHex(bytes.sublist(0, 20))}...');
  print('');

  // 6. Parse back from bytes
  print('6. Parse XR from bytes:');
  final rtcpPacket = RtcpPacket.parse(bytes);
  print('   RTCP Type: ${rtcpPacket.packetType}');

  final parsedXr = RtcpExtendedReport.fromPacket(rtcpPacket);
  if (parsedXr != null) {
    print('   Parsed SSRC: 0x${parsedXr.ssrc.toRadixString(16)}');
    print('   Parsed blocks: ${parsedXr.blocks.length}');

    // Filter blocks by type
    final rrtrBlocks = parsedXr.blocksOfType<ReceiverReferenceTimeBlock>();
    final dlrrBlocks = parsedXr.blocksOfType<DlrrBlock>();
    final statsBlocks = parsedXr.blocksOfType<StatisticsSummaryBlock>();

    print('   - RRTR blocks: ${rrtrBlocks.length}');
    print('   - DLRR blocks: ${dlrrBlocks.length}');
    print('   - Stats blocks: ${statsBlocks.length}');
  }
  print('');

  // 7. XR in compound RTCP packet
  print('7. XR in Compound RTCP Packet:');
  final sr = RtcpPacket(
    reportCount: 0,
    packetType: RtcpPacketType.senderReport,
    length: 6,
    ssrc: 0x11111111,
    payload: Uint8List(20), // SR payload
  );

  final compound = RtcpCompoundPacket([sr, xr.toRtcpPacket()]);
  final compoundBytes = compound.serialize();
  print('   Compound size: ${compoundBytes.length} bytes');

  final parsedCompound = RtcpCompoundPacket.parse(compoundBytes);
  print('   Packets in compound: ${parsedCompound.packets.length}');
  for (final pkt in parsedCompound.packets) {
    print('   - ${pkt.packetType}');
  }

  print('\n=== Demo Complete ===');
}

String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
