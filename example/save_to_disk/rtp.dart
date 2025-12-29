/// Save to Disk RTP Example
///
/// This example matches werift's save_to_disk/rtp.ts:
/// - Uses GStreamer to send RTP directly to UDP port
/// - MediaRecorder records incoming RTP to WebM
/// - No WebRTC signaling - direct RTP over UDP
///
/// Usage:
///   dart run example/save_to_disk/rtp.dart
///   (GStreamer will start automatically)
library;

import 'dart:async';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

/// Direct RTP to MediaRecorder
class RtpRecorderServer {
  Future<void> start({int port = 5004}) async {
    print('RTP Recorder Server');
    print('=' * 50);
    print('UDP RTP port: $port');
    print('');

    // Output path with timestamp
    final outputPath = './rtp-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Bind UDP socket for receiving RTP
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    print('[Server] Listening on UDP port $port');

    // Track packets
    var packetCount = 0;

    // Create audio recording track with RTP callback
    late void Function(RtpPacket) rtpHandler;
    final audioRecordingTrack = RecordingTrack(
      kind: 'audio',
      codecName: 'opus',
      payloadType: 96,
      clockRate: 48000,
      onRtp: (handler) {
        rtpHandler = handler;
      },
    );

    // Create MediaRecorder
    final recorder = MediaRecorder(
      tracks: [audioRecordingTrack],
      path: outputPath,
      options: MediaRecorderOptions(
        disableLipSync: true,
        disableNtp: true,
      ),
    );

    await recorder.start();
    print('[Server] Recording started: $outputPath');

    // Listen for RTP packets from GStreamer
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null && datagram.data.length > 12) {
          try {
            // Parse RTP packet
            final rtp = RtpPacket.parse(datagram.data);
            rtpHandler(rtp);
            packetCount++;
            if (packetCount % 100 == 0) {
              print('[Server] RTP packets: $packetCount');
            }
          } catch (e) {
            // Ignore malformed packets
          }
        }
      }
    });

    // Start GStreamer to send test audio RTP (like werift)
    print('[Server] Starting GStreamer audio source...');
    final gstProcess = await Process.start('gst-launch-1.0', [
      'audiotestsrc',
      '!',
      'audioconvert',
      '!',
      'audioresample',
      '!',
      'opusenc',
      '!',
      'rtpopuspay',
      '!',
      'udpsink',
      'host=127.0.0.1',
      'port=$port',
    ]);
    print('[Server] GStreamer started (PID: ${gstProcess.pid})');

    // Log GStreamer output
    gstProcess.stderr.listen((data) {
      // GStreamer outputs progress to stderr
    });

    // Record for 10 seconds
    print('[Server] Recording for 10 seconds...');
    await Future.delayed(Duration(seconds: 10));

    // Stop GStreamer
    gstProcess.kill();
    print('[Server] GStreamer stopped');

    // Stop recording
    await recorder.stop();
    print('[Server] Recording stopped');

    // Close socket
    socket.close();

    // Check output file
    final file = File(outputPath);
    if (await file.exists()) {
      final size = await file.length();
      print('[Server] Output: $outputPath ($size bytes)');
      print('[Server] Total RTP packets: $packetCount');
    }
  }
}

void main() async {
  final server = RtpRecorderServer();
  await server.start(port: 5004);
  exit(0);
}
