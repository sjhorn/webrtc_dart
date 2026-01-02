/// Save to Disk H.264 Example
///
/// This example matches werift's save_to_disk/h264.ts:
/// - WebSocket server for signaling
/// - MediaRecorder for recording to WebM
/// - H.264 video + Opus audio with RTCP feedback (NACK, PLI, REMB)
/// - Records for 20 seconds then stops
///
/// Usage:
///   dart run example/save_to_disk/h264.dart
///   Then open a browser to the answer.html (or use automated test)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

/// WebSocket server for browser signaling
class SaveToDiskH264Server {
  HttpServer? _httpServer;

  Future<void> start({int port = 8878}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Save to Disk H264 Server');
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
    final outputPath = './h264-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Track subscription for cleanup
    StreamSubscription? videoRtpSub;
    Timer? pliTimer;
    Timer? stopTimer;

    // Create PeerConnection with H.264 + Opus codecs (matches werift)
    final pc = RTCPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            createH264Codec(
              payloadType: 96,
              parameters: 'profile-level-id=42e01f;packetization-mode=1',
              rtcpFeedback: [
                RtcpFeedback(type: 'nack'),
                RtcpFeedback(type: 'nack', parameter: 'pli'),
                RtcpFeedback(type: 'goog-remb'),
              ],
            ),
          ],
          audio: [
            RtpCodecParameters(
              mimeType: 'audio/opus',
              clockRate: 48000,
              channels: 2,
            ),
          ],
        ),
      ),
    );

    // Create MediaRecorder for video+audio
    late MediaRecorder recorder;
    var videoTrackAdded = false;
    var audioTrackAdded = false;
    var videoPacketsReceived = 0;
    int? videoSsrc;

    // Add video transceiver (recvonly - receive from browser)
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[Server] Added video transceiver (recvonly)');

    // Add audio transceiver (recvonly - receive from browser)
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

      if (kind == MediaStreamTrackKind.video && !videoTrackAdded) {
        videoTrackAdded = true;

        // Create video recording track
        final videoRecordingTrack = RecordingTrack(
          kind: 'video',
          codecName: 'H264',
          payloadType: 96,
          clockRate: 90000,
          onRtp: (handler) {
            videoRtpSub = track.onReceiveRtp.listen((rtp) {
              videoPacketsReceived++;
              handler(rtp);
              videoSsrc ??= rtp.ssrc;
              if (videoPacketsReceived % 100 == 0) {
                print('[Server] Video RTP packets: $videoPacketsReceived');
              }
            });
          },
        );

        // Create recorder when video track arrives
        recorder = MediaRecorder(
          tracks: [videoRecordingTrack],
          path: outputPath,
          options: MediaRecorderOptions(
            width: 640,
            height: 360,
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        print('[Server] Recording started: $outputPath');

        // Send PLI every 2 seconds (like werift)
        pliTimer = Timer.periodic(Duration(seconds: 2), (_) {
          if (videoSsrc != null) {
            transceiver.receiver.rtpSession.sendPli(videoSsrc!);
            print('[Server] Sent PLI for keyframe');
          }
        });
      } else if (kind == MediaStreamTrackKind.audio && !audioTrackAdded) {
        audioTrackAdded = true;
        print('[Server] Audio track received (not recording in this example)');
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

    // Stop recording after 20 seconds (like werift)
    stopTimer = Timer(Duration(seconds: 20), () async {
      print('[Server] Recording duration reached');
      pliTimer?.cancel();
      videoRtpSub?.cancel();

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
        videoRtpSub?.cancel();
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SaveToDiskH264Server();
  await server.start(port: 8878);
}
