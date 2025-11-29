import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/nack_handler.dart';
import 'package:webrtc_dart/src/rtcp/nack.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('NackHandler', () {
    late NackHandler handler;
    late List<GenericNack> sentNacks;
    late List<int> lostPacketCallbacks;

    setUp(() {
      sentNacks = [];
      lostPacketCallbacks = [];

      handler = NackHandler(
        senderSsrc: 0x12345678,
        onSendNack: (nack) async {
          sentNacks.add(nack);
        },
        onPacketLost: (seqNum) {
          lostPacketCallbacks.add(seqNum);
        },
        maxRetries: 3,
        nackIntervalMs: 10,
      );
    });

    tearDown(() {
      handler.close();
    });

    RtpPacket createPacket(int seqNum, int ssrc) {
      return RtpPacket(
        payloadType: 96,
        sequenceNumber: seqNum,
        timestamp: seqNum * 1000,
        ssrc: ssrc,
        payload: Uint8List(0),
      );
    }

    test('should initialize expected sequence number on first packet', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
      expect(handler.mediaSourceSsrc, equals(0xAABBCCDD));
    });

    test('should handle consecutive packets without loss', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(101, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
      expect(sentNacks, isEmpty);
    });

    test('should detect single missing packet', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD)); // Gap: 101 missing

      expect(handler.lostPacketCount, equals(1));
      expect(handler.lostSeqNumbers, contains(101));

      // Wait for NACK to be sent
      await Future.delayed(Duration(milliseconds: 20));

      expect(sentNacks, isNotEmpty);
      expect(sentNacks[0].lostSeqNumbers, contains(101));
    });

    test('should detect multiple consecutive missing packets', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(105, 0xAABBCCDD)); // Gap: 101-104 missing

      expect(handler.lostPacketCount, equals(4));
      expect(handler.lostSeqNumbers, containsAll([101, 102, 103, 104]));

      // Wait for NACK
      await Future.delayed(Duration(milliseconds: 20));

      expect(sentNacks, isNotEmpty);
      expect(sentNacks[0].lostSeqNumbers, containsAll([101, 102, 103, 104]));
    });

    test('should recover when lost packet arrives late', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(103, 0xAABBCCDD)); // Gap: 101, 102 missing

      expect(handler.lostPacketCount, equals(2));

      // Receive one of the missing packets
      handler.addPacket(createPacket(101, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(1));
      expect(handler.lostSeqNumbers, equals([102]));

      // Receive the other missing packet
      handler.addPacket(createPacket(102, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
    });

    test('should send periodic NACKs for persistent loss', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD)); // 101 missing

      // Wait for multiple NACK intervals
      await Future.delayed(Duration(milliseconds: 50));

      // Should have sent multiple NACKs
      expect(sentNacks.length, greaterThan(1));

      // All should contain the same lost packet
      for (final nack in sentNacks) {
        expect(nack.lostSeqNumbers, contains(101));
      }
    });

    test('should give up after max retries', () async {
      final customHandler = NackHandler(
        senderSsrc: 0x12345678,
        onSendNack: (nack) async {
          sentNacks.add(nack);
        },
        onPacketLost: (seqNum) {
          lostPacketCallbacks.add(seqNum);
        },
        maxRetries: 2,
        nackIntervalMs: 10,
      );

      customHandler.addPacket(createPacket(100, 0xAABBCCDD));
      customHandler.addPacket(createPacket(102, 0xAABBCCDD)); // 101 missing

      // Wait for retries to exceed maxRetries
      await Future.delayed(Duration(milliseconds: 50));

      // Should have called onPacketLost
      expect(lostPacketCallbacks, contains(101));

      // Lost packet should be removed from tracking
      expect(customHandler.lostPacketCount, equals(0));

      customHandler.close();
    });

    test('should handle sequence number wraparound', () async {
      handler.addPacket(createPacket(0xFFFE, 0xAABBCCDD));
      handler.addPacket(createPacket(0x0001, 0xAABBCCDD)); // Gap: 0xFFFF, 0x0000

      expect(handler.lostPacketCount, equals(2));
      expect(handler.lostSeqNumbers, containsAll([0xFFFF, 0x0000]));

      await Future.delayed(Duration(milliseconds: 20));

      expect(sentNacks, isNotEmpty);
      expect(sentNacks[0].lostSeqNumbers.toSet(), equals({0xFFFF, 0x0000}));
    });

    test('should recover packets across wraparound', () {
      handler.addPacket(createPacket(0xFFFE, 0xAABBCCDD));
      handler.addPacket(createPacket(0x0001, 0xAABBCCDD)); // Missing: 0xFFFF, 0x0000

      expect(handler.lostPacketCount, equals(2));

      // Receive missing packets
      handler.addPacket(createPacket(0xFFFF, 0xAABBCCDD));
      handler.addPacket(createPacket(0x0000, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
    });

    test('should prune lost packets list when limit exceeded', () {
      final ssrc = 0xAABBCCDD;
      handler.addPacket(createPacket(100, ssrc));

      // Create gap larger than maxLostPackets (150)
      handler.addPacket(createPacket(300, ssrc)); // 200 packets missing

      // Should prune to maxLostPackets
      expect(handler.lostPacketCount, lessThanOrEqualTo(150));
    });

    test('should stop timer when all packets recovered', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD)); // 101 missing

      await Future.delayed(Duration(milliseconds: 20));

      final nackCountBefore = sentNacks.length;

      // Recover the packet
      handler.addPacket(createPacket(101, 0xAABBCCDD));

      // Wait to ensure no more NACKs are sent
      await Future.delayed(Duration(milliseconds: 50));

      // NACK count should not increase after recovery
      expect(sentNacks.length, equals(nackCountBefore));
    });

    test('should handle errors in NACK sending gracefully', () async {
      var callCount = 0;
      final errorHandler = NackHandler(
        senderSsrc: 0x12345678,
        onSendNack: (nack) async {
          callCount++;
          throw Exception('Send failed');
        },
        nackIntervalMs: 10,
      );

      errorHandler.addPacket(createPacket(100, 0xAABBCCDD));
      errorHandler.addPacket(createPacket(102, 0xAABBCCDD));

      await Future.delayed(Duration(milliseconds: 50));

      // Should have attempted multiple times despite errors
      expect(callCount, greaterThan(1));

      errorHandler.close();
    });

    test('should include correct SSRCs in NACK', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD));

      await Future.delayed(Duration(milliseconds: 20));

      expect(sentNacks, isNotEmpty);
      expect(sentNacks[0].senderSsrc, equals(0x12345678));
      expect(sentNacks[0].mediaSourceSsrc, equals(0xAABBCCDD));
    });

    test('should not send NACKs after close', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD));

      handler.close();

      await Future.delayed(Duration(milliseconds: 50));

      // Should not have sent any NACKs
      expect(sentNacks, isEmpty);
    });

    test('should ignore packets after close', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.close();

      handler.addPacket(createPacket(102, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
    });

    test('should handle out-of-order packets correctly', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(105, 0xAABBCCDD)); // Gap created

      expect(handler.lostPacketCount, equals(4)); // 101-104 missing

      // Receive packets out of order
      handler.addPacket(createPacket(103, 0xAABBCCDD));
      handler.addPacket(createPacket(101, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(2)); // 102, 104 still missing
    });

    test('should handle duplicate packets gracefully', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(101, 0xAABBCCDD));
      handler.addPacket(createPacket(101, 0xAABBCCDD)); // Duplicate

      expect(handler.lostPacketCount, equals(0));
    });

    test('should track media source SSRC correctly', () {
      handler.addPacket(createPacket(100, 0xAAAAAAAA));

      expect(handler.mediaSourceSsrc, equals(0xAAAAAAAA));

      // All subsequent packets should be from same source
      handler.addPacket(createPacket(102, 0xAAAAAAAA));

      expect(handler.lostPacketCount, equals(1));
      expect(handler.lostSeqNumbers, equals([101]));
    });

    test('should provide accurate lost packet count', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(110, 0xAABBCCDD)); // 101-109 missing

      expect(handler.lostPacketCount, equals(9));

      // Recover some
      handler.addPacket(createPacket(105, 0xAABBCCDD));
      handler.addPacket(createPacket(107, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(7));
    });

    test('should handle very large gaps', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(1000, 0xAABBCCDD)); // 900 packets gap

      // Should prune to maxLostPackets (150)
      expect(handler.lostPacketCount, lessThanOrEqualTo(150));
    });

    test('should handle rapid packet arrival', () {
      final ssrc = 0xAABBCCDD;

      // Send burst of 100 packets
      for (var i = 0; i < 100; i++) {
        handler.addPacket(createPacket(100 + i, ssrc));
      }

      expect(handler.lostPacketCount, equals(0));
    });

    test('should handle multiple gaps', () async {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(102, 0xAABBCCDD)); // Gap: 101
      handler.addPacket(createPacket(105, 0xAABBCCDD)); // Gap: 103, 104
      handler.addPacket(createPacket(110, 0xAABBCCDD)); // Gap: 106-109

      expect(handler.lostPacketCount, equals(7));
      expect(
        handler.lostSeqNumbers,
        containsAll([101, 103, 104, 106, 107, 108, 109]),
      );

      await Future.delayed(Duration(milliseconds: 20));

      expect(sentNacks, isNotEmpty);
      final allLost = sentNacks[0].lostSeqNumbers.toSet();
      expect(allLost, containsAll([101, 103, 104, 106, 107, 108, 109]));
    });

    test('should maintain state consistency during recovery', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(110, 0xAABBCCDD)); // 101-109 missing

      final initialCount = handler.lostPacketCount;
      expect(initialCount, equals(9));

      // Recover packets in different order
      for (final seqNum in [105, 102, 108, 101, 107, 103, 109, 104, 106]) {
        handler.addPacket(createPacket(seqNum, 0xAABBCCDD));
      }

      expect(handler.lostPacketCount, equals(0));
    });

    test('should handle first packet at sequence 0', () {
      handler.addPacket(createPacket(0, 0xAABBCCDD));
      handler.addPacket(createPacket(1, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(0));
    });

    test('should handle gap detection with first packet', () {
      handler.addPacket(createPacket(100, 0xAABBCCDD));
      handler.addPacket(createPacket(105, 0xAABBCCDD));

      expect(handler.lostPacketCount, equals(4));
      expect(handler.lostSeqNumbers.toSet(), equals({101, 102, 103, 104}));
    });
  });
}
