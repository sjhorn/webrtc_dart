/// ICE Trickle Example
///
/// This example demonstrates trickle ICE, where ICE candidates are
/// exchanged incrementally as they are gathered, rather than waiting
/// for all candidates to be collected before signaling.
///
/// Usage: dart run examples/ice_trickle.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('ICE Trickle Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final pc1 = RTCPeerConnection();
  final pc2 = RTCPeerConnection();

  // Track candidates
  final candidatesFromPc1 = <RTCIceCandidate>[];
  final candidatesFromPc2 = <RTCIceCandidate>[];

  // Track data channels
  late RTCDataChannel dc1;
  late RTCDataChannel dc2;

  final dc1Ready = Completer<void>();
  final dc2Ready = Completer<void>();

  // Completers for ICE gathering complete
  final pc1GatheringComplete = Completer<void>();
  final pc2GatheringComplete = Completer<void>();

  // Monitor ICE gathering state
  pc1.onIceGatheringStateChange.listen((state) {
    print('[PC1] ICE gathering state: $state');
    if (state == IceGatheringState.complete &&
        !pc1GatheringComplete.isCompleted) {
      pc1GatheringComplete.complete();
    }
  });

  pc2.onIceGatheringStateChange.listen((state) {
    print('[PC2] ICE gathering state: $state');
    if (state == IceGatheringState.complete &&
        !pc2GatheringComplete.isCompleted) {
      pc2GatheringComplete.complete();
    }
  });

  // Set up trickle ICE candidate exchange
  // Candidates are sent immediately as they are gathered
  pc1.onIceCandidate.listen((candidate) {
    candidatesFromPc1.add(candidate);
    final sdp = candidate.toSdp();
    final preview = sdp.length > 50 ? '${sdp.substring(0, 50)}...' : sdp;
    print('[PC1] Trickled candidate #${candidatesFromPc1.length}: $preview');

    // In a real app, this would be sent over signaling
    // Here we add it immediately to pc2
    pc2.addIceCandidate(candidate);
  });

  pc2.onIceCandidate.listen((candidate) {
    candidatesFromPc2.add(candidate);
    final sdp = candidate.toSdp();
    final preview = sdp.length > 50 ? '${sdp.substring(0, 50)}...' : sdp;
    print('[PC2] Trickled candidate #${candidatesFromPc2.length}: $preview');

    // In a real app, this would be sent over signaling
    // Here we add it immediately to pc1
    pc1.addIceCandidate(candidate);
  });

  // Monitor ICE connection state
  pc1.onIceConnectionStateChange.listen((state) {
    print('[PC1] ICE connection state: $state');
  });

  pc2.onIceConnectionStateChange.listen((state) {
    print('[PC2] ICE connection state: $state');
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
  dc1 = pc1.createDataChannel('trickle-test') as RTCDataChannel;
  dc1.onStateChange.listen((state) {
    if (state == DataChannelState.open && !dc1Ready.isCompleted) {
      dc1Ready.complete();
    }
  });

  print('--- Trickle ICE Signaling ---');
  print('');

  // Step 1: Create and set local offer (this starts candidate gathering)
  print('Step 1: PC1 creates offer (starts gathering)');
  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  print('  Offer created, candidates will trickle in...');

  // Step 2: PC2 sets remote description and creates answer
  print('');
  print('Step 2: PC2 receives offer, creates answer (starts gathering)');
  await pc2.setRemoteDescription(offer);
  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  print('  Answer created, candidates will trickle in...');

  // Step 3: PC1 sets remote answer
  print('');
  print('Step 3: PC1 receives answer');
  await pc1.setRemoteDescription(answer);

  // Wait for gathering to complete (or timeout)
  print('');
  print('Waiting for ICE gathering to complete...');
  try {
    await Future.wait([
      pc1GatheringComplete.future,
      pc2GatheringComplete.future,
    ]).timeout(Duration(seconds: 10));
  } catch (e) {
    print('Gathering timeout (may be normal if candidates already exchanged)');
  }

  // Wait for DataChannels to be ready
  print('');
  print('Waiting for RTCDataChannel connection...');
  await Future.wait([dc1Ready.future, dc2Ready.future])
      .timeout(Duration(seconds: 10));

  print('');
  print('RTCDataChannel connected!');

  // Verify connectivity
  final responseCompleter = Completer<void>();
  dc2.onMessage.listen((data) {
    final msg = String.fromCharCodes(data);
    print('[PC2] Received: $msg');
    dc2.sendString('pong');
  });

  dc1.onMessage.listen((data) {
    final msg = String.fromCharCodes(data);
    print('[PC1] Received: $msg');
    if (!responseCompleter.isCompleted) responseCompleter.complete();
  });

  dc1.sendString('ping');
  await responseCompleter.future.timeout(Duration(seconds: 5));

  // Summary
  print('');
  print('--- Summary ---');
  print('Candidates trickled from PC1: ${candidatesFromPc1.length}');
  print('Candidates trickled from PC2: ${candidatesFromPc2.length}');
  print('');
  print('PC1 final ICE state: ${pc1.iceConnectionState}');
  print('PC2 final ICE state: ${pc2.iceConnectionState}');

  // Categorize candidates
  final hostCandidates =
      candidatesFromPc1.where((c) => c.type == 'host').length +
          candidatesFromPc2.where((c) => c.type == 'host').length;
  final srflxCandidates =
      candidatesFromPc1.where((c) => c.type == 'srflx').length +
          candidatesFromPc2.where((c) => c.type == 'srflx').length;
  final relayCandidates =
      candidatesFromPc1.where((c) => c.type == 'relay').length +
          candidatesFromPc2.where((c) => c.type == 'relay').length;

  print('');
  print('RTCIceCandidate types:');
  print('  Host: $hostCandidates');
  print('  Server Reflexive: $srflxCandidates');
  print('  Relay: $relayCandidates');

  if (pc1.iceConnectionState == IceConnectionState.connected ||
      pc1.iceConnectionState == IceConnectionState.completed) {
    print('');
    print('SUCCESS: Trickle ICE connection established!');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await pc1.close();
  await pc2.close();
  print('Done.');
}
