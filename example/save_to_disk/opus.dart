/// Save to Disk Opus Example
///
/// This example matches werift's save_to_disk/opus.ts:
/// - WebSocket server for signaling
/// - MediaRecorder for recording audio to WebM
/// - Records Opus audio only (video is received but not recorded)
/// - Records for 15 seconds then stops
///
/// Usage:
///   dart run example/save_to_disk/opus.dart
///   Then open a browser to the answer.html (or use automated test)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

/// WebSocket server for browser signaling
class SaveToDiskOpusServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8878}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Save to Disk Opus Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('');

    await for (final request in _httpServer!) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _handleWebSocket(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    }
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    print('[Server] Client connected');

    // Output path with timestamp
    final outputPath = './opus-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Track subscription for cleanup
    StreamSubscription? audioRtpSub;
    Timer? pliTimer;
    Timer? stopTimer;

    // Create PeerConnection with default codecs (like werift)
    final pc = RTCPeerConnection();

    // Create MediaRecorder for audio only
    late MediaRecorder recorder;
    var audioTrackAdded = false;
    var audioPacketsReceived = 0;
    int? videoSsrc;

    // Add video transceiver (recvonly - receive from browser, PLI for keyframes)
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[Server] Added video transceiver (recvonly)');

    // Add audio transceiver (recvonly - receive from browser, record this)
    pc.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[Server] Added audio transceiver (recvonly)');

    // Handle incoming tracks
    pc.onTrack.listen((transceiver) async {
      final track = transceiver.receiver.track;
      final kind = transceiver.kind;
      print('[Server] Received track: $kind');

      if (kind == MediaStreamTrackKind.video) {
        // Video: send PLI every 3 seconds (like werift)
        track.onReceiveRtp.listen((rtp) {
          videoSsrc ??= rtp.ssrc;
        });

        pliTimer = Timer.periodic(Duration(seconds: 3), (_) {
          if (videoSsrc != null) {
            transceiver.receiver.rtpSession.sendPli(videoSsrc!);
          }
        });
      } else if (kind == MediaStreamTrackKind.audio && !audioTrackAdded) {
        audioTrackAdded = true;

        // Create audio recording track
        final audioRecordingTrack = RecordingTrack(
          kind: 'audio',
          codecName: 'opus',
          payloadType: 111,
          clockRate: 48000,
          onRtp: (handler) {
            audioRtpSub = track.onReceiveRtp.listen((rtp) {
              audioPacketsReceived++;
              handler(rtp);
              if (audioPacketsReceived % 100 == 0) {
                print('[Server] Audio RTP packets: $audioPacketsReceived');
              }
            });
          },
        );

        // Create recorder for audio only
        recorder = MediaRecorder(
          tracks: [audioRecordingTrack],
          path: outputPath,
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        print('[Server] Recording started: $outputPath');
      }
    });

    // Track connection state
    pc.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[Server] ICE state: $state');
    });

    // Create offer and send to browser
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    print('[Server] Created offer');

    // Send offer as JSON (like werift)
    socket.add(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Server] Sent offer to browser');

    // Stop recording after 15 seconds (like werift)
    stopTimer = Timer(Duration(seconds: 15), () async {
      print('[Server] Recording duration reached');
      pliTimer?.cancel();
      audioRtpSub?.cancel();

      try {
        await recorder.stop();
        print('[Server] Recording stopped');

        // Check output file
        final file = File(outputPath);
        if (await file.exists()) {
          final size = await file.length();
          print('[Server] Output: $outputPath ($size bytes)');
        }
      } catch (e) {
        print('[Server] Stop error: $e');
      }
    });

    // Handle messages from browser
    socket.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;

          if (msg['type'] == 'answer') {
            print('[Server] Received answer');
            await pc.setRemoteDescription(
              RTCSessionDescription(type: 'answer', sdp: msg['sdp'] as String),
            );
            print('[Server] Remote description set');
          }
        } catch (e) {
          print('[Server] Message error: $e');
        }
      },
      onDone: () async {
        print('[Server] Client disconnected');
        pliTimer?.cancel();
        stopTimer?.cancel();
        audioRtpSub?.cancel();
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SaveToDiskOpusServer();
  await server.start(port: 8878);
}
