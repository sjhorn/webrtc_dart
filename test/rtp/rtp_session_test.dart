import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';

void main() {
  group('RtpSession', () {
    test('sends RTP packets with incrementing sequence numbers', () async {
      final sentPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      session.start();

      // Send 3 packets
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List.fromList([1, 2, 3]),
        timestampIncrement: 160,
      );
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List.fromList([4, 5, 6]),
        timestampIncrement: 160,
      );
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List.fromList([7, 8, 9]),
        timestampIncrement: 160,
      );

      expect(sentPackets.length, 3);

      // Parse packets and check sequence numbers
      final packet1 = RtpPacket.parse(sentPackets[0]);
      final packet2 = RtpPacket.parse(sentPackets[1]);
      final packet3 = RtpPacket.parse(sentPackets[2]);

      expect(packet2.sequenceNumber, packet1.sequenceNumber + 1);
      expect(packet3.sequenceNumber, packet2.sequenceNumber + 1);

      // Check timestamps increment
      expect(packet2.timestamp, packet1.timestamp + 160);
      expect(packet3.timestamp, packet2.timestamp + 160);

      session.dispose();
    });

    test('receives RTP packets and updates statistics', () async {
      final receivedPackets = <RtpPacket>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        onReceiveRtp: (packet) {
          receivedPackets.add(packet);
        },
      );

      session.start();

      // Create and send incoming packets
      final packet1 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List.fromList([1, 2, 3]),
      );

      final packet2 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 101,
        timestamp: 1160,
        ssrc: 0xAABBCCDD,
        payload: Uint8List.fromList([4, 5, 6]),
      );

      await session.receiveRtp(packet1.serialize());
      await session.receiveRtp(packet2.serialize());

      expect(receivedPackets.length, 2);

      // Check statistics
      final stats = session.getReceiverStatistics(0xAABBCCDD);
      expect(stats, isNotNull);
      expect(stats!.packetsReceived, 2);
      expect(stats.bytesReceived, 6);
      expect(stats.highestSequence, 101);

      session.dispose();
    });

    test('tracks multiple remote SSRCs independently', () async {
      final session = RtpSession(localSsrc: 0x12345678);
      session.start();

      // Receive from two different sources
      final packet1 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x11111111,
        payload: Uint8List(10),
      );

      final packet2 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 200,
        timestamp: 2000,
        ssrc: 0x22222222,
        payload: Uint8List(20),
      );

      await session.receiveRtp(packet1.serialize());
      await session.receiveRtp(packet2.serialize());

      // Check statistics are tracked separately
      final stats1 = session.getReceiverStatistics(0x11111111);
      final stats2 = session.getReceiverStatistics(0x22222222);

      expect(stats1, isNotNull);
      expect(stats2, isNotNull);

      expect(stats1!.packetsReceived, 1);
      expect(stats1.bytesReceived, 10);

      expect(stats2!.packetsReceived, 1);
      expect(stats2.bytesReceived, 20);

      session.dispose();
    });

    test('sends RTCP Sender Reports when packets sent', () async {
      final sentRtcpPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        rtcpIntervalMs: 100, // Short interval for testing
        onSendRtcp: (data) async {
          sentRtcpPackets.add(data);
        },
      );

      // Send some RTP packets first
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List(100),
        timestampIncrement: 160,
      );

      session.start();

      // Wait for RTCP report
      await Future.delayed(Duration(milliseconds: 150));

      expect(sentRtcpPackets.isNotEmpty, true);

      // Parse and verify it's a Sender Report
      final rtcpPacket = RtcpPacket.parse(sentRtcpPackets.first);
      expect(rtcpPacket.packetType, RtcpPacketType.senderReport);
      expect(rtcpPacket.ssrc, 0x12345678);

      final sr = RtcpSenderReport.fromPacket(rtcpPacket);
      expect(sr.packetCount, 1);
      expect(sr.octetCount, 100);

      session.dispose();
    });

    test('sends RTCP Receiver Reports when no packets sent', () async {
      final sentRtcpPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        rtcpIntervalMs: 100, // Short interval for testing
        onSendRtcp: (data) async {
          sentRtcpPackets.add(data);
        },
      );

      session.start();

      // Wait for RTCP report
      await Future.delayed(Duration(milliseconds: 150));

      expect(sentRtcpPackets.isNotEmpty, true);

      // Parse and verify it's a Receiver Report
      final rtcpPacket = RtcpPacket.parse(sentRtcpPackets.first);
      expect(rtcpPacket.packetType, RtcpPacketType.receiverReport);
      expect(rtcpPacket.ssrc, 0x12345678);

      session.dispose();
    });

    test('includes reception reports in RTCP packets', () async {
      final sentRtcpPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        rtcpIntervalMs: 100,
        onSendRtcp: (data) async {
          sentRtcpPackets.add(data);
        },
      );

      // Receive some packets from a remote source
      for (var i = 0; i < 10; i++) {
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100 + i,
          timestamp: 1000 + (i * 160),
          ssrc: 0xAABBCCDD,
          payload: Uint8List(100),
        );
        await session.receiveRtp(packet.serialize());
      }

      // Send a packet so we get SR instead of RR
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List(50),
        timestampIncrement: 160,
      );

      session.start();

      // Wait for RTCP report
      await Future.delayed(Duration(milliseconds: 150));

      expect(sentRtcpPackets.isNotEmpty, true);

      // Parse SR
      final rtcpPacket = RtcpPacket.parse(sentRtcpPackets.first);
      final sr = RtcpSenderReport.fromPacket(rtcpPacket);

      // Should have one reception report
      expect(sr.receptionReports.length, 1);
      expect(sr.receptionReports.first.ssrc, 0xAABBCCDD);

      session.dispose();
    });

    test('handles received Sender Reports', () async {
      final session = RtpSession(localSsrc: 0x12345678);
      session.start();

      // First receive some packets from remote source
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List(10),
      );
      await session.receiveRtp(packet.serialize());

      // Create and receive a Sender Report
      final sr = RtcpSenderReport(
        ssrc: 0xAABBCCDD,
        ntpTimestamp: 0x123456789ABCDEF0,
        rtpTimestamp: 1000,
        packetCount: 100,
        octetCount: 5000,
      );

      await session.receiveRtcp(sr.toPacket().serialize());

      // Check that statistics were updated
      final stats = session.getReceiverStatistics(0xAABBCCDD);
      expect(stats, isNotNull);
      expect(stats!.lastSrTimestamp, 0x123456789ABCDEF0);

      session.dispose();
    });

    test('resets statistics correctly', () async {
      final session = RtpSession(localSsrc: 0x12345678);

      // Send and receive packets
      await session.sendRtp(
        payloadType: 96,
        payload: Uint8List(100),
        timestampIncrement: 160,
      );

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List(50),
      );
      await session.receiveRtp(packet.serialize());

      expect(session.getSenderStatistics().packetsSent, 1);
      expect(session.getAllReceiverStatistics().length, 1);

      // Reset
      session.reset();

      expect(session.getSenderStatistics().packetsSent, 0);
      expect(session.getAllReceiverStatistics().length, 0);

      session.dispose();
    });

    test('stops RTCP reports when stopped', () async {
      final sentRtcpPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        rtcpIntervalMs: 100,
        onSendRtcp: (data) async {
          sentRtcpPackets.add(data);
        },
      );

      session.start();
      await Future.delayed(Duration(milliseconds: 150));

      final countAfterStart = sentRtcpPackets.length;
      expect(countAfterStart, greaterThan(0));

      // Stop session
      session.stop();
      sentRtcpPackets.clear();

      // Wait and verify no more reports sent
      await Future.delayed(Duration(milliseconds: 200));
      expect(sentRtcpPackets.length, 0);

      session.dispose();
    });
  });

  group('RtpSession sendRawRtpPacket (Ring forwarding regression)', () {
    // Test vectors for SRTP
    final masterKey = Uint8List.fromList([
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0a,
      0x0b,
      0x0c,
      0x0d,
      0x0e,
      0x0f,
    ]);
    final masterSalt = Uint8List.fromList([
      0xa0,
      0xa1,
      0xa2,
      0xa3,
      0xa4,
      0xa5,
      0xa6,
      0xa7,
      0xa8,
      0xa9,
      0xaa,
      0xab,
    ]);

    test('drops packets when SRTP session not set', () async {
      final sentPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );
      // No srtpSession set

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet);

      // Packet should be dropped silently
      expect(sentPackets.length, 0);

      session.dispose();
    });

    test('rewrites payload type correctly', () async {
      final sentPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      // Ring sends PT=96, we want to forward as PT=111
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet, payloadType: 111);

      expect(sentPackets.length, 1);

      // Parse encrypted packet header (not encrypted in SRTP, only payload)
      final encrypted = sentPackets.first;
      // Byte 1 contains marker bit (MSB) and payload type (lower 7 bits)
      final ptInPacket = encrypted[1] & 0x7F;
      expect(ptInPacket, 111,
          reason: 'Payload type should be rewritten to 111');

      session.dispose();
    });

    test('replaces SSRC with local SSRC', () async {
      final sentPackets = <Uint8List>[];
      final localSsrc = 0x12345678;
      final session = RtpSession(
        localSsrc: localSsrc,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      // Incoming packet has different SSRC (Ring camera's SSRC)
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD, // Ring's SSRC
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet);

      expect(sentPackets.length, 1);

      // Parse SSRC from encrypted packet (bytes 8-11)
      final encrypted = sentPackets.first;
      final ssrcInPacket = ByteData.sublistView(encrypted).getUint32(8);
      expect(ssrcInPacket, localSsrc,
          reason: 'SSRC should be replaced with local SSRC');

      session.dispose();
    });

    test('preserves SSRC when replaceSsrc=false', () async {
      final sentPackets = <Uint8List>[];
      final originalSsrc = 0xAABBCCDD;
      final session = RtpSession(
        localSsrc: 0x12345678,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: originalSsrc,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet, replaceSsrc: false);

      expect(sentPackets.length, 1);

      // SSRC should be preserved
      final encrypted = sentPackets.first;
      final ssrcInPacket = ByteData.sublistView(encrypted).getUint32(8);
      expect(ssrcInPacket, originalSsrc,
          reason: 'Original SSRC should be preserved');

      session.dispose();
    });

    test('preserves marker bit', () async {
      final sentPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      // Packet with marker bit set (end of frame)
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        marker: true,
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet);

      expect(sentPackets.length, 1);

      // Check marker bit (MSB of byte 1)
      final encrypted = sentPackets.first;
      final markerBit = (encrypted[1] & 0x80) != 0;
      expect(markerBit, true, reason: 'Marker bit should be preserved');

      session.dispose();
    });

    test('preserves extension header for GCM AAD', () async {
      final sentPackets = <Uint8List>[];
      final session = RtpSession(
        localSsrc: 0x12345678,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {
          sentPackets.add(data);
        },
      );

      // Packet with extension header (like mid extension)
      final midExtension = Uint8List.fromList([0x10, 0x31, 0x00, 0x00]);
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE,
          data: midExtension,
        ),
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      await session.sendRawRtpPacket(packet);

      expect(sentPackets.length, 1);

      // Check extension bit is set (bit 4 of byte 0)
      final encrypted = sentPackets.first;
      final hasExtension = (encrypted[0] & 0x10) != 0;
      expect(hasExtension, true, reason: 'Extension bit should be preserved');

      // Check extension profile at bytes 12-13
      final extProfile = ByteData.sublistView(encrypted).getUint16(12);
      expect(extProfile, 0xBEDE, reason: 'Extension profile should be 0xBEDE');

      session.dispose();
    });

    test('updates sender statistics', () async {
      final session = RtpSession(
        localSsrc: 0x12345678,
        srtpSession: SrtpSession(
          profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
          localMasterKey: masterKey,
          localMasterSalt: masterSalt,
          remoteMasterKey: masterKey,
          remoteMasterSalt: masterSalt,
        ),
        onSendRtp: (data) async {},
      );

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0xAABBCCDD,
        payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      );

      await session.sendRawRtpPacket(packet);
      await session.sendRawRtpPacket(packet);
      await session.sendRawRtpPacket(packet);

      final stats = session.getSenderStatistics();
      expect(stats.packetsSent, 3);
      expect(stats.bytesSent, 30);

      session.dispose();
    });
  });
}
