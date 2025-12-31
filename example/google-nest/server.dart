/// Google Nest Camera Example
///
/// Demonstrates connecting to Google Nest cameras via the
/// Smart Device Management API. Uses WebRTC to receive
/// live video stream from Nest cameras.
///
/// Prerequisites:
/// - Google Cloud project with SDM API enabled
/// - OAuth2 credentials (client ID, secret)
/// - Nest device access
///
/// Usage: dart run example/google-nest/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

// Environment variables needed:
// CLIENT_ID, CLIENT_SECRET, PROJECT_ID, REFRESH_TOKEN

void main() async {
  print('Google Nest Camera Example');
  print('=' * 50);

  // In a real implementation, you would:
  // 1. Load OAuth2 credentials from environment
  // 2. Authenticate with Google Smart Device Management API
  // 3. List available Nest devices
  // 4. Create WebRTC session with camera

  print('\nRequired environment variables:');
  print('  CLIENT_ID - Google OAuth2 client ID');
  print('  CLIENT_SECRET - Google OAuth2 client secret');
  print('  PROJECT_ID - Google Cloud project ID');
  print('  REFRESH_TOKEN - OAuth2 refresh token');

  print('\n--- Nest Camera WebRTC Flow ---');
  print('1. Authenticate with Google SDM API');
  print('2. List devices: GET /enterprises/{projectId}/devices');
  print('3. Generate stream: POST /devices/{deviceId}:executeCommand');
  print(
      '   Command: sdm.devices.commands.CameraLiveStream.GenerateWebRtcStream');
  print('4. Receive offer SDP from Nest API');
  print('5. Create answer and send back');
  print('6. Receive H.264 video stream');

  // Create peer connection with Nest-compatible codecs
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
    bundlePolicy: BundlePolicy.maxBundle,
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Nest cameras send H.264 video and Opus audio
  // Add transceivers to receive
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind} from Nest camera');

    // Process received media:
    // - Video: H.264 encoded frames
    // - Audio: Opus encoded

    // Request keyframes for video
    if (transceiver.kind == MediaStreamTrackKind.video) {
      Timer.periodic(Duration(seconds: 5), (_) {
        print('[Video] Requesting keyframe');
      });
    }
  });

  print('\n--- Codec Configuration ---');
  print('Video: H.264 (Nest cameras use H.264)');
  print('  - Profile: Baseline or Main');
  print('  - RTCP feedback: nack, pli, fir, transport-cc');
  print('Audio: Opus');
  print('  - Sample rate: 48000 Hz');
  print('  - Channels: 2 (stereo)');

  print('\n--- Usage ---');
  print('To use this example:');
  print('1. Set up Google Cloud project with SDM API');
  print('2. Create OAuth2 credentials');
  print('3. Complete device access authorization');
  print('4. Set environment variables');
  print('5. Run this server to receive Nest camera stream');

  // Demo: create an offer to show codec negotiation
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Sample Offer SDP (video section) ---');
  final lines = offer.sdp.split('\n');
  for (final line in lines) {
    if (line.startsWith('m=video') ||
        (line.startsWith('a=') && line.contains('H264'))) {
      print(line);
    }
  }

  await pc.close();
  print('\nDone.');
}
