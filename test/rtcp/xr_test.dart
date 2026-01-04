import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/xr/xr.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('XrBlockType', () {
    test('enum values have correct codes', () {
      expect(XrBlockType.lossRle.value, equals(1));
      expect(XrBlockType.duplicateRle.value, equals(2));
      expect(XrBlockType.packetReceiptTimes.value, equals(3));
      expect(XrBlockType.receiverReferenceTime.value, equals(4));
      expect(XrBlockType.dlrr.value, equals(5));
      expect(XrBlockType.statisticsSummary.value, equals(6));
      expect(XrBlockType.voipMetrics.value, equals(7));
    });

    test('fromValue returns correct type', () {
      expect(XrBlockType.fromValue(4),
          equals(XrBlockType.receiverReferenceTime));
      expect(XrBlockType.fromValue(5), equals(XrBlockType.dlrr));
      expect(XrBlockType.fromValue(6), equals(XrBlockType.statisticsSummary));
    });

    test('fromValue returns null for unknown values', () {
      expect(XrBlockType.fromValue(0), isNull);
      expect(XrBlockType.fromValue(100), isNull);
    });
  });

  group('ReceiverReferenceTimeBlock', () {
    test('serialize creates correct bytes', () {
      final block = ReceiverReferenceTimeBlock(
        ntpTimestampMsw: 0x12345678,
        ntpTimestampLsw: 0xABCDEF01,
      );

      final bytes = block.serialize();

      expect(bytes.length, equals(12));
      expect(bytes[0], equals(4)); // BT=4
      expect(bytes[1], equals(0)); // reserved
      expect(bytes[2], equals(0)); // block length high
      expect(bytes[3], equals(2)); // block length low = 2
      // NTP MSW
      expect(bytes[4], equals(0x12));
      expect(bytes[5], equals(0x34));
      expect(bytes[6], equals(0x56));
      expect(bytes[7], equals(0x78));
      // NTP LSW
      expect(bytes[8], equals(0xAB));
      expect(bytes[9], equals(0xCD));
      expect(bytes[10], equals(0xEF));
      expect(bytes[11], equals(0x01));
    });

    test('parse creates correct block', () {
      final data = Uint8List.fromList([
        4, 0, 0, 2, // header: BT=4, reserved, length=2
        0x12, 0x34, 0x56, 0x78, // NTP MSW
        0xAB, 0xCD, 0xEF, 0x01, // NTP LSW
      ]);

      final block = ReceiverReferenceTimeBlock.parse(data);

      expect(block, isNotNull);
      expect(block!.ntpTimestampMsw, equals(0x12345678));
      expect(block.ntpTimestampLsw, equals(0xABCDEF01));
    });

    test('roundtrip serialize/parse', () {
      final original = ReceiverReferenceTimeBlock(
        ntpTimestampMsw: 0xDEADBEEF,
        ntpTimestampLsw: 0xCAFEBABE,
      );

      final bytes = original.serialize();
      final parsed = ReceiverReferenceTimeBlock.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.ntpTimestampMsw, equals(original.ntpTimestampMsw));
      expect(parsed.ntpTimestampLsw, equals(original.ntpTimestampLsw));
    });

    test('ntpMiddle32 extracts correct bits', () {
      // NTP MSW = 0x12345678, LSW = 0xABCDEF01
      // Middle 32 = (0x5678 << 16) | 0xABCD = 0x5678ABCD
      final block = ReceiverReferenceTimeBlock(
        ntpTimestampMsw: 0x12345678,
        ntpTimestampLsw: 0xABCDEF01,
      );

      expect(block.ntpMiddle32, equals(0x5678ABCD));
    });

    test('fromNtpTimestamp creates correct block', () {
      final block =
          ReceiverReferenceTimeBlock.fromNtpTimestamp(0x123456789ABCDEF0);

      expect(block.ntpTimestampMsw, equals(0x12345678));
      expect(block.ntpTimestampLsw, equals(0x9ABCDEF0));
    });

    test('now() creates block with current time', () {
      final block = ReceiverReferenceTimeBlock.now();

      // Just verify it creates something reasonable
      expect(block.ntpTimestampMsw, greaterThan(0));
    });

    test('blockType returns receiverReferenceTime', () {
      final block = ReceiverReferenceTimeBlock(
        ntpTimestampMsw: 0,
        ntpTimestampLsw: 0,
      );

      expect(block.blockType, equals(XrBlockType.receiverReferenceTime));
    });
  });

  group('DlrrSubBlock', () {
    test('serialize creates correct bytes', () {
      final subBlock = DlrrSubBlock(
        ssrc: 0x12345678,
        lastRr: 0xABCDEF01,
        delaySinceLastRr: 0x11223344,
      );

      final buffer = ByteData(12);
      subBlock.serialize(buffer, 0);
      final bytes = buffer.buffer.asUint8List();

      expect(bytes[0], equals(0x12));
      expect(bytes[1], equals(0x34));
      expect(bytes[2], equals(0x56));
      expect(bytes[3], equals(0x78));
      expect(bytes[4], equals(0xAB));
      expect(bytes[5], equals(0xCD));
      expect(bytes[6], equals(0xEF));
      expect(bytes[7], equals(0x01));
      expect(bytes[8], equals(0x11));
      expect(bytes[9], equals(0x22));
      expect(bytes[10], equals(0x33));
      expect(bytes[11], equals(0x44));
    });

    test('parse creates correct sub-block', () {
      final data = Uint8List.fromList([
        0x12, 0x34, 0x56, 0x78, // SSRC
        0xAB, 0xCD, 0xEF, 0x01, // LRR
        0x11, 0x22, 0x33, 0x44, // DLRR
      ]);
      final buffer = ByteData.sublistView(data);

      final subBlock = DlrrSubBlock.parse(buffer, 0);

      expect(subBlock.ssrc, equals(0x12345678));
      expect(subBlock.lastRr, equals(0xABCDEF01));
      expect(subBlock.delaySinceLastRr, equals(0x11223344));
    });

    test('fromTimestamps converts delay correctly', () {
      final subBlock = DlrrSubBlock.fromTimestamps(
        ssrc: 0x12345678,
        rrtrNtpMiddle32: 0xABCDEF01,
        delay: Duration(milliseconds: 500),
      );

      // 500ms = 32768 units (500 * 65536 / 1000)
      expect(subBlock.delaySinceLastRr, equals(32768));
    });

    test('delay getter converts correctly', () {
      final subBlock = DlrrSubBlock(
        ssrc: 0,
        lastRr: 0,
        delaySinceLastRr: 65536, // 1 second in 1/65536 units
      );

      expect(subBlock.delay.inSeconds, equals(1));
    });
  });

  group('DlrrBlock', () {
    test('serialize with single sub-block', () {
      final block = DlrrBlock([
        DlrrSubBlock(
          ssrc: 0x12345678,
          lastRr: 0xABCDEF01,
          delaySinceLastRr: 0x11223344,
        ),
      ]);

      final bytes = block.serialize();

      expect(bytes.length, equals(16)); // 4 header + 12 sub-block
      expect(bytes[0], equals(5)); // BT=5
      expect(bytes[1], equals(0)); // reserved
      expect(bytes[2], equals(0)); // block length high
      expect(bytes[3], equals(3)); // block length low = 3 (12 bytes = 3 words)
    });

    test('serialize with multiple sub-blocks', () {
      final block = DlrrBlock([
        DlrrSubBlock(ssrc: 0x11111111, lastRr: 0, delaySinceLastRr: 0),
        DlrrSubBlock(ssrc: 0x22222222, lastRr: 0, delaySinceLastRr: 0),
        DlrrSubBlock(ssrc: 0x33333333, lastRr: 0, delaySinceLastRr: 0),
      ]);

      final bytes = block.serialize();

      expect(bytes.length, equals(40)); // 4 header + 36 (3 * 12) sub-blocks
      expect(bytes[3], equals(9)); // block length = 9 words
    });

    test('parse creates correct block', () {
      final data = Uint8List.fromList([
        5, 0, 0, 3, // header: BT=5, reserved, length=3
        0x12, 0x34, 0x56, 0x78, // SSRC
        0xAB, 0xCD, 0xEF, 0x01, // LRR
        0x11, 0x22, 0x33, 0x44, // DLRR
      ]);

      final block = DlrrBlock.parse(data);

      expect(block, isNotNull);
      expect(block!.subBlocks.length, equals(1));
      expect(block.subBlocks[0].ssrc, equals(0x12345678));
    });

    test('roundtrip serialize/parse', () {
      final original = DlrrBlock([
        DlrrSubBlock(
            ssrc: 0xAAAAAAAA, lastRr: 0xBBBBBBBB, delaySinceLastRr: 0xCCCCCCCC),
        DlrrSubBlock(
            ssrc: 0xDDDDDDDD, lastRr: 0xEEEEEEEE, delaySinceLastRr: 0x12345678),
      ]);

      final bytes = original.serialize();
      final parsed = DlrrBlock.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.subBlocks.length, equals(2));
      expect(parsed.subBlocks[0].ssrc, equals(0xAAAAAAAA));
      expect(parsed.subBlocks[1].ssrc, equals(0xDDDDDDDD));
      expect(parsed.subBlocks[1].delaySinceLastRr, equals(0x12345678));
    });

    test('blockType returns dlrr', () {
      final block = DlrrBlock([]);
      expect(block.blockType, equals(XrBlockType.dlrr));
    });
  });

  group('StatisticsSummaryBlock', () {
    test('serialize creates correct bytes', () {
      final block = StatisticsSummaryBlock(
        lossReportFlag: true,
        duplicateReportFlag: true,
        jitterFlag: true,
        ttlOrHopLimit: 1,
        ssrcOfSource: 0x12345678,
        beginSeq: 1000,
        endSeq: 2000,
        lostPackets: 50,
        dupPackets: 5,
        minJitter: 100,
        maxJitter: 500,
        meanJitter: 250,
        devJitter: 75,
        minTtl: 60,
        maxTtl: 64,
        meanTtl: 62,
        devTtl: 1,
      );

      final bytes = block.serialize();

      expect(bytes.length, equals(40));
      expect(bytes[0], equals(6)); // BT=6
      // Type-specific: L=1, D=1, J=1, ToH=01, rsvd=0 = 0b11101000 = 0xE8
      expect(bytes[1], equals(0xE8));
      expect(bytes[2], equals(0)); // block length high
      expect(bytes[3], equals(9)); // block length = 9
    });

    test('parse creates correct block', () {
      final data = Uint8List.fromList([
        6, 0xE8, 0, 9, // header: BT=6, flags, length=9
        0x12, 0x34, 0x56, 0x78, // SSRC of source
        0x03, 0xE8, 0x07, 0xD0, // begin_seq=1000, end_seq=2000
        0, 0, 0, 50, // lost_packets
        0, 0, 0, 5, // dup_packets
        0, 0, 0, 100, // min_jitter
        0, 0, 1, 244, // max_jitter = 500
        0, 0, 0, 250, // mean_jitter
        0, 0, 0, 75, // dev_jitter
        60, 64, 62, 1, // TTL stats
      ]);

      final block = StatisticsSummaryBlock.parse(data);

      expect(block, isNotNull);
      expect(block!.lossReportFlag, isTrue);
      expect(block.duplicateReportFlag, isTrue);
      expect(block.jitterFlag, isTrue);
      expect(block.ttlOrHopLimit, equals(1));
      expect(block.ssrcOfSource, equals(0x12345678));
      expect(block.beginSeq, equals(1000));
      expect(block.endSeq, equals(2000));
      expect(block.lostPackets, equals(50));
      expect(block.dupPackets, equals(5));
      expect(block.minJitter, equals(100));
      expect(block.maxJitter, equals(500));
      expect(block.meanJitter, equals(250));
      expect(block.devJitter, equals(75));
      expect(block.minTtl, equals(60));
      expect(block.maxTtl, equals(64));
      expect(block.meanTtl, equals(62));
      expect(block.devTtl, equals(1));
    });

    test('roundtrip serialize/parse', () {
      final original = StatisticsSummaryBlock(
        lossReportFlag: true,
        duplicateReportFlag: false,
        jitterFlag: true,
        ttlOrHopLimit: 2,
        ssrcOfSource: 0xDEADBEEF,
        beginSeq: 5000,
        endSeq: 6000,
        lostPackets: 100,
        dupPackets: 10,
        minJitter: 50,
        maxJitter: 200,
        meanJitter: 100,
        devJitter: 30,
        minTtl: 50,
        maxTtl: 60,
        meanTtl: 55,
        devTtl: 2,
      );

      final bytes = original.serialize();
      final parsed = StatisticsSummaryBlock.parse(bytes);

      expect(parsed, isNotNull);
      expect(parsed!.lossReportFlag, equals(original.lossReportFlag));
      expect(parsed.duplicateReportFlag, equals(original.duplicateReportFlag));
      expect(parsed.jitterFlag, equals(original.jitterFlag));
      expect(parsed.ttlOrHopLimit, equals(original.ttlOrHopLimit));
      expect(parsed.ssrcOfSource, equals(original.ssrcOfSource));
      expect(parsed.beginSeq, equals(original.beginSeq));
      expect(parsed.endSeq, equals(original.endSeq));
      expect(parsed.lostPackets, equals(original.lostPackets));
      expect(parsed.dupPackets, equals(original.dupPackets));
      expect(parsed.minJitter, equals(original.minJitter));
      expect(parsed.maxJitter, equals(original.maxJitter));
      expect(parsed.meanJitter, equals(original.meanJitter));
      expect(parsed.devJitter, equals(original.devJitter));
      expect(parsed.minTtl, equals(original.minTtl));
      expect(parsed.maxTtl, equals(original.maxTtl));
      expect(parsed.meanTtl, equals(original.meanTtl));
      expect(parsed.devTtl, equals(original.devTtl));
    });

    test('blockType returns statisticsSummary', () {
      final block = StatisticsSummaryBlock(
        ssrcOfSource: 0,
        beginSeq: 0,
        endSeq: 0,
      );
      expect(block.blockType, equals(XrBlockType.statisticsSummary));
    });
  });

  group('RtcpExtendedReport', () {
    test('toRtcpPacket creates correct packet', () {
      final xr = RtcpExtendedReport(
        ssrc: 0x12345678,
        blocks: [
          ReceiverReferenceTimeBlock(
            ntpTimestampMsw: 0xAAAAAAAA,
            ntpTimestampLsw: 0xBBBBBBBB,
          ),
        ],
      );

      final packet = xr.toRtcpPacket();

      expect(packet.packetType, equals(RtcpPacketType.extendedReport));
      expect(packet.ssrc, equals(0x12345678));
      expect(packet.payload.length, equals(12)); // RRTR block size
    });

    test('fromPacket parses correctly', () {
      // Build XR packet manually
      final payload = Uint8List.fromList([
        4, 0, 0, 2, // RRTR header
        0xAA, 0xAA, 0xAA, 0xAA, // NTP MSW
        0xBB, 0xBB, 0xBB, 0xBB, // NTP LSW
      ]);

      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.extendedReport,
        length: 4, // (20 bytes / 4) - 1 = 4
        ssrc: 0x12345678,
        payload: payload,
      );

      final xr = RtcpExtendedReport.fromPacket(packet);

      expect(xr, isNotNull);
      expect(xr!.ssrc, equals(0x12345678));
      expect(xr.blocks.length, equals(1));
      expect(xr.blocks[0], isA<ReceiverReferenceTimeBlock>());
    });

    test('roundtrip with multiple blocks', () {
      final original = RtcpExtendedReport(
        ssrc: 0xDEADBEEF,
        blocks: [
          ReceiverReferenceTimeBlock(
            ntpTimestampMsw: 0x11111111,
            ntpTimestampLsw: 0x22222222,
          ),
          DlrrBlock([
            DlrrSubBlock(
                ssrc: 0x33333333,
                lastRr: 0x44444444,
                delaySinceLastRr: 0x55555555),
          ]),
        ],
      );

      final packet = original.toRtcpPacket();
      final parsed = RtcpExtendedReport.fromPacket(packet);

      expect(parsed, isNotNull);
      expect(parsed!.ssrc, equals(original.ssrc));
      expect(parsed.blocks.length, equals(2));
      expect(parsed.blocks[0], isA<ReceiverReferenceTimeBlock>());
      expect(parsed.blocks[1], isA<DlrrBlock>());
    });

    test('fromPacket returns null for non-XR packet', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 1,
        ssrc: 0,
        payload: Uint8List(0),
      );

      final xr = RtcpExtendedReport.fromPacket(packet);
      expect(xr, isNull);
    });

    test('blocksOfType filters correctly', () {
      final xr = RtcpExtendedReport(
        ssrc: 0x12345678,
        blocks: [
          ReceiverReferenceTimeBlock(
              ntpTimestampMsw: 0, ntpTimestampLsw: 0),
          DlrrBlock([]),
          ReceiverReferenceTimeBlock(
              ntpTimestampMsw: 1, ntpTimestampLsw: 1),
        ],
      );

      final rrtrBlocks = xr.blocksOfType<ReceiverReferenceTimeBlock>();
      final dlrrBlocks = xr.blocksOfType<DlrrBlock>();

      expect(rrtrBlocks.length, equals(2));
      expect(dlrrBlocks.length, equals(1));
    });

    test('serialize produces valid bytes', () {
      final xr = RtcpExtendedReport(
        ssrc: 0x12345678,
        blocks: [
          ReceiverReferenceTimeBlock(
            ntpTimestampMsw: 0xAAAAAAAA,
            ntpTimestampLsw: 0xBBBBBBBB,
          ),
        ],
      );

      final bytes = xr.serialize();

      // 8 (RTCP header) + 12 (RRTR block) = 20 bytes
      expect(bytes.length, equals(20));

      // Verify RTCP header
      expect(bytes[0] & 0xC0, equals(0x80)); // V=2
      expect(bytes[1], equals(207)); // PT=207 (XR)
    });

    test('handles unknown block types gracefully', () {
      // Build XR packet with unknown block type
      final payload = Uint8List.fromList([
        99, 0, 0, 1, // Unknown BT=99, length=1
        0, 0, 0, 0, // 4 bytes of data
      ]);

      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.extendedReport,
        length: 3,
        ssrc: 0x12345678,
        payload: payload,
      );

      final xr = RtcpExtendedReport.fromPacket(packet);

      expect(xr, isNotNull);
      expect(xr!.blocks.length, equals(0)); // Unknown block skipped
    });

    test('handles mixed known and unknown blocks', () {
      // Build XR packet with known RRTR + unknown block
      final payload = Uint8List.fromList([
        // RRTR block
        4, 0, 0, 2,
        0xAA, 0xAA, 0xAA, 0xAA,
        0xBB, 0xBB, 0xBB, 0xBB,
        // Unknown block
        99, 0, 0, 1,
        0, 0, 0, 0,
      ]);

      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.extendedReport,
        length: 6, // (28 bytes / 4) - 1 = 6
        ssrc: 0x12345678,
        payload: payload,
      );

      final xr = RtcpExtendedReport.fromPacket(packet);

      expect(xr, isNotNull);
      expect(xr!.blocks.length, equals(1)); // Only RRTR parsed
      expect(xr.blocks[0], isA<ReceiverReferenceTimeBlock>());
    });
  });

  group('Integration with RtcpPacket', () {
    test('XR packet type is recognized', () {
      expect(RtcpPacketType.extendedReport.value, equals(207));
      expect(RtcpPacketType.fromValue(207),
          equals(RtcpPacketType.extendedReport));
    });

    test('XR packet can be parsed in compound packet', () {
      // Create compound packet with SR + XR
      final sr = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 1,
        ssrc: 0x11111111,
        payload: Uint8List(0),
      );

      final xr = RtcpExtendedReport(
        ssrc: 0x22222222,
        blocks: [
          ReceiverReferenceTimeBlock(
              ntpTimestampMsw: 0xAAAA, ntpTimestampLsw: 0xBBBB),
        ],
      );

      final compound =
          RtcpCompoundPacket([sr, xr.toRtcpPacket()]);
      final bytes = compound.serialize();

      final parsed = RtcpCompoundPacket.parse(bytes);
      expect(parsed.packets.length, equals(2));
      expect(parsed.packets[0].packetType, equals(RtcpPacketType.senderReport));
      expect(
          parsed.packets[1].packetType, equals(RtcpPacketType.extendedReport));

      // Parse the XR packet
      final parsedXr = RtcpExtendedReport.fromPacket(parsed.packets[1]);
      expect(parsedXr, isNotNull);
      expect(parsedXr!.blocks.length, equals(1));
    });
  });
}
