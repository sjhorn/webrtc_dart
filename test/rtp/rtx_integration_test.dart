/// RTX Integration Tests
///
/// Tests for the complete RTX retransmission flow:
/// 1. Sender stores packets in retransmission buffer
/// 2. Receiver detects loss via NackHandler
/// 3. Receiver sends NACK
/// 4. Sender retrieves from buffer and retransmits via RTX
/// 5. Receiver unwraps RTX and recovers original packet
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/rtp/rtx.dart';
import 'package:webrtc_dart/src/rtp/nack_handler.dart';
import 'package:webrtc_dart/src/rtcp/nack.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RTX Integration', () {
    group('RtpSession with RTX enabled', () {
      test('stores sent packets in retransmission buffer', () async {
        final sentPackets = <Uint8List>[];
        final session = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          onSendRtp: (data) async {
            sentPackets.add(data);
          },
        );

        // Send packets
        for (var i = 0; i < 5; i++) {
          await session.sendRtp(
            payloadType: 96,
            payload: Uint8List.fromList([i]),
            timestampIncrement: 160,
          );
        }

        expect(sentPackets.length, equals(5));

        // Verify packets are stored by checking stats
        expect(session.getSenderStatistics().packetsSent, equals(5));

        session.dispose();
      });

      test('retransmits packets via RTX when NACK received', () async {
        final sentRtpPackets = <Uint8List>[];
        final session = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          onSendRtp: (data) async {
            sentRtpPackets.add(data);
          },
        );

        // Send some packets
        for (var i = 0; i < 10; i++) {
          await session.sendRtp(
            payloadType: 96,
            payload: Uint8List.fromList([i, i, i]),
            timestampIncrement: 160,
          );
        }

        expect(sentRtpPackets.length, equals(10));

        // Parse original packets to get actual sequence numbers
        final originalPackets =
            sentRtpPackets.map((d) => RtpPacket.parse(d)).toList();
        final seqNumbers =
            originalPackets.map((p) => p.sequenceNumber).toList();

        sentRtpPackets.clear();

        // Create NACK requesting retransmission of packets 2 and 5
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA, // Remote receiver's SSRC
          mediaSourceSsrc: 0x12345678, // Our SSRC
          lostSeqNumbers: [seqNumbers[2], seqNumbers[5]],
        );

        // Receive NACK as RTCP
        await session.receiveRtcp(nack.toRtcpPacket().serialize());

        // Should have sent 2 RTX packets
        expect(sentRtpPackets.length, equals(2));

        // Verify they are RTX packets
        for (final data in sentRtpPackets) {
          final rtxPacket = RtpPacket.parse(data);
          expect(rtxPacket.ssrc, equals(0x87654321)); // RTX SSRC
          expect(rtxPacket.payloadType, equals(97)); // RTX payload type
        }

        session.dispose();
      });

      test('RTX packet contains original sequence number (OSN)', () async {
        final sentRtpPackets = <Uint8List>[];
        final session = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          onSendRtp: (data) async {
            sentRtpPackets.add(data);
          },
        );

        // Send packet with specific payload
        await session.sendRtp(
          payloadType: 96,
          payload: Uint8List.fromList([0xAA, 0xBB, 0xCC]),
          timestampIncrement: 160,
        );

        // Get original sequence number
        final originalPacket = RtpPacket.parse(sentRtpPackets[0]);
        final originalSeq = originalPacket.sequenceNumber;

        sentRtpPackets.clear();

        // Create NACK for the packet
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA,
          mediaSourceSsrc: 0x12345678,
          lostSeqNumbers: [originalSeq],
        );

        await session.receiveRtcp(nack.toRtcpPacket().serialize());

        expect(sentRtpPackets.length, equals(1));

        // Parse RTX packet
        final rtxPacket = RtpPacket.parse(sentRtpPackets[0]);

        // Extract OSN from payload (first 2 bytes)
        final osnView = ByteData.sublistView(rtxPacket.payload);
        final osn = osnView.getUint16(0);

        expect(osn, equals(originalSeq));

        // Original payload should follow
        expect(rtxPacket.payload.sublist(2), equals([0xAA, 0xBB, 0xCC]));

        session.dispose();
      });

      test('resends original packet when RTX not enabled', () async {
        final sentRtpPackets = <Uint8List>[];
        final session = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: false, // RTX disabled
          onSendRtp: (data) async {
            sentRtpPackets.add(data);
          },
        );

        // Send packet
        await session.sendRtp(
          payloadType: 96,
          payload: Uint8List.fromList([0xAA, 0xBB]),
          timestampIncrement: 160,
        );

        final originalPacket = RtpPacket.parse(sentRtpPackets[0]);
        final originalSeq = originalPacket.sequenceNumber;

        sentRtpPackets.clear();

        // Create NACK
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA,
          mediaSourceSsrc: 0x12345678,
          lostSeqNumbers: [originalSeq],
        );

        await session.receiveRtcp(nack.toRtcpPacket().serialize());

        expect(sentRtpPackets.length, equals(1));

        // Should be original packet format (not RTX)
        final resent = RtpPacket.parse(sentRtpPackets[0]);
        expect(resent.ssrc, equals(0x12345678)); // Original SSRC
        expect(resent.payloadType, equals(96)); // Original payload type
        expect(resent.sequenceNumber, equals(originalSeq));
        expect(resent.payload, equals([0xAA, 0xBB]));

        session.dispose();
      });

      test('ignores NACK for packets no longer in buffer', () async {
        final sentRtpPackets = <Uint8List>[];
        final session = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          retransmissionBufferSize: 8, // Small buffer
          onSendRtp: (data) async {
            sentRtpPackets.add(data);
          },
        );

        // Send more packets than buffer size
        for (var i = 0; i < 20; i++) {
          await session.sendRtp(
            payloadType: 96,
            payload: Uint8List.fromList([i]),
            timestampIncrement: 160,
          );
        }

        sentRtpPackets.clear();

        // Request retransmission of old packet (should be overwritten)
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA,
          mediaSourceSsrc: 0x12345678,
          lostSeqNumbers: [0], // First packet, now overwritten
        );

        await session.receiveRtcp(nack.toRtcpPacket().serialize());

        // Should not retransmit (packet not in buffer)
        expect(sentRtpPackets.length, equals(0));

        session.dispose();
      });
    });

    group('RTX unwrapping on receiver side', () {
      test('unwraps RTX packet and restores original', () async {
        final receivedPackets = <RtpPacket>[];
        final session = RtpSession(
          localSsrc: 0xAAAAAAAA, // Receiver SSRC
          onReceiveRtp: (packet) {
            receivedPackets.add(packet);
          },
        );

        // Register RTX mapping
        session.registerRtxMapping(
          originalSsrc: 0x12345678,
          rtxSsrc: 0x87654321,
          originalPayloadType: 96,
          rtxPayloadType: 97,
        );

        // Create RTX packet with OSN=1234 and payload [0xAA, 0xBB]
        final rtxPayload = Uint8List(4);
        final view = ByteData.sublistView(rtxPayload);
        view.setUint16(0, 1234); // OSN
        rtxPayload[2] = 0xAA;
        rtxPayload[3] = 0xBB;

        final rtxPacket = RtpPacket(
          payloadType: 97, // RTX payload type
          sequenceNumber: 100, // RTX sequence number
          timestamp: 567890,
          ssrc: 0x87654321, // RTX SSRC
          payload: rtxPayload,
        );

        await session.receiveRtp(rtxPacket.serialize());

        expect(receivedPackets.length, equals(1));

        // Should be unwrapped to original format
        final received = receivedPackets[0];
        expect(received.ssrc, equals(0x12345678)); // Original SSRC
        expect(received.payloadType, equals(96)); // Original payload type
        expect(received.sequenceNumber, equals(1234)); // OSN
        expect(received.payload, equals([0xAA, 0xBB]));

        session.dispose();
      });

      test('passes through non-RTX packets unchanged', () async {
        final receivedPackets = <RtpPacket>[];
        final session = RtpSession(
          localSsrc: 0xAAAAAAAA,
          onReceiveRtp: (packet) {
            receivedPackets.add(packet);
          },
        );

        // Register RTX mapping
        session.registerRtxMapping(
          originalSsrc: 0x12345678,
          rtxSsrc: 0x87654321,
          originalPayloadType: 96,
          rtxPayloadType: 97,
        );

        // Send regular (non-RTX) packet
        final regularPacket = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 567890,
          ssrc: 0x12345678, // Original SSRC (not RTX)
          payload: Uint8List.fromList([0xAA, 0xBB]),
        );

        await session.receiveRtp(regularPacket.serialize());

        expect(receivedPackets.length, equals(1));

        final received = receivedPackets[0];
        expect(received.ssrc, equals(0x12345678));
        expect(received.payloadType, equals(96));
        expect(received.sequenceNumber, equals(100));
        expect(received.payload, equals([0xAA, 0xBB]));

        session.dispose();
      });
    });

    group('NACK handler integration', () {
      test('detects packet loss and generates NACK', () async {
        final nacksSent = <GenericNack>[];

        final handler = NackHandler(
          senderSsrc: 0xAAAAAAAA,
          nackIntervalMs: 10, // Short interval for testing
          onSendNack: (nack) async {
            nacksSent.add(nack);
          },
        );

        // Receive packets with a gap (packet 102 missing)
        handler.addPacket(_createPacket(100));
        handler.addPacket(_createPacket(101));
        // Skip 102
        handler.addPacket(_createPacket(103));

        // Wait for NACK to be sent
        await Future.delayed(Duration(milliseconds: 50));

        expect(nacksSent.isNotEmpty, isTrue);
        expect(nacksSent.first.lostSeqNumbers, contains(102));

        handler.close();
      });

      test('removes from lost list when retransmission received', () async {
        final nacksSent = <GenericNack>[];

        final handler = NackHandler(
          senderSsrc: 0xAAAAAAAA,
          nackIntervalMs: 10,
          maxRetries: 5,
          onSendNack: (nack) async {
            nacksSent.add(nack);
          },
        );

        // Create gap
        handler.addPacket(_createPacket(100));
        handler.addPacket(_createPacket(101));
        handler.addPacket(_createPacket(103)); // 102 missing

        expect(handler.lostSeqNumbers, contains(102));

        // Simulate receiving the missing packet (retransmission)
        handler.addPacket(_createPacket(102));

        // Should be removed from lost list
        expect(handler.lostSeqNumbers, isNot(contains(102)));

        handler.close();
      });
    });

    group('End-to-end RTX flow', () {
      test('complete sender-receiver retransmission cycle', () async {
        // Setup sender
        final senderSentPackets = <Uint8List>[];
        final sender = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          onSendRtp: (data) async {
            senderSentPackets.add(data);
          },
        );

        // Sender sends 5 packets
        for (var i = 0; i < 5; i++) {
          await sender.sendRtp(
            payloadType: 96,
            payload: Uint8List.fromList([i * 10, i * 10 + 1]),
            timestampIncrement: 160,
          );
        }

        // Parse original packets to get sequence numbers
        final originalPackets =
            senderSentPackets.map((d) => RtpPacket.parse(d)).toList();
        final seqNumbers =
            originalPackets.map((p) => p.sequenceNumber).toList();

        // Simulate receiver detecting loss of packet 2
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA,
          mediaSourceSsrc: 0x12345678,
          lostSeqNumbers: [
            seqNumbers[2]
          ], // Request retransmission of 3rd packet
        );

        senderSentPackets.clear();

        // Sender receives NACK
        await sender.receiveRtcp(nack.toRtcpPacket().serialize());

        // Sender should retransmit via RTX
        expect(senderSentPackets.length, equals(1));

        final rtxPacket = RtpPacket.parse(senderSentPackets[0]);
        expect(rtxPacket.ssrc, equals(0x87654321)); // RTX SSRC
        expect(rtxPacket.payloadType, equals(97)); // RTX payload type

        // Extract OSN
        final osnView = ByteData.sublistView(rtxPacket.payload);
        final osn = osnView.getUint16(0);
        expect(osn, equals(seqNumbers[2]));

        // Original payload should be [20, 21] (packet index 2 * 10)
        expect(rtxPacket.payload.sublist(2), equals([20, 21]));

        sender.dispose();
      });

      test('handles multiple NACKs for same packet', () async {
        final senderSentPackets = <Uint8List>[];
        final sender = RtpSession(
          localSsrc: 0x12345678,
          rtxEnabled: true,
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          onSendRtp: (data) async {
            senderSentPackets.add(data);
          },
        );

        // Send a packet
        await sender.sendRtp(
          payloadType: 96,
          payload: Uint8List.fromList([0xAA]),
          timestampIncrement: 160,
        );

        final originalSeq =
            RtpPacket.parse(senderSentPackets[0]).sequenceNumber;
        senderSentPackets.clear();

        // Send NACK twice for same packet
        final nack = GenericNack(
          senderSsrc: 0xAAAAAAAA,
          mediaSourceSsrc: 0x12345678,
          lostSeqNumbers: [originalSeq],
        );

        await sender.receiveRtcp(nack.toRtcpPacket().serialize());
        await sender.receiveRtcp(nack.toRtcpPacket().serialize());

        // Should retransmit twice (RTX sequence numbers should increment)
        expect(senderSentPackets.length, equals(2));

        final rtx1 = RtpPacket.parse(senderSentPackets[0]);
        final rtx2 = RtpPacket.parse(senderSentPackets[1]);

        // RTX sequence numbers should be different
        expect(rtx1.sequenceNumber, isNot(equals(rtx2.sequenceNumber)));

        // Both should have same OSN
        final osn1 = ByteData.sublistView(rtx1.payload).getUint16(0);
        final osn2 = ByteData.sublistView(rtx2.payload).getUint16(0);
        expect(osn1, equals(originalSeq));
        expect(osn2, equals(originalSeq));

        sender.dispose();
      });
    });

    group('RTX handler sequence number management', () {
      test('RTX handler increments sequence number independently', () {
        final handler = RtxHandler(
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          rtxSequenceNumber: 100,
        );

        final packet1 = _createPacket(1000);
        final packet2 = _createPacket(1001);
        final packet3 = _createPacket(1000); // Same original packet

        final rtx1 = handler.wrapRtx(packet1);
        final rtx2 = handler.wrapRtx(packet2);
        final rtx3 = handler.wrapRtx(packet3);

        expect(rtx1.sequenceNumber, equals(100));
        expect(rtx2.sequenceNumber, equals(101));
        expect(rtx3.sequenceNumber, equals(102));
      });

      test('RTX handler wraps sequence number at 65535', () {
        final handler = RtxHandler(
          rtxPayloadType: 97,
          rtxSsrc: 0x87654321,
          rtxSequenceNumber: 65534,
        );

        final packet = _createPacket(100);

        final rtx1 = handler.wrapRtx(packet);
        final rtx2 = handler.wrapRtx(packet);
        final rtx3 = handler.wrapRtx(packet);

        expect(rtx1.sequenceNumber, equals(65534));
        expect(rtx2.sequenceNumber, equals(65535));
        expect(rtx3.sequenceNumber, equals(0)); // Wrapped
      });
    });
  });
}

/// Helper to create RTP packets for testing
RtpPacket _createPacket(int sequenceNumber,
    {List<int> payload = const [0x00]}) {
  return RtpPacket(
    version: 2,
    padding: false,
    extension: false,
    marker: false,
    payloadType: 96,
    sequenceNumber: sequenceNumber,
    timestamp: sequenceNumber * 160,
    ssrc: 0x12345678,
    csrcs: [],
    extensionHeader: null,
    payload: Uint8List.fromList(payload),
    paddingLength: 0,
  );
}
