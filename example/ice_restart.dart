/// ICE Restart Example
///
/// This example demonstrates ICE restart functionality between two
/// local peer connections. ICE restart generates new ICE credentials
/// and re-establishes connectivity.
///
/// Usage: dart run examples/ice_restart.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('ICE Restart Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final pc1 = RtcPeerConnection();
  final pc2 = RtcPeerConnection();

  // Track data channels
  late DataChannel dc1;
  late DataChannel dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Track ICE states
  final iceStates1 = <IceConnectionState>[];
  final iceStates2 = <IceConnectionState>[];

  // Set up ICE state monitoring
  pc1.onIceConnectionStateChange.listen((state) {
    print('[PC1] ICE state: $state');
    iceStates1.add(state);
  });

  pc2.onIceConnectionStateChange.listen((state) {
    print('[PC2] ICE state: $state');
    iceStates2.add(state);
  });

  // Set up connection state monitoring
  pc1.onConnectionStateChange.listen((state) {
    print('[PC1] Connection state: $state');
  });

  pc2.onConnectionStateChange.listen((state) {
    print('[PC2] Connection state: $state');
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
    if (channel.state == DataChannelState.open) {
      if (!dc2Ready.isCompleted) dc2Ready.complete();
    } else {
      channel.onStateChange.listen((state) {
        if (state == DataChannelState.open && !dc2Ready.isCompleted) {
          dc2Ready.complete();
        }
      });
    }
  });

  // Create datachannel on pc1
  dc1 = pc1.createDataChannel('test') as DataChannel;
  dc1.onStateChange.listen((state) {
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  // Initial offer/answer exchange
  print('--- Initial Connection ---');
  final offer1 = await pc1.createOffer();
  await pc1.setLocalDescription(offer1);
  await pc2.setRemoteDescription(offer1);

  final answer1 = await pc2.createAnswer();
  await pc2.setLocalDescription(answer1);
  await pc1.setRemoteDescription(answer1);

  // Wait for connection
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('');
  print('Initial connection established!');
  print('PC1 ICE state: ${pc1.iceConnectionState}');
  print('PC2 ICE state: ${pc2.iceConnectionState}');

  // Verify connectivity
  final testCompleter = Completer<void>();
  dc2.onMessage.listen((data) {
    if (!testCompleter.isCompleted) testCompleter.complete();
  });

  dc1.sendString('test before restart');
  await testCompleter.future.timeout(Duration(seconds: 5));
  print('Data channel working before restart.');

  // Perform ICE restart
  print('');
  print('--- ICE Restart ---');
  print('Triggering ICE restart on PC1...');

  // Clear state tracking for restart
  iceStates1.clear();
  iceStates2.clear();

  // Request ICE restart
  pc1.restartIce();

  // Create new offer with ICE restart
  final offer2 = await pc1.createOffer(RtcOfferOptions(iceRestart: true));
  print('Created new offer with ICE restart');

  await pc1.setLocalDescription(offer2);
  await pc2.setRemoteDescription(offer2);

  final answer2 = await pc2.createAnswer();
  await pc2.setLocalDescription(answer2);
  await pc1.setRemoteDescription(answer2);

  // Wait for ICE to re-establish
  await Future.delayed(Duration(seconds: 2));

  print('');
  print('ICE restart completed!');
  print('PC1 ICE state: ${pc1.iceConnectionState}');
  print('PC2 ICE state: ${pc2.iceConnectionState}');

  // Verify connectivity after restart
  final testCompleter2 = Completer<void>();
  late final StreamSubscription sub;
  sub = dc2.onMessage.listen((data) {
    if (!testCompleter2.isCompleted) {
      testCompleter2.complete();
      sub.cancel();
    }
  });

  dc1.sendString('test after restart');
  try {
    await testCompleter2.future.timeout(Duration(seconds: 5));
    print('Data channel working after restart.');
  } catch (e) {
    print('Warning: Data channel test after restart timed out');
  }

  // Summary
  print('');
  print('--- Summary ---');
  print('ICE states observed on PC1: ${iceStates1.map((s) => s.name).join(" -> ")}');
  print('ICE states observed on PC2: ${iceStates2.map((s) => s.name).join(" -> ")}');

  final success = pc1.iceConnectionState == IceConnectionState.connected ||
      pc1.iceConnectionState == IceConnectionState.completed;

  if (success) {
    print('');
    print('SUCCESS: ICE restart completed successfully!');
  } else {
    print('');
    print('WARNING: ICE may not have fully re-established');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await pc1.close();
  await pc2.close();
  print('Done.');
}
