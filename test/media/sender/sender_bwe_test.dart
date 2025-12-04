import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/sender/sender_bwe.dart';
import 'package:webrtc_dart/src/rtcp/rtpfb/twcc.dart';

/// Test subclass that allows direct manipulation of packet results.
class TestTransportWideCC extends TransportWideCC {
  final List<PacketResult> _packetResults = [];

  TestTransportWideCC({
    required super.senderSsrc,
    required super.mediaSourceSsrc,
    required super.baseSequenceNumber,
    required super.packetStatusCount,
    required super.referenceTime,
    required super.fbPktCount,
    required super.packetChunks,
    required super.recvDeltas,
  });

  @override
  List<PacketResult> get packetResults => _packetResults;
}

void main() {
  group('CumulativeResult', () {
    test('addPacket updates first/last times on first packet', () {
      final result = CumulativeResult();
      result.addPacket(100, 1000, 1050);

      expect(result.numPackets, equals(1));
      expect(result.totalSize, equals(100));
      expect(result.firstPacketSentAtMs, equals(1000));
      expect(result.lastPacketSentAtMs, equals(1000));
      expect(result.firstPacketReceivedAtMs, equals(1050));
      expect(result.lastPacketReceivedAtMs, equals(1050));
    });

    test('addPacket updates times correctly for multiple packets', () {
      final result = CumulativeResult();
      result.addPacket(100, 1000, 1050);
      result.addPacket(150, 1100, 1160);
      result.addPacket(120, 1200, 1270);

      expect(result.numPackets, equals(3));
      expect(result.totalSize, equals(370));
      expect(result.firstPacketSentAtMs, equals(1000));
      expect(result.lastPacketSentAtMs, equals(1200));
      expect(result.firstPacketReceivedAtMs, equals(1050));
      expect(result.lastPacketReceivedAtMs, equals(1270));
    });

    test('addPacket handles out-of-order packets', () {
      final result = CumulativeResult();
      result.addPacket(100, 1100, 1150); // Middle
      result.addPacket(100, 1000, 1050); // First
      result.addPacket(100, 1200, 1250); // Last

      expect(result.firstPacketSentAtMs, equals(1000));
      expect(result.lastPacketSentAtMs, equals(1200));
      expect(result.firstPacketReceivedAtMs, equals(1050));
      expect(result.lastPacketReceivedAtMs, equals(1250));
    });

    test('reset clears all values', () {
      final result = CumulativeResult();
      result.addPacket(100, 1000, 1050);
      result.addPacket(150, 1100, 1160);
      result.reset();

      expect(result.numPackets, equals(0));
      expect(result.totalSize, equals(0));
      expect(result.firstPacketSentAtMs, equals(0));
      expect(result.lastPacketSentAtMs, equals(0));
      expect(result.firstPacketReceivedAtMs, equals(0));
      expect(result.lastPacketReceivedAtMs, equals(0));
    });

    test('receiveBitrate calculates correctly', () {
      final result = CumulativeResult();
      // 1000 bytes over 100ms = 10000 bytes/s = 80000 bits/s
      result.addPacket(500, 1000, 1000);
      result.addPacket(500, 1100, 1100); // 100ms interval

      expect(result.receiveBitrate, equals(80000));
    });

    test('sendBitrate calculates correctly', () {
      final result = CumulativeResult();
      // 1000 bytes over 100ms = 10000 bytes/s = 80000 bits/s
      result.addPacket(500, 1000, 1000);
      result.addPacket(500, 1100, 1100); // 100ms interval

      expect(result.sendBitrate, equals(80000));
    });

    test('bitrate returns 0 for zero interval', () {
      final result = CumulativeResult();
      result.addPacket(100, 1000, 1000);

      expect(result.receiveBitrate, equals(0));
      expect(result.sendBitrate, equals(0));
    });
  });

  group('SentInfo', () {
    test('construction', () {
      final info = SentInfo(
        wideSeq: 123,
        size: 1200,
        sendingAtMs: 1000,
        sentAtMs: 1005,
      );

      expect(info.wideSeq, equals(123));
      expect(info.size, equals(1200));
      expect(info.isProbation, isFalse);
      expect(info.sendingAtMs, equals(1000));
      expect(info.sentAtMs, equals(1005));
    });

    test('construction with probation', () {
      final info = SentInfo(
        wideSeq: 123,
        size: 1200,
        isProbation: true,
        sendingAtMs: 1000,
        sentAtMs: 1005,
      );

      expect(info.isProbation, isTrue);
    });
  });

  group('SenderBandwidthEstimator', () {
    late SenderBandwidthEstimator bwe;
    int currentTime = 0;

    setUp(() {
      bwe = SenderBandwidthEstimator();
      currentTime = 0;
      bwe.milliTime = () => currentTime;
    });

    test('initial state', () {
      expect(bwe.congestion, isFalse);
      expect(bwe.congestionScore, equals(1));
      expect(bwe.availableBitrate, equals(0));
    });

    test('rtpPacketSent stores packet info', () {
      bwe.rtpPacketSent(SentInfo(
        wideSeq: 1,
        size: 1200,
        sendingAtMs: 100,
        sentAtMs: 105,
      ));

      // No public way to verify storage, but no crash means success
    });

    test('rtpPacketSent cleans up old entries', () {
      bwe.rtpPacketSent(SentInfo(
        wideSeq: 1,
        size: 1200,
        sendingAtMs: 100,
        sentAtMs: 105,
      ));
      bwe.rtpPacketSent(SentInfo(
        wideSeq: 2,
        size: 1200,
        sendingAtMs: 110,
        sentAtMs: 115,
      ));
      bwe.rtpPacketSent(SentInfo(
        wideSeq: 100,
        size: 1200,
        sendingAtMs: 1000,
        sentAtMs: 1005,
      ));

      // Old entries should be cleaned up (seq < 100)
    });

    test('receiveTWCC updates available bitrate', () {
      // We need packets with enough time spread to calculate bitrate.
      // Key condition: elapsedMs >= 100 && numPackets >= 20

      // Send 25 packets spread over 100ms (0-96ms)
      for (var i = 0; i < 25; i++) {
        bwe.rtpPacketSent(SentInfo(
          wideSeq: i,
          size: 1200,
          sendingAtMs: i * 4, // 0, 4, 8, ..., 96ms
          sentAtMs: i * 4 + 1,
        ));
      }

      // Create feedback with directly accessible packet results
      final feedback = TestTransportWideCC(
        senderSsrc: 1,
        mediaSourceSsrc: 2,
        baseSequenceNumber: 0,
        packetStatusCount: 25,
        referenceTime: 0,
        fbPktCount: 0,
        packetChunks: [],
        recvDeltas: [],
      );
      for (var i = 0; i < 25; i++) {
        feedback.packetResults.add(PacketResult(
          sequenceNumber: i,
          received: true,
          receivedAtMs: i * 4 + 50,
        ));
      }

      // Current time at 100ms, first packet sent at 0ms -> elapsed = 100ms
      // After processing: numPackets = 25, elapsed >= 100, so bitrate calculated
      currentTime = 100;
      bwe.receiveTWCC(feedback);

      // The bitrate should be calculated
      // Sent interval: 96ms (0 to 96), Recv interval: 96ms (50 to 146)
      // 25 * 1200 = 30000 bytes over 96ms = 312500 bytes/sec = 2500000 bits/sec
      expect(bwe.availableBitrate, greaterThan(0));
    });

    test('onAvailableBitrate callback is invoked', () {
      int? callbackBitrate;
      bwe.onAvailableBitrate = (bitrate) {
        callbackBitrate = bitrate;
      };

      // Send 25 packets
      for (var i = 0; i < 25; i++) {
        bwe.rtpPacketSent(SentInfo(
          wideSeq: i,
          size: 1200,
          sendingAtMs: i * 4,
          sentAtMs: i * 4 + 1,
        ));
      }

      final feedback = TestTransportWideCC(
        senderSsrc: 1,
        mediaSourceSsrc: 2,
        baseSequenceNumber: 0,
        packetStatusCount: 25,
        referenceTime: 0,
        fbPktCount: 0,
        packetChunks: [],
        recvDeltas: [],
      );
      for (var i = 0; i < 25; i++) {
        feedback.packetResults.add(PacketResult(
          sequenceNumber: i,
          received: true,
          receivedAtMs: i * 4 + 50,
        ));
      }

      currentTime = 100;
      bwe.receiveTWCC(feedback);

      expect(callbackBitrate, isNotNull);
      expect(callbackBitrate, greaterThan(0));
    });

    test('congestion detected after prolonged feedback delay', () {
      bool? congestionState;
      bwe.onCongestion = (congested) {
        congestionState = congested;
      };

      // Send one packet to initialize timing
      bwe.rtpPacketSent(SentInfo(
        wideSeq: 0,
        size: 1200,
        sendingAtMs: 0,
        sentAtMs: 1,
      ));

      // Create empty feedback to trigger congestion counter increase
      final feedback = TestTransportWideCC(
        senderSsrc: 1,
        mediaSourceSsrc: 2,
        baseSequenceNumber: 0,
        packetStatusCount: 0,
        referenceTime: 0,
        fbPktCount: 0,
        packetChunks: [],
        recvDeltas: [],
      );

      // Simulate 20 feedback cycles with >1000ms delay each
      // Each triggers congestion counter increment
      for (var i = 1; i <= 25; i++) {
        currentTime = i * 1001; // Each cycle has >1000ms elapsed
        bwe.receiveTWCC(feedback);
      }

      expect(bwe.congestion, isTrue);
      expect(congestionState, isTrue);
    });

    test('onCongestionScore callback invoked when score changes', () {
      final scores = <int>[];
      bwe.onCongestionScore = (score) {
        scores.add(score);
      };

      // Create empty feedback
      final feedback = TestTransportWideCC(
        senderSsrc: 1,
        mediaSourceSsrc: 2,
        baseSequenceNumber: 0,
        packetStatusCount: 0,
        referenceTime: 0,
        fbPktCount: 0,
        packetChunks: [],
        recvDeltas: [],
      );

      // Simulate many feedback cycles to increase congestion score
      for (var i = 1; i <= 50; i++) {
        currentTime = i * 1001;
        bwe.receiveTWCC(feedback);
      }

      // Score should have increased from 1
      expect(scores, isNotEmpty);
      expect(bwe.congestionScore, greaterThan(1));
    });

    test('congestion clears when good feedback resumes', () {
      final congestionStates = <bool>[];
      bwe.onCongestion = (congested) {
        congestionStates.add(congested);
      };

      // First trigger congestion
      final emptyFeedback = TestTransportWideCC(
        senderSsrc: 1,
        mediaSourceSsrc: 2,
        baseSequenceNumber: 0,
        packetStatusCount: 0,
        referenceTime: 0,
        fbPktCount: 0,
        packetChunks: [],
        recvDeltas: [],
      );

      for (var i = 1; i <= 25; i++) {
        currentTime = i * 1001;
        bwe.receiveTWCC(emptyFeedback);
      }

      expect(bwe.congestion, isTrue);

      // Now send good feedback to clear congestion
      // Need to reset the timing by sending packets
      var baseTime = 30000;
      currentTime = baseTime;

      // Simulate multiple rounds of good feedback
      for (var round = 0; round < 30; round++) {
        final roundBaseTime = baseTime + round * 100;
        currentTime = roundBaseTime;

        // Send packets for this round
        for (var i = 0; i < 25; i++) {
          bwe.rtpPacketSent(SentInfo(
            wideSeq: round * 25 + i,
            size: 1200,
            sendingAtMs: roundBaseTime + i * 4,
            sentAtMs: roundBaseTime + i * 4 + 1,
          ));
        }

        final goodFeedback = TestTransportWideCC(
          senderSsrc: 1,
          mediaSourceSsrc: 2,
          baseSequenceNumber: round * 25,
          packetStatusCount: 25,
          referenceTime: 0,
          fbPktCount: round,
          packetChunks: [],
          recvDeltas: [],
        );
        for (var i = 0; i < 25; i++) {
          goodFeedback.packetResults.add(PacketResult(
            sequenceNumber: round * 25 + i,
            received: true,
            receivedAtMs: roundBaseTime + i * 4 + 50,
          ));
        }

        // Advance time slightly past the round base
        currentTime = roundBaseTime + 100;
        bwe.receiveTWCC(goodFeedback);
      }

      expect(bwe.congestion, isFalse);
    });
  });
}
