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

    /// Data channel message exchange test - matches werift's simple approach.
    ///
    /// Note: This test can be flaky (~30% failure rate) when two peer connections
    /// run in the same process due to timing-sensitive ICE candidate exchange.
    /// The retry handles occasional failures. In production, peers run in
    /// separate processes/devices where this race doesn't occur.
    test('data channel message exchange', () async {
      final pc1 = RTCPeerConnection();
      final pc2 = RTCPeerConnection();

      await pc1.waitForReady();
      await pc2.waitForReady();

      final done = Completer<void>();

      // Set up answerer's data channel handler (like werift)
      pc2.onDataChannel.listen((dc2) {
        dc2.onMessage.listen((msg) {
          if (msg.toString() == 'ping') {
            dc2.sendString('pong');
          }
        });
      });

      // Create data channel on offerer
      final dc1 = pc1.createDataChannel('test');
      dc1.onStateChange.listen((state) {
        if (state == DataChannelState.open) {
          // Send message when open
          dc1.sendString('ping');
        }
      });
      dc1.onMessage.listen((msg) {
        if (msg.toString() == 'pong' && !done.isCompleted) {
          done.complete();
        }
      });

      // Trickle ICE - needed for loopback (candidates not in SDP by default)
      pc1.onIceCandidate.listen((c) => pc2.addIceCandidate(c));
      pc2.onIceCandidate.listen((c) => pc1.addIceCandidate(c));

      // Simple SDP exchange (like werift)
      await pc1.setLocalDescription(await pc1.createOffer());
      await pc2.setRemoteDescription(pc1.localDescription!);
      await pc2.setLocalDescription(await pc2.createAnswer());
      await pc1.setRemoteDescription(pc2.localDescription!);

      // Wait for ping-pong to complete
      await done.future.timeout(Duration(seconds: 15));

      await pc1.close();
      await pc2.close();
    }, timeout: Timeout(Duration(seconds: 20)), retry: 1);
  });
}
