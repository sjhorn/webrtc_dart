/// Save to Disk AV1X Example
///
/// This example matches werift's save_to_disk/av1x.ts:
/// - WebSocket server for signaling
/// - MediaRecorder for recording to WebM
/// - AV1X video + Opus audio with RTCP feedback (NACK, PLI, REMB)
/// - Records for 10 seconds then stops
///
/// Usage:
///   dart run example/save_to_disk/av1x.dart
///   Then open a browser to the answer.html (or use automated test)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

/// WebSocket server for browser signaling
class SaveToDiskAV1XServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8878}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Save to Disk AV1X Server');
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
    final outputPath = './av1x-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Track subscription for cleanup
    StreamSubscription? videoRtpSub;
    StreamSubscription? audioRtpSub;
    Timer? pliTimer;
    Timer? stopTimer;

    // Create PeerConnection with AV1X + Opus codecs (matches werift)
    final pc = RTCPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            RtpCodecParameters(
              mimeType: 'video/AV1X',
              clockRate: 90000,
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
    var audioPacketsReceived = 0;
    int? videoSsrc;

    // Add video transceiver (sendrecv - like werift)
    final videoTransceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[Server] Added video transceiver (sendrecv)');

    // Add audio transceiver (sendrecv - like werift)
    pc.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[Server] Added audio transceiver (sendrecv)');

    // Handle incoming tracks
    pc.onTrack.listen((transceiver) async {
      final track = transceiver.receiver.track;
      final kind = transceiver.kind;
      print('[Server] Received track: $kind');

      // Echo track back (like werift)
      transceiver.sender.replaceTrack(track);
      print('[Server] $kind track echoed back');

      if (kind == MediaStreamTrackKind.video && !videoTrackAdded) {
        videoTrackAdded = true;

        // Create video recording track
        final videoRecordingTrack = RecordingTrack(
          kind: 'video',
          codecName: 'AV1',
          payloadType: 35, // AV1 typically uses PT 35
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

        // Create recorder when video track arrives (may be before audio)
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
            videoTransceiver.receiver.rtpSession.sendPli(videoSsrc!);
            print('[Server] Sent PLI for keyframe');
          }
        });
      } else if (kind == MediaStreamTrackKind.audio && !audioTrackAdded) {
        audioTrackAdded = true;

        // Track audio packets
        audioRtpSub = track.onReceiveRtp.listen((rtp) {
          audioPacketsReceived++;
          if (audioPacketsReceived % 100 == 0) {
            print('[Server] Audio RTP packets: $audioPacketsReceived');
          }
        });
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

    // Stop recording after 10 seconds (like werift)
    stopTimer = Timer(Duration(seconds: 10), () async {
      print('[Server] Recording duration reached');
      pliTimer?.cancel();
      videoRtpSub?.cancel();
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
        videoRtpSub?.cancel();
        audioRtpSub?.cancel();
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SaveToDiskAV1XServer();
  await server.start(port: 8878);
}
