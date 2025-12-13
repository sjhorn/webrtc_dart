/// MediaChannel Send/Receive Example
///
/// This example demonstrates bidirectional media (send and receive).
/// Creates transceivers for both video and audio with sendrecv direction.
///
/// Usage: dart run example/mediachannel/sendrecv/offer.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('MediaChannel Send/Receive Example');
  print('=' * 50);

  // Create peer connection with STUN
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  pc.onIceConnectionStateChange.listen((state) {
    print('[PC] ICE: $state');
  });

  // Add video transceiver (sendrecv)
  final videoTransceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.sendrecv,
  );
  print('[Video] Created transceiver, direction: ${videoTransceiver.direction}');

  // Add audio transceiver (sendrecv)
  final audioTransceiver = pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.sendrecv,
  );
  print('[Audio] Created transceiver, direction: ${audioTransceiver.direction}');

  // Handle incoming tracks
  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind} track');
    print('  mid: ${transceiver.mid}');
    print('  direction: ${transceiver.direction}');

    // Get the received track and echo back
    final track = transceiver.receiver.track;
    print('  track received');

    // Echo back: replace sender track with received track
    transceiver.sender.replaceTrack(track);
    print('  -> Echoing track back to sender');
  });

  // Create offer
  print('\nCreating offer...');
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Offer SDP Summary ---');
  print('Type: ${offer.type}');

  // Parse SDP for media info
  final sdpLines = offer.sdp.split('\n');
  final mediaLines = sdpLines.where((l) => l.startsWith('m=')).toList();
  for (final line in mediaLines) {
    print('Media: $line');
  }

  print('\n--- Usage ---');
  print('This server creates sendrecv transceivers for video and audio.');
  print('When a remote peer sends media, it gets echoed back.');
  print('');
  print('To test:');
  print('1. Send this offer to a browser client');
  print('2. Browser sends answer with its media');
  print('3. Browser should see its own video/audio echoed back');
  print('');
  print('Transceivers:');
  print('  Video mid: ${videoTransceiver.mid}');
  print('  Audio mid: ${audioTransceiver.mid}');

  // Keep alive briefly to show the setup
  await Future.delayed(Duration(seconds: 2));

  // Cleanup
  await pc.close();
  print('\nDone.');
}
