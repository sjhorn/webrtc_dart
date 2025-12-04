/// Audio peer connection example
/// Demonstrates bidirectional audio track exchange between two local peers
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('[Audio Test] Starting bidirectional audio test');

  // Create two peer connections
  final pc1 = RtcPeerConnection();
  final pc2 = RtcPeerConnection();

  // Track received audio frames
  int pc1ReceivedFrames = 0;
  int pc2ReceivedFrames = 0;

  // Create audio tracks with generators
  print('[PC1] Creating audio track with periodic frames');
  final track1 = AudioStreamTrack(id: 'audio1', label: 'Test Audio 1');
  final track2 = AudioStreamTrack(id: 'audio2', label: 'Test Audio 2');

  // Add tracks to peer connections
  print('[PC1] Adding audio track');
  pc1.addTrack(track1);

  print('[PC2] Adding audio track');
  pc2.addTrack(track2);

  // Listen for received tracks
  pc1.onTrack.listen((transceiver) {
    print('[PC1] Received remote track: ${transceiver.receiver.track.id}, mid: ${transceiver.mid}');
    final remoteTrack = transceiver.receiver.track;
    if (remoteTrack is AudioStreamTrack) {
      remoteTrack.onAudioFrame.listen((frame) {
        pc1ReceivedFrames++;
        print('[PC1] Received frame #$pc1ReceivedFrames from PC2');
      });
    }
  });

  pc2.onTrack.listen((transceiver) {
    print('[PC2] Received remote track: ${transceiver.receiver.track.id}, mid: ${transceiver.mid}');
    final remoteTrack = transceiver.receiver.track;
    if (remoteTrack is AudioStreamTrack) {
      remoteTrack.onAudioFrame.listen((frame) {
        pc2ReceivedFrames++;
        print('[PC2] Received frame #$pc2ReceivedFrames from PC1');
      });
    }
  });

  // Set up ICE candidate exchange
  pc1.onIceCandidate.listen((candidate) async {
    await pc2.addIceCandidate(candidate);
  });

  pc2.onIceCandidate.listen((candidate) async {
    await pc1.addIceCandidate(candidate);
  });

  // Monitor connection states
  pc1.onConnectionStateChange.listen((state) {
    print('[PC1] Connection state: $state');
  });

  pc2.onConnectionStateChange.listen((state) {
    print('[PC2] Connection state: $state');
  });

  // Create and exchange SDP
  print('[PC1] Creating offer...');
  final offer = await pc1.createOffer();
  print('[Offer SDP]:\n${offer.sdp}');
  print('');

  print('[PC1] Setting local description');
  await pc1.setLocalDescription(offer);

  print('[PC2] Setting remote description');
  await pc2.setRemoteDescription(offer);

  print('[PC2] Creating answer...');
  final answer = await pc2.createAnswer();
  print('[Answer SDP]:\n${answer.sdp}');
  print('');

  print('[PC2] Setting local description');
  await pc2.setLocalDescription(answer);

  print('[PC1] Setting remote description');
  await pc1.setRemoteDescription(answer);

  // Wait for connection to establish
  print('[Test] Waiting for connection to establish...');
  await Future.delayed(Duration(seconds: 3));

  // Start generating audio frames
  print('[PC1] Starting audio frame generation (50ms intervals)');
  print('[PC2] Starting audio frame generation (50ms intervals)');

  // Generate audio frames at 20Hz (50ms intervals) for both tracks
  // In real WebRTC, this would be driven by audio capture
  var frameCount1 = 0;
  var frameCount2 = 0;

  final timer1 = Timer.periodic(Duration(milliseconds: 50), (timer) {
    // Opus: 20ms frame duration, 48kHz sample rate
    final frame = AudioFrame(
      samples: [], // Would contain PCM samples in production
      sampleRate: 48000,
      channels: 1,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
    track1.sendAudioFrame(frame);
    frameCount1++;

    if (frameCount1 % 20 == 0) {
      print('[PC1] Sent $frameCount1 audio frames');
    }
  });

  final timer2 = Timer.periodic(Duration(milliseconds: 50), (timer) {
    final frame = AudioFrame(
      samples: [],
      sampleRate: 48000,
      channels: 1,
      timestamp: DateTime.now().microsecondsSinceEpoch,
    );
    track2.sendAudioFrame(frame);
    frameCount2++;

    if (frameCount2 % 20 == 0) {
      print('[PC2] Sent $frameCount2 audio frames');
    }
  });

  // Let it run for 5 seconds
  print('[Test] Running for 5 seconds...');
  await Future.delayed(Duration(seconds: 5));

  // Clean up
  timer1.cancel();
  timer2.cancel();

  print('\n[Test Results]');
  print('PC1 sent: $frameCount1 frames, received: $pc1ReceivedFrames frames');
  print('PC2 sent: $frameCount2 frames, received: $pc2ReceivedFrames frames');

  if (pc1ReceivedFrames > 0 && pc2ReceivedFrames > 0) {
    print('[SUCCESS] Bidirectional audio RTP flow working!');
  } else {
    print('[FAILURE] No audio frames received');
  }

  await pc1.close();
  await pc2.close();

  print('[Audio Test] Complete');
}
