/// Close PeerConnection Example
///
/// This example demonstrates proper PeerConnection closing behavior.
/// It shows how closing a PeerConnection affects associated DataChannels
/// and the state transitions that occur.
///
/// Usage: dart run examples/close_peerconnection.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Close PeerConnection Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final pc1 = RtcPeerConnection();
  final pc2 = RtcPeerConnection();

  // Wait for transport initialization
  await Future.delayed(Duration(milliseconds: 500));

  // Track data channels (dynamic - can be DataChannel or ProxyDataChannel)
  late dynamic dc1;
  late dynamic dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Track state changes
  final pc1States = <PeerConnectionState>[];
  final pc2States = <PeerConnectionState>[];
  final dc1States = <DataChannelState>[];
  final dc2States = <DataChannelState>[];

  // Monitor peer connection states
  pc1.onConnectionStateChange.listen((state) {
    print('[PC1] Connection state: $state');
    pc1States.add(state);
  });

  pc2.onConnectionStateChange.listen((state) {
    print('[PC2] Connection state: $state');
    pc2States.add(state);
  });

  // Set up ICE candidate exchange
  pc1.onIceCandidate.listen((candidate) async {
    await pc2.addIceCandidate(candidate);
  });

  pc2.onIceCandidate.listen((candidate) async {
    await pc1.addIceCandidate(candidate);
  });

  // Handle incoming datachannel on pc2
  pc2.onDataChannel.listen((channel) {
    dc2 = channel;
    print('[DC2] Received DataChannel: ${channel.label}');

    channel.onStateChange.listen((state) {
      print('[DC2] State changed: $state');
      dc2States.add(state);
      if (state == DataChannelState.open && !dc2Ready.isCompleted) {
        dc2Ready.complete();
      }
    });

    channel.onMessage.listen((data) {
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[DC2] Received: $msg');
      if (channel.state == DataChannelState.open) {
        channel.sendString('pong');
      }
    });

    if (channel.state == DataChannelState.open) {
      dc2States.add(channel.state);
      if (!dc2Ready.isCompleted) dc2Ready.complete();
    }
  });

  // Create datachannel on pc1
  dc1 = pc1.createDataChannel('test');
  print('[DC1] Created DataChannel: ${dc1.label}');

  dc1.onStateChange.listen((state) {
    print('[DC1] State changed: $state');
    dc1States.add(state);
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  dc1.onMessage.listen((data) {
    final msg = data is String ? data : String.fromCharCodes(data);
    print('[DC1] Received: $msg');
  });

  // Perform offer/answer exchange
  print('');
  print('--- Establishing Connection ---');
  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  await pc2.setRemoteDescription(offer);

  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  await pc1.setRemoteDescription(answer);

  // Wait for connection
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('');
  print('Connection established!');
  print('');

  // Send some messages
  print('--- Exchanging Messages ---');
  await dc1.sendString('ping 1');
  await Future.delayed(Duration(milliseconds: 200));
  await dc1.sendString('ping 2');
  await Future.delayed(Duration(milliseconds: 200));
  await dc1.sendString('ping 3');
  await Future.delayed(Duration(milliseconds: 500));

  // Show current states before close
  print('');
  print('States before close:');
  print('  PC1: ${pc1.connectionState}, signaling: ${pc1.signalingState}');
  print('  PC2: ${pc2.connectionState}, signaling: ${pc2.signalingState}');
  print('  DC1: ${dc1.state}');
  print('  DC2: ${dc2.state}');

  // Close pc1 (should cascade to DC and affect pc2)
  print('');
  print('--- Closing PC1 ---');
  print('[PC1] Calling close()...');

  // Clear state tracking
  pc1States.clear();
  pc2States.clear();

  await pc1.close();

  // Give time for close to propagate
  await Future.delayed(Duration(seconds: 1));

  // Show final states
  print('');
  print('States after PC1 close:');
  print('  PC1: ${pc1.connectionState}, signaling: ${pc1.signalingState}');
  print('  PC2: ${pc2.connectionState}, signaling: ${pc2.signalingState}');
  print('  DC1: ${dc1.state}');
  print('  DC2: ${dc2.state}');

  // Summary
  print('');
  print('--- Summary ---');
  print('PC1 state transitions: ${pc1States.map((s) => s.name).join(" -> ")}');
  print('PC2 state transitions: ${pc2States.map((s) => s.name).join(" -> ")}');
  print('DC1 state transitions: ${dc1States.map((s) => s.name).join(" -> ")}');
  print('DC2 state transitions: ${dc2States.map((s) => s.name).join(" -> ")}');

  final pc1Closed = pc1.connectionState == PeerConnectionState.closed;
  final signalingClosed = pc1.signalingState == SignalingState.closed;

  print('');
  if (pc1Closed && signalingClosed) {
    print('SUCCESS: PeerConnection closed properly!');
    print('  - Connection state: closed');
    print('  - Signaling state: closed');
  } else {
    print('Close status:');
    print('  - Connection closed: $pc1Closed');
    print('  - Signaling closed: $signalingClosed');
  }

  // Cleanup pc2
  print('');
  print('Closing PC2...');
  await pc2.close();
  print('Done.');
}
