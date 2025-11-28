/// Connection Stability Test
///
/// Tests that a WebRTC connection remains stable for at least 60 seconds
/// with periodic message exchange to verify ongoing connectivity.

import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() {
  group('Connection Stability', () {
    test('connection remains stable for 60 seconds with periodic messaging',
        () async {
      print('\n=== Starting 60-Second Stability Test ===\n');

      // Create two peer connections
      final pcOffer = RtcPeerConnection();
      final pcAnswer = RtcPeerConnection();

      // Wait for transport initialization (certificate generation, SCTP setup)
      await Future.delayed(Duration(milliseconds: 1000));

      // Track messages
      var offerMessageCount = 0;
      var answerMessageCount = 0;
      var connectionLost = false;

      // Monitor connection state
      pcOffer.onConnectionStateChange.listen((state) {
        if (state == PeerConnectionState.failed ||
            state == PeerConnectionState.closed) {
          connectionLost = true;
        }
      });

      pcAnswer.onConnectionStateChange.listen((state) {
        if (state == PeerConnectionState.failed ||
            state == PeerConnectionState.closed) {
          connectionLost = true;
        }
      });

      // Perform offer/answer exchange
      final offerDc = pcOffer.createDataChannel('stability-test');
      final offer = await pcOffer.createOffer();
      await pcOffer.setLocalDescription(offer);

      // Set up answer datachannel handler
      DataChannel? answerDc;
      pcAnswer.onDataChannel.listen((dc) {
        answerDc = dc;
        dc.onMessage.listen((data) {
          answerMessageCount++;
          // Echo back
          dc.send(data);
        });
      });

      await pcAnswer.setRemoteDescription(offer);
      final answer = await pcAnswer.createAnswer();
      await pcAnswer.setLocalDescription(answer);
      await pcOffer.setRemoteDescription(answer);

      // Exchange ICE candidates
      pcOffer.onIceCandidate.listen((candidate) async {
        await pcAnswer.addIceCandidate(candidate);
      });

      pcAnswer.onIceCandidate.listen((candidate) async {
        await pcOffer.addIceCandidate(candidate);
      });

      // Set up offer datachannel handler
      offerDc.onMessage.listen((data) {
        offerMessageCount++;
      });

      // Wait for datachannel to open
      print('Waiting for connection establishment...');
      await Future.doWhile(() async {
        await Future.delayed(Duration(milliseconds: 100));
        return offerDc.state != DataChannelState.open;
      }).timeout(Duration(seconds: 10));

      print('✓ Connection established!\n');
      print('Starting 60-second stability test with messaging every 2 seconds...\n');

      final startTime = DateTime.now();
      final testDuration = Duration(seconds: 60);
      var messagesSent = 0;

      // Send messages every 2 seconds for 60 seconds
      while (DateTime.now().difference(startTime) < testDuration) {
        if (connectionLost) {
          fail('Connection lost during stability test');
        }

        messagesSent++;
        offerDc.send('Stability test message #$messagesSent'.codeUnits);

        await Future.delayed(Duration(seconds: 2));

        final elapsed = DateTime.now().difference(startTime).inSeconds;
        print('[$elapsed s] Sent: $messagesSent, Received: $offerMessageCount');
      }

      print('\n✓ 60 seconds completed!');
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
    }, timeout: Timeout(Duration(seconds: 90)));
  });
}
