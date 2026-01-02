/// Encrypted Recording Example
///
/// Demonstrates recording encrypted media. WebRTC media is
/// encrypted with SRTP, but this example shows additional
/// application-level encryption for stored files.
///
/// Usage: dart run example/save_to_disk/encrypt/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Encrypted Recording Example');
  print('=' * 50);

  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add transceivers
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Receive decrypted RTP from SRTP
    // 2. Re-encrypt for storage using AES-GCM
    // 3. Store encrypted frames with key metadata
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Encryption Layers ---');
  print('');
  print('Layer 1: SRTP (transport)');
  print('  - AES-CM or AES-GCM');
  print('  - Keys derived via DTLS-SRTP');
  print('  - Protects RTP in transit');
  print('');
  print('Layer 2: Storage encryption');
  print('  - AES-256-GCM recommended');
  print('  - Per-file or per-segment keys');
  print('  - Key management required');

  print('\n--- Encrypted File Format ---');
  print('');
  print('Option 1: Encrypt entire WebM');
  print('  - Simple: encrypt after muxing');
  print('  - Must decrypt entire file to play');
  print('');
  print('Option 2: Encrypt frames only');
  print('  - Container metadata unencrypted');
  print('  - Allows seeking without full decrypt');
  print('  - More complex implementation');
  print('');
  print('Option 3: Common Encryption (CENC)');
  print('  - Industry standard for DRM');
  print('  - Compatible with Widevine, PlayReady');
  print('  - Complex key management');

  print('\n--- Key Management ---');
  print('');
  print('Options:');
  print('  - Static key (simple but inflexible)');
  print('  - Key rotation per segment');
  print('  - KMS integration (AWS KMS, Vault)');
  print('  - CPIX for interoperability');
  print('');
  print('Key delivery:');
  print('  - Out-of-band (separate channel)');
  print('  - DRM license server');
  print('  - Encrypted key in file header');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
