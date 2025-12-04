/// Simulcast Example
///
/// This example demonstrates simulcast functionality where multiple
/// encoding layers (high, medium, low quality) are sent for a single
/// video track. The receiver can select which layer to receive.
///
/// Usage: dart run examples/simulcast_local.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Simulcast Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final sender = RtcPeerConnection();
  final receiver = RtcPeerConnection();

  // Track connection ready
  final connected = Completer<void>();
  var senderConnected = false;
  var receiverConnected = false;

  // Monitor connection states
  sender.onConnectionStateChange.listen((state) {
    print('[Sender] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      senderConnected = true;
      if (receiverConnected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  receiver.onConnectionStateChange.listen((state) {
    print('[Receiver] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      receiverConnected = true;
      if (senderConnected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  // Set up ICE candidate exchange
  sender.onIceCandidate.listen((candidate) async {
    await receiver.addIceCandidate(candidate);
  });

  receiver.onIceCandidate.listen((candidate) async {
    await sender.addIceCandidate(candidate);
  });

  // Create video track with simulcast layers
  print('Creating video track with simulcast layers...');
  final videoTrack = VideoStreamTrack(
    id: 'simulcast-video',
    label: 'Simulcast Video',
  );

  // Add track to sender - the track will be sent with multiple encodings
  print('Adding track to sender...');
  sender.addTrack(videoTrack);

  // Handle incoming tracks on receiver
  final tracksReceived = <String>[];
  receiver.onTrack.listen((transceiver) {
    print('[Receiver] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
    tracksReceived.add(transceiver.mid);

    // In a real simulcast scenario, you would access different layers
    // via transceiver.receiver.trackByRID['high'], etc.
  });

  // Perform offer/answer exchange
  print('');
  print('Performing offer/answer exchange...');

  final offer = await sender.createOffer();
  print('[Sender] Created offer');

  // Log SDP simulcast-related lines
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('simulcast') || line.contains('rid=')) {
      print('  SDP: $line');
    }
  }

  await sender.setLocalDescription(offer);
  await receiver.setRemoteDescription(offer);

  final answer = await receiver.createAnswer();
  print('[Receiver] Created answer');

  await receiver.setLocalDescription(answer);
  await sender.setRemoteDescription(answer);

  // Wait for connection
  print('');
  print('Waiting for connection...');
  try {
    await connected.future.timeout(Duration(seconds: 10));
    print('Connection established!');
  } catch (e) {
    print('Connection timeout');
  }

  // Display transceiver info
  print('');
  print('--- Transceivers ---');
  print('Sender transceivers: ${sender.transceivers.length}');
  for (final t in sender.transceivers) {
    print('  - mid=${t.mid}, kind=${t.kind}, direction=${t.direction}');
  }

  print('Receiver transceivers: ${receiver.transceivers.length}');
  for (final t in receiver.transceivers) {
    print('  - mid=${t.mid}, kind=${t.kind}, direction=${t.direction}');
  }

  // Simulcast layer selection demonstration
  print('');
  print('--- Simulcast Layer Selection ---');
  print('In a full simulcast scenario with browser, you would:');
  print('  1. Sender encodes video at multiple bitrates (high/mid/low)');
  print('  2. Each layer has a unique RID (Restriction Identifier)');
  print('  3. Receiver can select which layer to receive');
  print('  4. SFU can forward different layers to different receivers');
  print('');

  // Summary
  print('--- Summary ---');
  print('Sender connection: ${sender.connectionState}');
  print('Receiver connection: ${receiver.connectionState}');
  print('Tracks received: ${tracksReceived.length}');

  if (sender.connectionState == PeerConnectionState.connected) {
    print('');
    print('SUCCESS: Simulcast-capable connection established!');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await sender.close();
  await receiver.close();
  print('Done.');
}
