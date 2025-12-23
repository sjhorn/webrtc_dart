/// Save H.264 to Disk Example
///
/// Receives H.264 video from browser and saves raw NAL units.
/// For MP4 container output, see save_to_disk/mp4/h264.dart.
///
/// Usage: dart run example/save_to_disk/h264.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Save H.264 to Disk Example');
  print('=' * 50);

  final outputFile = File('output.h264');
  IOSink? sink;

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
      codecs: RtcCodecs(
        video: [
          createH264Codec(
            payloadType: 96,
            parameters: 'profile-level-id=42e01f;packetization-mode=1',
          ),
        ],
      ),
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
      if (state == PeerConnectionState.connected) {
        sink = outputFile.openWrite();
        print('[File] Opened ${outputFile.path} for writing');
      } else if (state == PeerConnectionState.closed) {
        sink?.close();
        print('[File] Closed ${outputFile.path}');
      }
    });

    var frameCount = 0;
    var nalCount = 0;

    // Add receive-only video transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[Track] Receiving H.264 video');
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      // H.264 RTP depacketization
      final payload = rtp.payload;
      if (payload.isEmpty) return;

      final nalType = payload[0] & 0x1F;

      if (nalType >= 1 && nalType <= 23) {
        // Single NAL unit
        if (sink != null) {
          _writeNalUnit(sink!, payload);
        }
        nalCount++;
      } else if (nalType == 28) {
        // FU-A fragmentation
        // In full implementation, reassemble fragments
        // For now, just count
        final fuHeader = payload[1];
        final isStart = (fuHeader & 0x80) != 0;
        if (isStart) {
          frameCount++;
        }
      } else if (nalType == 24) {
        // STAP-A (multiple NALs)
        var offset = 1;
        while (offset < payload.length - 2) {
          final size = (payload[offset] << 8) | payload[offset + 1];
          offset += 2;
          if (offset + size <= payload.length && sink != null) {
            _writeNalUnit(sink!, payload.sublist(offset, offset + size));
            nalCount++;
          }
          offset += size;
        }
      }

      if (nalCount > 0 && nalCount % 100 == 0) {
        print('[H264] Frames: $frameCount, NAL units: $nalCount');
      }
    });

    // Create offer and send to browser
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
      print('[WS] Client disconnected');
      pc.close();
    });
  });

  print('\n--- H.264 Recording ---');
  print('');
  print('Output: ${outputFile.path}');
  print('');
  print('NAL unit types:');
  print('  1-23: Single NAL (SPS, PPS, IDR, non-IDR)');
  print('  24:   STAP-A (aggregated)');
  print('  28:   FU-A (fragmented)');
  print('');
  print('Play with: ffplay output.h264');

  print('\nWaiting for browser connection...');
}

void _writeNalUnit(IOSink sink, List<int> nal) {
  // Write Annex B start code
  sink.add([0x00, 0x00, 0x00, 0x01]);
  sink.add(nal);
}
