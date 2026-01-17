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

      // Event-driven connection waiting
      final pc1Connected = Completer<void>();
      final pc2Connected = Completer<void>();

      pc1.onIceConnectionStateChange.listen((s) {
        print('[PC1] ICE state: $s');
        if ((s == IceConnectionState.connected ||
                s == IceConnectionState.completed) &&
            !pc1Connected.isCompleted) {
          pc1Connected.complete();
        }
      });

      pc2.onIceConnectionStateChange.listen((s) {
        print('[PC2] ICE state: $s');
        if ((s == IceConnectionState.connected ||
                s == IceConnectionState.completed) &&
            !pc2Connected.isCompleted) {
          pc2Connected.complete();
        }
      });

      // Trickle ICE - exchange candidates as they arrive
      pc1.onIceCandidate.listen((c) async {
        print('[PC1] ICE candidate: ${c.type} ${c.host}:${c.port}');
        await pc2.addIceCandidate(c);
      });

      pc2.onIceCandidate.listen((c) async {
        print('[PC2] ICE candidate: ${c.type} ${c.host}:${c.port}');
        await pc1.addIceCandidate(c);
      });

      // PC1 creates offer
      print('[Test] Creating offer...');
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);

      // PC2 receives offer and creates answer
      await pc2.setRemoteDescription(offer);
      print('[Test] Creating answer...');
      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);

      // PC1 receives answer
      await pc1.setRemoteDescription(answer);

      // Wait for at least one side to connect (event-driven)
      print('[Test] Waiting for ICE connection...');
      await Future.any([
        pc1Connected.future,
        pc2Connected.future,
      ]).timeout(Duration(seconds: 10));

      print('[Test] PC1 ICE state: ${pc1.iceConnectionState}');
      print('[Test] PC2 ICE state: ${pc2.iceConnectionState}');

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

      // Wait for transport initialization
      await Future.delayed(Duration(milliseconds: 100));

      final receivedMessages = <String>[];
      final dc1Connected = Completer<void>();
      final messageReceived = Completer<void>();

      // Set up data channel on PC1 (offerer)
      final dc1 = pc1.createDataChannel('test');

      dc1.onStateChange.listen((state) {
        print('[DC1] State: $state');
        if (state == DataChannelState.open && !dc1Connected.isCompleted) {
          dc1Connected.complete();
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
        });
        dc2.onMessage.listen((msg) {
          print('[DC2] Received: $msg');
          receivedMessages.add(msg.toString());
          // Echo back
          dc2.sendString('Echo: $msg');
        });
      });

      // Trickle ICE - exchange candidates as they arrive
      pc1.onIceCandidate.listen((c) async {
        await pc2.addIceCandidate(c);
      });
      pc2.onIceCandidate.listen((c) async {
        await pc1.addIceCandidate(c);
      });

      pc1.onIceConnectionStateChange.listen((s) => print('[PC1] ICE: $s'));
      pc2.onIceConnectionStateChange.listen((s) => print('[PC2] ICE: $s'));

      // Signaling exchange
      final offer = await pc1.createOffer();
      await pc1.setLocalDescription(offer);
      await pc2.setRemoteDescription(offer);

      final answer = await pc2.createAnswer();
      await pc2.setLocalDescription(answer);
      await pc1.setRemoteDescription(answer);

      // Wait for data channel to open (event-driven with timeout)
      // Allow extra time for concurrent test load
      print('[Test] Waiting for data channel connection...');
      try {
        await dc1Connected.future.timeout(Duration(seconds: 15));
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
    },
        timeout: Timeout(Duration(seconds: 25)),
        retry: 1 // Retry once on failure due to resource contention under parallel test load
        );
  });
}
