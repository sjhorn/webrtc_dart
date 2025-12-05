/// RTX Retransmission Example
///
/// This example demonstrates RTX (Retransmission) functionality.
/// RTX allows lost RTP packets to be retransmitted using a separate
/// SSRC and payload type, enabling better packet loss recovery.
///
/// Usage: dart run examples/rtx_retransmission.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RTX Retransmission Example');
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

  // Create video track
  print('Creating video track...');
  final videoTrack = VideoStreamTrack(
    id: 'rtx-video',
    label: 'RTX Video',
  );

  // Add track to sender
  sender.addTrack(videoTrack);

  // Handle incoming tracks on receiver
  receiver.onTrack.listen((transceiver) {
    print('[Receiver] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
  });

  // Perform offer/answer exchange
  print('');
  print('Performing offer/answer exchange...');

  final offer = await sender.createOffer();
  print('[Sender] Created offer');

  // Log RTX-related SDP lines
  print('');
  print('--- RTX in SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('rtx') ||
        line.contains('apt=') ||
        line.contains('ssrc-group:FID')) {
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

  // Explain RTX mechanism
  print('');
  print('--- RTX Mechanism ---');
  print('RTX (Retransmission) works as follows:');
  print('  1. Original video uses primary SSRC and payload type');
  print('  2. RTX uses separate SSRC and payload type (apt=<original PT>)');
  print('  3. When receiver detects packet loss, it sends NACK');
  print('  4. Sender retransmits lost packet via RTX stream');
  print('  5. RTX packet wraps original RTP with RTX header');
  print('');
  print('SDP negotiation includes:');
  print('  - a=rtpmap:<PT> rtx/90000 (RTX codec)');
  print('  - a=fmtp:<PT> apt=<original PT> (associated payload type)');
  print('  - a=ssrc-group:FID <primary SSRC> <RTX SSRC>');

  // Summary
  print('');
  print('--- Summary ---');
  print('Sender connection: ${sender.connectionState}');
  print('Receiver connection: ${receiver.connectionState}');
  print('Sender transceivers: ${sender.transceivers.length}');
  print('Receiver transceivers: ${receiver.transceivers.length}');

  if (sender.connectionState == PeerConnectionState.connected) {
    print('');
    print('SUCCESS: RTX-capable connection established!');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await sender.close();
  await receiver.close();
  print('Done.');
}
