/// RED Send Example
///
/// Demonstrates sending audio with RED (Redundant Encoding)
/// using GStreamer as the audio source.
///
/// Usage: dart run example/mediachannel/red/send.dart
///
/// Requires: GStreamer with opusenc and rtpopuspay
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

void main() async {
  print('RED Send Example');
  print('=' * 50);

  // WebSocket signaling server
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      codecs: RtcCodecs(
        audio: [
          // RED codec wraps Opus for redundancy
          RtpCodecParameters(
            mimeType: 'audio/RED',
            clockRate: 48000,
            channels: 2,
          ),
          RtpCodecParameters(
            mimeType: 'audio/OPUS',
            clockRate: 48000,
            channels: 2,
          ),
        ],
      ),
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Create nonstandard track for sending RTP
    final track =
        nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.audio);

    // Find available UDP port and set up GStreamer
    final udpSocket =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = udpSocket.port;
    print('[UDP] Listening on port $port');

    // Start GStreamer pipeline to generate test audio
    final gstArgs = [
      'audiotestsrc',
      'wave=ticks',
      '!',
      'audioconvert',
      '!',
      'audioresample',
      '!',
      'queue',
      '!',
      'opusenc',
      '!',
      'rtpopuspay',
      '!',
      'udpsink',
      'host=127.0.0.1',
      'port=$port',
    ];
    print('[GStreamer] gst-launch-1.0 ${gstArgs.join(' ')}');

    try {
      final process = await Process.start('gst-launch-1.0', gstArgs);
      process.stdout
          .listen((data) => print('[GST] ${String.fromCharCodes(data)}'));
      process.stderr
          .listen((data) => print('[GST ERR] ${String.fromCharCodes(data)}'));
    } catch (e) {
      print('[GST] Failed to start GStreamer: $e');
      print('[GST] Make sure GStreamer is installed with Opus support');
    }

    // Forward UDP packets to WebRTC track
    udpSocket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = udpSocket.receive();
        if (datagram != null) {
          track.writeRtp(datagram.data);
        }
      }
    });

    // Add send-only audio transceiver
    pc.addTransceiver(
      track,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Create offer and send to browser
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
      await pc.setRemoteDescription(answer);
      print('[SDP] Remote description set');
    });
  });

  print('\n--- RED Send Pipeline ---');
  print('');
  print('GStreamer -> UDP -> Dart -> WebRTC -> Browser');
  print('');
  print('RED provides redundancy by including previous frames');
  print('in each packet, improving resilience to packet loss.');

  print('\nWaiting for browser connection...');
}
