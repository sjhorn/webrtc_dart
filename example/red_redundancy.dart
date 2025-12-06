/// RED (Redundancy Encoding) Example
///
/// This example demonstrates RED (RFC 2198) which provides redundancy
/// for audio streams by including previous audio frames in each packet.
/// This helps recover from packet loss without retransmission delay.
///
/// Usage: dart run examples/red_redundancy.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RED (Redundancy Encoding) Example');
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

  // Create audio track
  print('Creating audio track with RED support...');
  final audioTrack = AudioStreamTrack(
    id: 'red-audio',
    label: 'RED Audio',
  );

  // Add track to sender
  sender.addTrack(audioTrack);

  // Handle incoming tracks on receiver
  receiver.onTrack.listen((transceiver) {
    print(
        '[Receiver] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
  });

  // Perform offer/answer exchange
  print('');
  print('Performing offer/answer exchange...');

  final offer = await sender.createOffer();
  print('[Sender] Created offer');

  // Log RED-related SDP lines
  print('');
  print('--- RED in SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.toLowerCase().contains('red') ||
        line.contains('OPUS') ||
        line.contains('opus')) {
      print('  $line');
    }
  }

  await sender.setLocalDescription(offer);
  await receiver.setRemoteDescription(offer);

  final answer = await receiver.createAnswer();
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

  // Explain RED mechanism
  print('');
  print('--- RED Mechanism (RFC 2198) ---');
  print('RED provides redundancy for audio streams:');
  print('  1. Each RED packet contains the current audio frame');
  print('  2. Plus one or more previous audio frames as redundancy');
  print('  3. If a packet is lost, the redundant copy in the next');
  print('     packet can be used for recovery');
  print('  4. This adds latency equal to packet interval but');
  print('     enables loss recovery without RTT delay');
  print('');
  print('RED packet structure:');
  print(
      '  [Header] [Redundant Block N-2] [Redundant Block N-1] [Primary Block N]');
  print('');
  print('SDP negotiation includes:');
  print('  - a=rtpmap:<PT> red/48000/2 (RED codec)');
  print('  - RED wraps the primary codec (e.g., Opus)');

  // Summary
  print('');
  print('--- Summary ---');
  print('Sender connection: ${sender.connectionState}');
  print('Receiver connection: ${receiver.connectionState}');

  if (sender.connectionState == PeerConnectionState.connected) {
    print('');
    print('SUCCESS: RED-capable audio connection established!');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await sender.close();
  await receiver.close();
  print('Done.');
}
