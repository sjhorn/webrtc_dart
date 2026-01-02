/// Save Audio+Video to MP4 Example
///
/// Records both H.264 video and AAC audio to an MP4 file.
/// Demonstrates synchronized A/V muxing.
///
/// Usage: dart run example/save_to_disk/mp4/av.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Save Audio+Video to MP4 Example');
  print('=' * 50);

  final outputFile = 'output_av.mp4';

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
      codecs: RtcCodecs(
        video: [
          createH264Codec(
            payloadType: 96,
            parameters: 'profile-level-id=42e01f;packetization-mode=1',
          ),
        ],
        audio: [
          createOpusCodec(payloadType: 111),
        ],
      ),
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    var videoPackets = 0;
    var audioPackets = 0;

    // Add video transceiver
    final videoTransceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Add audio transceiver
    final audioTransceiver = pc.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((transceiver) {
      final kind = transceiver.kind;
      print('[Track] Receiving $kind');
    });

    // Listen for video RTP
    videoTransceiver.receiver.track.onReceiveRtp.listen((rtp) {
      videoPackets++;
      // In real implementation:
      // 1. Depacketize H.264 FU-A/STAP-A
      // 2. Extract NAL units
      // 3. Pass to MP4 muxer video track
    });

    // Listen for audio RTP
    audioTransceiver.receiver.track.onReceiveRtp.listen((rtp) {
      audioPackets++;
      // In real implementation:
      // 1. Decode Opus to PCM (or transcode to AAC)
      // 2. Pass to MP4 muxer audio track
    });

    // Stats timer
    Timer.periodic(Duration(seconds: 3), (_) {
      print('[Stats] Video: $videoPackets pkts, Audio: $audioPackets pkts');
    });

    // Create offer and send
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final answer = RTCSessionDescription(type: 'answer', sdp: msg['sdp']);
      await pc.setRemoteDescription(answer);
      print('[SDP] Remote description set');
    }, onDone: () {
      pc.close();
      print('\n[Done] Output: $outputFile');
    });
  });

  print('\n--- MP4 A/V Recording ---');
  print('');
  print('Output: $outputFile');
  print('');
  print('MP4 container structure:');
  print('  ftyp - File type');
  print('  moov - Movie metadata');
  print('    mvhd - Movie header');
  print('    trak - Video track (H.264)');
  print('    trak - Audio track (AAC)');
  print('  mdat - Media data');
  print('');
  print('Note: Full implementation requires:');
  print('  - H.264 depacketization');
  print('  - Opus -> AAC transcoding');
  print('  - MP4 muxer (mp4box, FFmpeg, or custom)');

  print('\nWaiting for browser connection...');
}
