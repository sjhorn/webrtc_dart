/// Loopback connection test - two Dart PeerConnections connected to each other
/// This tests the full ICE → DTLS → SCTP → RTCDataChannel stack in isolation
library;

import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() {
  group('Loopback Connection', () {
    test('two peer connections exchange ICE candidates and connect', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      // Collect ICE candidates from each peer
      final pc1Candidates = <RTCIceCandidate>[];
      final pc2Candidates = <RTCIceCandidate>[];

      pc1.onIceCandidate.listen((c) {
        print('[PC1] ICE candidate: ${c.type} ${c.host}:${c.port}');
        pc1Candidates.add(c);
      });

      pc2.onIceCandidate.listen((c) {
        print('[PC2] ICE candidate: ${c.type} ${c.host}:${c.port}');
        pc2Candidates.add(c);
      });

      // Track connection states
      pc1.onIceConnectionStateChange
          .listen((s) => print('[PC1] ICE state: $s'));
      pc2.onIceConnectionStateChange
          .listen((s) => print('[PC2] ICE state: $s'));
      pc1.onConnectionStateChange
          .listen((s) => print('[PC1] Connection state: $s'));
      pc2.onConnectionStateChange
          .listen((s) => print('[PC2] Connection state: $s'));

      // Wait for initialization
      await Future.delayed(Duration(milliseconds: 100));

      // PC1 creates offer
      print('[Test] Creating offer...');
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);

      // PC2 receives offer
      await pc2.setRemoteDescription(offer);

      // PC2 creates answer
      print('[Test] Creating answer...');
      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);

      // PC1 receives answer
      await pc1.setRemoteDescription(answer);

      // Wait for ICE gathering
      await Future.delayed(Duration(milliseconds: 500));

      // Exchange ICE candidates
      print(
          '[Test] Exchanging ${pc1Candidates.length} + ${pc2Candidates.length} ICE candidates...');
      for (final c in pc1Candidates) {
        await pc2.addIceCandidate(c);
      }
      for (final c in pc2Candidates) {
        await pc1.addIceCandidate(c);
      }

      // Wait for connection
      print('[Test] Waiting for ICE connection...');
      await Future.delayed(Duration(seconds: 3));

      print('[Test] PC1 ICE state: ${pc1.iceConnectionState}');
      print('[Test] PC2 ICE state: ${pc2.iceConnectionState}');
      print('[Test] PC1 Connection state: ${pc1.connectionState}');
      print('[Test] PC2 Connection state: ${pc2.connectionState}');

      // Verify at least one side connected
      expect(
        pc1.iceConnectionState == IceConnectionState.connected ||
            pc1.iceConnectionState == IceConnectionState.completed ||
            pc2.iceConnectionState == IceConnectionState.connected ||
            pc2.iceConnectionState == IceConnectionState.completed,
        isTrue,
        reason: 'At least one peer should reach connected state',
      );

      await pc1.close();
      await pc2.close();
    }, timeout: Timeout(Duration(seconds: 15)));

    test('data channel message exchange', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      final receivedMessages = <String>[];
      final pc1Connected = Completer<void>();
      final pc2Connected = Completer<void>();
      final messageReceived = Completer<void>();

      // Set up data channel on PC1 (offerer)
      await Future.delayed(Duration(milliseconds: 100));
      final dc1 = pc1.createDataChannel('test');

      dc1.onStateChange.listen((state) {
        print('[DC1] State: $state');
        if (state == DataChannelState.open && !pc1Connected.isCompleted) {
          pc1Connected.complete();
        }
      });

      dc1.onMessage.listen((msg) {
        print('[DC1] Received: $msg');
        receivedMessages.add(msg.toString());
        if (!messageReceived.isCompleted) {
          messageReceived.complete();
        }
      });

      // Set up data channel handler on PC2 (answerer)
      pc2.onDataChannel.listen((dc2) {
        print('[DC2] Received data channel: ${dc2.label}');
        dc2.onStateChange.listen((state) {
          print('[DC2] State: $state');
          if (state == DataChannelState.open && !pc2Connected.isCompleted) {
            pc2Connected.complete();
          }
        });
        dc2.onMessage.listen((msg) {
          print('[DC2] Received: $msg');
          receivedMessages.add(msg.toString());
          // Echo back
          dc2.sendString('Echo: $msg');
        });
      });

      // Collect and exchange ICE candidates
      final pc1Candidates = <RTCIceCandidate>[];
      final pc2Candidates = <RTCIceCandidate>[];
      pc1.onIceCandidate.listen((c) => pc1Candidates.add(c));
      pc2.onIceCandidate.listen((c) => pc2Candidates.add(c));

      pc1.onIceConnectionStateChange.listen((s) => print('[PC1] ICE: $s'));
      pc2.onIceConnectionStateChange.listen((s) => print('[PC2] ICE: $s'));

      // Signaling exchange
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);

      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      // Wait for ICE gathering
      await Future.delayed(Duration(milliseconds: 500));

      // Exchange candidates
      for (final c in pc1Candidates) {
        await pc2.addIceCandidate(c);
      }
      for (final c in pc2Candidates) {
        await pc1.addIceCandidate(c);
      }

      // Wait for data channel to open (with timeout)
      print('[Test] Waiting for data channel connection...');
      try {
        await pc1Connected.future.timeout(Duration(seconds: 10));
        print('[Test] DC1 connected!');

        // Send a message
        dc1.sendString('Hello from PC1');

        await messageReceived.future.timeout(Duration(seconds: 5));
        print('[Test] Message received!');

        expect(receivedMessages, contains('Echo: Hello from PC1'));
      } catch (e) {
        print('[Test] Timeout or error: $e');
        print('[Test] PC1 ICE: ${pc1.iceConnectionState}');
        print('[Test] PC2 ICE: ${pc2.iceConnectionState}');
        print('[Test] DC1 state: ${dc1.state}');
        fail('Data channel communication failed: $e');
      }

      await pc1.close();
      await pc2.close();
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
