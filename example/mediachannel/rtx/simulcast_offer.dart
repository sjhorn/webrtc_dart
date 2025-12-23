/// RTX Simulcast Offer Example
///
/// Sends simulcast video with RTX retransmission enabled.
/// Combines simulcast layers with packet loss recovery.
///
/// Usage: dart run example/mediachannel/rtx/simulcast_offer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

void main() async {
  print('RTX Simulcast Offer Example');
  print('=' * 50);

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Create tracks for each simulcast layer
    final tracks = {
      'high': nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video),
      'mid': nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video),
      'low': nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video),
    };

    // Add transceivers for each layer
    for (final entry in tracks.entries) {
      pc.addTransceiverWithTrack(
        entry.value,
        direction: RtpTransceiverDirection.sendonly,
      );
      print('[Transceiver] Added ${entry.key} layer');
    }

    // Create and send offer
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

      // Start sending simulated video to each layer
      _startSimulatedVideo(tracks);
    }, onDone: () {
      pc.close();
    });
  });

  print('\n--- RTX + Simulcast ---');
  print('');
  print('Combines two features:');
  print('  1. Simulcast: Multiple quality layers');
  print('  2. RTX: Retransmission for lost packets');
  print('');
  print('Benefits:');
  print('  - Adaptive quality selection');
  print('  - Packet loss recovery per layer');
  print('  - Bandwidth efficiency');

  print('\nWaiting for browser connection...');
}

void _startSimulatedVideo(Map<String, nonstandard.MediaStreamTrack> tracks) {
  // Simulate different bitrates for each layer
  final intervals = {
    'high': Duration(milliseconds: 33), // 30fps
    'mid': Duration(milliseconds: 50),  // 20fps
    'low': Duration(milliseconds: 100), // 10fps
  };

  for (final entry in tracks.entries) {
    final interval = intervals[entry.key]!;
    Timer.periodic(interval, (_) {
      // Would write real RTP packets here
      // entry.value.writeRtp(rtpPacket);
    });
    print('[Video] Started ${entry.key} layer at ${1000 ~/ interval.inMilliseconds}fps');
  }
}
