/// Connection Stability Test
///
/// Tests that a WebRTC connection remains stable for at least 20 seconds
/// with periodic message exchange to verify ongoing connectivity.
///
/// This test is tagged as 'slow' and should be run with limited concurrency:
///   dart test --tags=slow --concurrency=1
///
/// Or exclude from fast test runs:
///   dart test --exclude-tags=slow
@Tags(['slow'])
library;

import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() {
  group('Connection Stability', () {
    test('connection remains stable for 20 seconds with periodic messaging',
        () async {
      print('\n=== Starting 20-Second Stability Test ===\n');

      // Create two peer connections
      final pcOffer = RTCPeerConnection();
      final pcAnswer = RTCPeerConnection();

      // Wait for transport initialization (certificate generation)
      await Future.delayed(Duration(milliseconds: 500));

      // Track ICE candidates - MUST be set up before any SDP exchange
      // to avoid missing candidates that are emitted during setLocalDescription
      final offerCandidates = <RTCIceCandidate>[];
      final answerCandidates = <RTCIceCandidate>[];

      pcOffer.onIceCandidate.listen((candidate) {
        print(
            'Offer candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
        offerCandidates.add(candidate);
      });

      pcAnswer.onIceCandidate.listen((candidate) {
        print(
            'Answer candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
        answerCandidates.add(candidate);
      });

      // Create data channel - can now be called before connection is established
      // Returns a ProxyRTCDataChannel that will be wired to real channel when SCTP is ready
      final dc = pcOffer.createDataChannel('stability-test');

      // Track messages
      var offerMessageCount = 0;
      var answerMessageCount = 0;
      var connectionLost = false;

      // Monitor connection state
      pcOffer.onConnectionStateChange.listen((state) {
        print('Offer connection state: $state');
        if (state == PeerConnectionState.failed ||
            state == PeerConnectionState.closed) {
          connectionLost = true;
        }
      });

      pcAnswer.onConnectionStateChange.listen((state) {
        print('Answer connection state: $state');
        if (state == PeerConnectionState.failed ||
            state == PeerConnectionState.closed) {
          connectionLost = true;
        }
      });

      // Set up answer datachannel handler BEFORE SDP exchange
      pcAnswer.onDataChannel.listen((incomingDc) {
        print('Answer received data channel: ${incomingDc.label}');
        incomingDc.onMessage.listen((data) {
          answerMessageCount++;
          // Echo back
          incomingDc.send(data);
        });
      });

      // Perform offer/answer exchange
      print('Creating offer...');
      final offer = await pcOffer.createOffer();
      print('Setting local description (offer)...');
      await pcOffer.setLocalDescription(offer);

      print('Setting remote description (offer) on answer...');
      await pcAnswer.setRemoteDescription(offer);
      print('Creating answer...');
      final answer = await pcAnswer.createAnswer();
      print('Setting local description (answer)...');
      await pcAnswer.setLocalDescription(answer);
      print('Setting remote description (answer) on offer...');
      await pcOffer.setRemoteDescription(answer);

      // Wait for ICE gathering to complete
      await Future.delayed(Duration(milliseconds: 500));

      print('Offer gathered ${offerCandidates.length} candidates');
      print('Answer gathered ${answerCandidates.length} candidates');

      // Exchange ICE candidates
      for (final candidate in offerCandidates) {
        await pcAnswer.addIceCandidate(candidate);
      }
      for (final candidate in answerCandidates) {
        await pcOffer.addIceCandidate(candidate);
      }

      // Signal end of candidates
      print('Signaling end of candidates...');

      // Set up offer datachannel handler
      dc.onMessage.listen((data) {
        offerMessageCount++;
      });

      // Wait for datachannel to open
      print('Waiting for connection establishment...');
      await Future.doWhile(() async {
        await Future.delayed(Duration(milliseconds: 100));
        return dc.state != DataChannelState.open;
      }).timeout(Duration(seconds: 10));

      print('✓ Connection established!\n');
      print(
          'Starting 20-second stability test with messaging every 2 seconds...\n');

      final startTime = DateTime.now();
      final testDuration = Duration(seconds: 20);
      var messagesSent = 0;

      // Send messages every 2 seconds for 20 seconds
      while (DateTime.now().difference(startTime) < testDuration) {
        if (connectionLost) {
          fail('Connection lost during stability test');
        }

        messagesSent++;
        dc.send('Stability test message #$messagesSent'.codeUnits);

        await Future.delayed(Duration(seconds: 2));

        final elapsed = DateTime.now().difference(startTime).inSeconds;
        print('[$elapsed s] Sent: $messagesSent, Received: $offerMessageCount');
      }

      print('\n✓ 20 seconds completed!');
      print('Final stats:');
      print('  Messages sent: $messagesSent');
      print('  Messages received by offer: $offerMessageCount');
      print('  Messages received by answer: $answerMessageCount');
      print('  Connection lost: $connectionLost');

      // Verify connection stayed up
      expect(connectionLost, false, reason: 'Connection should not be lost');

      // Verify we got most messages back (allow for some in-flight)
      expect(offerMessageCount, greaterThan(messagesSent - 3),
          reason: 'Should receive most echo messages');

      // Clean up
      await pcOffer.close();
      await pcAnswer.close();

      print('\n✓ Stability test passed!\n');
    }, timeout: Timeout(Duration(seconds: 45)));
  });
}
