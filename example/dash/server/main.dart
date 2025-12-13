/// DASH Streaming Server Example
///
/// Demonstrates receiving WebRTC media and creating DASH segments
/// for HTTP streaming. Receives audio/video via WebRTC, packages
/// into WebM segments, and serves via HTTP for DASH playback.
///
/// Usage: dart run example/dash/server/main.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

const _dashDir = './dash_output';
const _dashServerPort = 8125;
const _signalingPort = 8888;

void main() async {
  print('DASH Streaming Server Example');
  print('=' * 50);
  print('DASH output: $_dashDir');
  print('DASH HTTP server: http://localhost:$_dashServerPort');
  print('Signaling WebSocket: ws://localhost:$_signalingPort');

  // Create output directory
  await Directory(_dashDir).create(recursive: true);

  // Start DASH HTTP server
  final dashServer = await HttpServer.bind('localhost', _dashServerPort);
  print('\n[DASH] HTTP server started');
  _serveDashFiles(dashServer);

  // Start signaling server
  final signalingServer = await HttpServer.bind('localhost', _signalingPort);
  print('[Signaling] WebSocket server started');

  await for (final request in signalingServer) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _handleWebSocketConnection(socket);
    }
  }
}

void _serveDashFiles(HttpServer server) {
  server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.add('Access-Control-Allow-Origin', '*');

    if (path == '/manifest.mpd') {
      request.response.headers.contentType = ContentType('application', 'dash+xml');
      request.response.write(_generateMpd());
    } else if (path.endsWith('.webm')) {
      final file = File('$_dashDir$path');
      if (await file.exists()) {
        request.response.headers.contentType = ContentType('video', 'webm');
        await request.response.addStream(file.openRead());
      } else {
        request.response.statusCode = 404;
      }
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  });
}

Future<void> _handleWebSocketConnection(WebSocket socket) async {
  print('[Client] Connected');

  final pc = RtcPeerConnection();
  // ignore: unused_local_variable
  var segmentIndex = 0;

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Audio transceiver (recvonly)
  // ignore: unused_local_variable
  final audioTransceiver = pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Video transceiver (recvonly)
  // ignore: unused_local_variable
  final videoTransceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Handle incoming tracks
  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Receive RTP packets
    // 2. Depacketize to raw frames
    // 3. Package into WebM segments
    // 4. Write to filesystem for DASH serving

    // Request keyframes periodically for video
    if (transceiver.kind == MediaStreamTrackKind.video) {
      Timer.periodic(Duration(seconds: 5), (_) {
        print('[Video] Requesting keyframe for new segment');
        // transceiver.receiver.sendRtcpPLI(track.ssrc);
      });
    }
  });

  // Create and send offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  socket.add(json.encode({'type': 'offer', 'sdp': offer.sdp}));

  // Handle answer
  socket.listen((data) async {
    final msg = json.decode(data as String);
    if (msg['type'] == 'answer') {
      await pc.setRemoteDescription(SessionDescription(
        type: 'answer',
        sdp: msg['sdp'] as String,
      ));
      print('[Signaling] Answer received, connection establishing...');
    }
  });
}

String _generateMpd() {
  // Generate DASH MPD manifest
  return '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="dynamic"
     minimumUpdatePeriod="PT2S" availabilityStartTime="2024-01-01T00:00:00Z">
  <Period>
    <AdaptationSet mimeType="video/webm" codecs="vp8">
      <Representation id="video" bandwidth="1000000">
        <SegmentTemplate media="video_\$Number\$.webm" initialization="video_init.webm"
                         startNumber="1" duration="2000" timescale="1000"/>
      </Representation>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/webm" codecs="opus">
      <Representation id="audio" bandwidth="128000">
        <SegmentTemplate media="audio_\$Number\$.webm" initialization="audio_init.webm"
                         startNumber="1" duration="2000" timescale="1000"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';
}
