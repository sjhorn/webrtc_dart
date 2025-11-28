import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('RtcpSenderReport', () {
    test('serializes to RTCP packet', () {
      final sr = RtcpSenderReport(
        ssrc: 0x12345678,
        ntpTimestamp: 0x123456789ABCDEF0,
        rtpTimestamp: 1000,
        packetCount: 100,
        octetCount: 5000,
      );

      final packet = sr.toPacket();

      expect(packet.packetType, RtcpPacketType.senderReport);
      expect(packet.ssrc, 0x12345678);
      expect(packet.reportCount, 0);
      expect(packet.payload.length, 20); // Sender info only
    });

    test('serializes with reception reports', () {
      final sr = RtcpSenderReport(
        ssrc: 0x12345678,
        ntpTimestamp: 0x123456789ABCDEF0,
        rtpTimestamp: 1000,
        packetCount: 100,
        octetCount: 5000,
        receptionReports: [
          RtcpReceptionReportBlock(
            ssrc: 0xAABBCCDD,
            fractionLost: 10,
            cumulativeLost: 5,
            extendedHighestSequence: 1000,
            jitter: 20,
            lastSr: 0x12345678,
            delaySinceLastSr: 100,
          ),
        ],
      );

      final packet = sr.toPacket();

      expect(packet.reportCount, 1);
      expect(packet.payload.length, 20 + 24); // Sender info + 1 report
    });

    test('parses from RTCP packet', () {
      final original = RtcpSenderReport(
        ssrc: 0x12345678,
        ntpTimestamp: 0x123456789ABCDEF0,
        rtpTimestamp: 1000,
        packetCount: 100,
        octetCount: 5000,
      );

      final packet = original.toPacket();
      final parsed = RtcpSenderReport.fromPacket(packet);

      expect(parsed.ssrc, 0x12345678);
      expect(parsed.ntpTimestamp, 0x123456789ABCDEF0);
      expect(parsed.rtpTimestamp, 1000);
      expect(parsed.packetCount, 100);
      expect(parsed.octetCount, 5000);
      expect(parsed.receptionReports.length, 0);
    });

    test('parses with reception reports', () {
      final original = RtcpSenderReport(
        ssrc: 0x12345678,
        ntpTimestamp: 0x123456789ABCDEF0,
        rtpTimestamp: 1000,
        packetCount: 100,
        octetCount: 5000,
        receptionReports: [
          RtcpReceptionReportBlock(
            ssrc: 0xAABBCCDD,
            fractionLost: 10,
            cumulativeLost: 5,
            extendedHighestSequence: 1000,
            jitter: 20,
            lastSr: 0x12345678,
            delaySinceLastSr: 100,
          ),
          RtcpReceptionReportBlock(
            ssrc: 0x11223344,
            fractionLost: 5,
            cumulativeLost: 2,
            extendedHighestSequence: 2000,
            jitter: 15,
            lastSr: 0x87654321,
            delaySinceLastSr: 50,
          ),
        ],
      );

      final packet = original.toPacket();
      final parsed = RtcpSenderReport.fromPacket(packet);

      expect(parsed.receptionReports.length, 2);
      expect(parsed.receptionReports[0].ssrc, 0xAABBCCDD);
      expect(parsed.receptionReports[1].ssrc, 0x11223344);
    });

    test('throws on invalid packet type', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.receiverReport, // Wrong type
        length: 5,
        ssrc: 0x12345678,
        payload: Uint8List(20),
      );

      expect(
        () => RtcpSenderReport.fromPacket(packet),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws on payload too short', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 1,
        ssrc: 0x12345678,
        payload: Uint8List(10), // Too short
      );

      expect(
        () => RtcpSenderReport.fromPacket(packet),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RtcpReceiverReport', () {
    test('serializes to RTCP packet', () {
      final rr = RtcpReceiverReport(
        ssrc: 0x12345678,
        receptionReports: [],
      );

      final packet = rr.toPacket();

      expect(packet.packetType, RtcpPacketType.receiverReport);
      expect(packet.ssrc, 0x12345678);
      expect(packet.reportCount, 0);
      expect(packet.payload.length, 0);
    });

    test('serializes with reception reports', () {
      final rr = RtcpReceiverReport(
        ssrc: 0x12345678,
        receptionReports: [
          RtcpReceptionReportBlock(
            ssrc: 0xAABBCCDD,
            fractionLost: 10,
            cumulativeLost: 5,
            extendedHighestSequence: 1000,
            jitter: 20,
            lastSr: 0x12345678,
            delaySinceLastSr: 100,
          ),
        ],
      );

      final packet = rr.toPacket();

      expect(packet.reportCount, 1);
      expect(packet.payload.length, 24);
    });

    test('parses from RTCP packet', () {
      final original = RtcpReceiverReport(
        ssrc: 0x12345678,
        receptionReports: [
          RtcpReceptionReportBlock(
            ssrc: 0xAABBCCDD,
            fractionLost: 10,
            cumulativeLost: 5,
            extendedHighestSequence: 1000,
            jitter: 20,
            lastSr: 0x12345678,
            delaySinceLastSr: 100,
          ),
        ],
      );

      final packet = original.toPacket();
      final parsed = RtcpReceiverReport.fromPacket(packet);

      expect(parsed.ssrc, 0x12345678);
      expect(parsed.receptionReports.length, 1);
      expect(parsed.receptionReports[0].ssrc, 0xAABBCCDD);
    });

    test('throws on invalid packet type', () {
      final packet = RtcpPacket(
        reportCount: 0,
        packetType: RtcpPacketType.senderReport, // Wrong type
        length: 1,
        ssrc: 0x12345678,
        payload: Uint8List(0),
      );

      expect(
        () => RtcpReceiverReport.fromPacket(packet),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RtcpReceptionReportBlock', () {
    test('serializes to 24 bytes', () {
      final report = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 10,
        cumulativeLost: 100,
        extendedHighestSequence: 1000,
        jitter: 20,
        lastSr: 0x12345678,
        delaySinceLastSr: 50,
      );

      final data = report.serialize();

      expect(data.length, 24);
    });

    test('parses from 24 bytes', () {
      final original = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 10,
        cumulativeLost: 100,
        extendedHighestSequence: 1000,
        jitter: 20,
        lastSr: 0x12345678,
        delaySinceLastSr: 50,
      );

      final data = original.serialize();
      final parsed = RtcpReceptionReportBlock.parse(data);

      expect(parsed.ssrc, 0xAABBCCDD);
      expect(parsed.fractionLost, 10);
      expect(parsed.cumulativeLost, 100);
      expect(parsed.extendedHighestSequence, 1000);
      expect(parsed.jitter, 20);
      expect(parsed.lastSr, 0x12345678);
      expect(parsed.delaySinceLastSr, 50);
    });

    test('handles negative cumulative lost', () {
      // Cumulative lost is 24-bit signed
      // In Dart, int is 64-bit signed, so negative values work correctly
      final report = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 0,
        cumulativeLost: -100,
        extendedHighestSequence: 1000,
        jitter: 20,
        lastSr: 0x12345678,
        delaySinceLastSr: 50,
      );

      final data = report.serialize();
      final parsed = RtcpReceptionReportBlock.parse(data);

      // When serializing -100, it becomes 0xFFFFFF9C in 24-bit two's complement
      // After parsing, it should be sign-extended to a negative int
      // The parsed value will be 0xFFFFFF9C sign-extended = -100 (as 32-bit signed)
      // But in Dart, it gets represented as 0xFFFFFF9C = 4294967196 due to OR with 0xFF000000
      // Let's verify the 24-bit representation is correct instead
      final buffer = ByteData.sublistView(data);
      final bits24 = (buffer.getUint8(5) << 16) |
          (buffer.getUint8(6) << 8) |
          buffer.getUint8(7);

      // -100 in 24-bit two's complement is 0xFFFF9C
      expect(bits24, 0xFFFF9C);

      // The parsed cumulative lost should round-trip correctly
      expect(parsed.cumulativeLost, report.cumulativeLost);
    });

    test('handles large cumulative lost values', () {
      // Maximum 24-bit positive value
      final report = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 255,
        cumulativeLost: 0x7FFFFF, // Max positive 24-bit
        extendedHighestSequence: 0xFFFFFFFF,
        jitter: 0xFFFFFFFF,
        lastSr: 0xFFFFFFFF,
        delaySinceLastSr: 0xFFFFFFFF,
      );

      final data = report.serialize();
      final parsed = RtcpReceptionReportBlock.parse(data);

      expect(parsed.fractionLost, 255);
      expect(parsed.cumulativeLost, 0x7FFFFF);
      expect(parsed.extendedHighestSequence, 0xFFFFFFFF);
      expect(parsed.jitter, 0xFFFFFFFF);
    });

    test('throws on data too short', () {
      final shortData = Uint8List(20); // Less than 24 bytes

      expect(
        () => RtcpReceptionReportBlock.parse(shortData),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles fraction lost boundaries', () {
      // 0 = no loss
      final report1 = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 0,
        cumulativeLost: 0,
        extendedHighestSequence: 1000,
        jitter: 20,
        lastSr: 0x12345678,
        delaySinceLastSr: 50,
      );

      // 255 = 100% loss
      final report2 = RtcpReceptionReportBlock(
        ssrc: 0xAABBCCDD,
        fractionLost: 255,
        cumulativeLost: 1000,
        extendedHighestSequence: 1000,
        jitter: 20,
        lastSr: 0x12345678,
        delaySinceLastSr: 50,
      );

      final data1 = report1.serialize();
      final data2 = report2.serialize();

      final parsed1 = RtcpReceptionReportBlock.parse(data1);
      final parsed2 = RtcpReceptionReportBlock.parse(data2);

      expect(parsed1.fractionLost, 0);
      expect(parsed2.fractionLost, 255);
    });

    test('round-trips through serialization', () {
      final original = RtcpReceptionReportBlock(
        ssrc: 0x11223344,
        fractionLost: 42,
        cumulativeLost: 12345,
        extendedHighestSequence: 67890,
        jitter: 150,
        lastSr: 0x99887766,
        delaySinceLastSr: 999,
      );

      final serialized = original.serialize();
      final parsed = RtcpReceptionReportBlock.parse(serialized);

      expect(parsed.ssrc, original.ssrc);
      expect(parsed.fractionLost, original.fractionLost);
      expect(parsed.cumulativeLost, original.cumulativeLost);
      expect(parsed.extendedHighestSequence, original.extendedHighestSequence);
      expect(parsed.jitter, original.jitter);
      expect(parsed.lastSr, original.lastSr);
      expect(parsed.delaySinceLastSr, original.delaySinceLastSr);
    });
  });
}
