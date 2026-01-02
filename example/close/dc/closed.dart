/// Close RTCDataChannel Example
///
/// This example demonstrates proper RTCDataChannel closing behavior.
/// It shows how to gracefully close a RTCDataChannel and observe
/// the state transitions.
///
/// Usage: dart run examples/close_datachannel.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Close RTCDataChannel Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final pc1 = RTCPeerConnection();
  final pc2 = RTCPeerConnection();

  // Wait for transport initialization
  await Future.delayed(Duration(milliseconds: 500));

  // Track data channels (dynamic - can be RTCDataChannel or ProxyDataChannel)
  late dynamic dc1;
  late dynamic dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Track state changes
  final dc1States = <DataChannelState>[];
  final dc2States = <DataChannelState>[];

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
    print('[DC2] Received RTCDataChannel: ${channel.label}');

    channel.onStateChange.listen((state) {
      print('[DC2] State changed: $state');
      dc2States.add(state);
      if (state == DataChannelState.open && !dc2Ready.isCompleted) {
        dc2Ready.complete();
      }
    });

    // Echo messages back
    channel.onMessage.listen((data) {
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[DC2] Received message: $msg');
      if (channel.state == DataChannelState.open) {
        channel.sendString('echo: $msg');
      }
    });

    if (channel.state == DataChannelState.open) {
      dc2States.add(channel.state);
      if (!dc2Ready.isCompleted) dc2Ready.complete();
    }
  });

  // Create datachannel on pc1
  dc1 = pc1.createDataChannel('closing-test');
  print('[DC1] Created RTCDataChannel: ${dc1.label}');

  dc1.onStateChange.listen((state) {
    print('[DC1] State changed: $state');
    dc1States.add(state);
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  dc1.onMessage.listen((data) {
    final msg = data is String ? data : String.fromCharCodes(data);
    print('[DC1] Received message: $msg');
  });

  // Perform offer/answer exchange
  print('');
  print('Establishing connection...');
  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  await pc2.setRemoteDescription(offer);

  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  await pc1.setRemoteDescription(answer);

  // Wait for datachannels to be ready
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('');
  print('RTCDataChannel connected!');
  print('');

  // Send some messages before closing
  print('--- Sending Messages ---');
  for (var i = 0; i < 3; i++) {
    await dc1.sendString('message $i');
    await Future.delayed(Duration(milliseconds: 200));
  }

  await Future.delayed(Duration(milliseconds: 500));

  // Close the datachannel from dc1 side
  print('');
  print('--- Closing RTCDataChannel ---');
  print('[DC1] Calling close()...');

  // Track close completion
  final dc1Closed = Completer<void>();
  final dc2Closed = Completer<void>();

  final dc1CloseSub = dc1.onStateChange.listen((state) {
    if (state == DataChannelState.closed && !dc1Closed.isCompleted) {
      dc1Closed.complete();
    }
  });

  final dc2CloseSub = dc2.onStateChange.listen((state) {
    if (state == DataChannelState.closed && !dc2Closed.isCompleted) {
      dc2Closed.complete();
    }
  });

  // Close from dc1 side
  await dc1.close();

  // Wait for both sides to see close
  print('Waiting for close to propagate...');
  try {
    await Future.wait([
      dc1Closed.future,
      dc2Closed.future,
    ]).timeout(Duration(seconds: 5));
    print('Both channels closed.');
  } catch (e) {
    print('Close timeout (checking states...)');
  }

  await dc1CloseSub.cancel();
  await dc2CloseSub.cancel();

  // Summary
  print('');
  print('--- Summary ---');
  print('DC1 final state: ${dc1.state}');
  print('DC2 final state: ${dc2.state}');
  print('');
  print('DC1 state transitions: ${dc1States.map((s) => s.name).join(" -> ")}');
  print('DC2 state transitions: ${dc2States.map((s) => s.name).join(" -> ")}');

  final success = dc1.state == DataChannelState.closed &&
      dc2.state == DataChannelState.closed;

  if (success) {
    print('');
    print('SUCCESS: RTCDataChannel closed gracefully on both sides!');
  } else {
    print('');
    print('Note: Close may still be propagating');
  }

  // Note: PeerConnection is still connected
  print('');
  print('Connection state after DC close:');
  print('  PC1: ${pc1.connectionState}');
  print('  PC2: ${pc2.connectionState}');

  // Cleanup
  print('');
  print('Closing peer connections...');
  await pc1.close();
  await pc2.close();
  print('Done.');
}
