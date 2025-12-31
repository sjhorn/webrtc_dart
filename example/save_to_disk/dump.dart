/// Dump RTP Packets to Disk Example
///
/// Saves raw RTP packets to disk for offline analysis.
/// Useful for debugging and protocol analysis.
///
/// Usage: dart run example/save_to_disk/dump.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Dump RTP Packets Example');
  print('=' * 50);

  // Create output directory
  final dumpDir = Directory('rtp_dump');
  if (!dumpDir.existsSync()) {
    dumpDir.createSync();
  }

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    var videoIndex = 0;
    var audioIndex = 0;

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

    // Listen for RTP on video track
    videoTransceiver.receiver.track.onReceiveRtp.listen((rtp) {
      final index = videoIndex++;
      final file = File('${dumpDir.path}/video_$index.rtp');
      file.writeAsBytesSync(rtp.serialize());

      if (index > 0 && index % 500 == 0) {
        print('[video] Dumped $index packets');
      }
    });

    // Listen for RTP on audio track
    audioTransceiver.receiver.track.onReceiveRtp.listen((rtp) {
      final index = audioIndex++;
      final file = File('${dumpDir.path}/audio_$index.rtp');
      file.writeAsBytesSync(rtp.serialize());

      if (index > 0 && index % 500 == 0) {
        print('[audio] Dumped $index packets');
      }
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
      final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
      await pc.setRemoteDescription(answer);
      print('[SDP] Remote description set');
    }, onDone: () {
      pc.close();
      print('\n[Summary]');
      print('  Video packets: $videoIndex');
      print('  Audio packets: $audioIndex');
      print('  Output: ${dumpDir.path}/');
    });
  });

  print('\n--- RTP Dump ---');
  print('');
  print('Output directory: ${dumpDir.path}/');
  print('');
  print('Files:');
  print('  video_N.rtp - Raw video RTP packets');
  print('  audio_N.rtp - Raw audio RTP packets');
  print('');
  print('Analysis tools:');
  print('  - Wireshark: Import as RTP');
  print('  - editcap: Convert to pcap');
  print('  - Custom parsing scripts');

  print('\nWaiting for browser connection...');
}
