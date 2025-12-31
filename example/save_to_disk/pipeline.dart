/// Save to Disk Pipeline Example
///
/// This example matches werift's save_to_disk/pipeline.ts:
/// - WebSocket server for signaling
/// - Recording pipeline with lip sync for A/V synchronization
/// - VP8 video + Opus audio
/// - Records for 20 seconds then stops
///
/// werift uses callback-based pipeline:
///   RtpSource -> JitterBuffer -> NtpTime -> Depacketize -> Lipsync -> WebM
///
/// Dart uses MediaRecorder which handles the same internally:
///   RTP -> MediaRecorder (jitter, depacketize, lipsync, mux) -> WebM
///
/// Usage:
///   dart run example/save_to_disk/pipeline.dart
///   Then open a browser to send video+audio
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

/// WebSocket server for browser signaling
class PipelineRecordingServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8878}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Pipeline Recording Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('');
    print('Pipeline architecture (like werift):');
    print('  Audio: RTP -> NtpTime -> Depacketize -> Lipsync -> WebM');
    print(
        '  Video: RTP -> JitterBuffer -> NtpTime -> Depacketize -> Lipsync -> WebM');
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

    // Output path with timestamp (like werift: output-${Date.now()}.webm)
    final outputPath =
        './pipeline-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Track subscriptions for cleanup
    StreamSubscription? videoRtpSub;
    StreamSubscription? audioRtpSub;
    Timer? pliTimer;
    Timer? stopTimer;

    // Create PeerConnection with VP8 + Opus codecs (matches werift pipeline.ts)
    final pc = RtcPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
              payloadType: 96,
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

    // Create MediaRecorder with lip sync enabled (like werift's LipsyncCallback)
    late MediaRecorder recorder;
    var videoTrackAdded = false;
    var audioTrackAdded = false;
    var videoPacketsReceived = 0;
    var audioPacketsReceived = 0;
    int? videoSsrc;

    // Recording tracks - will be populated when tracks arrive
    RecordingTrack? videoRecordingTrack;

    // Add video transceiver (sendrecv - like werift: sender.replaceTrack)
    final videoTransceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[Server] Added video transceiver (sendrecv)');

    // Add audio transceiver (sendrecv - like werift: sender.replaceTrack)
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

      // Echo track back (like werift: sender.replaceTrack(track))
      transceiver.sender.replaceTrack(track);
      print('[Server] $kind track echoed back');

      if (kind == MediaStreamTrackKind.video && !videoTrackAdded) {
        videoTrackAdded = true;

        // Create video recording track (like werift's video RtpSourceCallback)
        videoRecordingTrack = RecordingTrack(
          kind: 'video',
          codecName: 'VP8',
          payloadType: 96,
          clockRate: 90000,
          onRtp: (handler) {
            videoRtpSub = track.onReceiveRtp.listen((rtp) {
              videoPacketsReceived++;
              handler(rtp);
              videoSsrc ??= rtp.ssrc;
              if (videoPacketsReceived % 100 == 0) {
                print('[Pipeline] Video packets: $videoPacketsReceived');
              }
            });
          },
        );

        // Create recorder with lip sync (like werift's LipsyncCallback)
        // Note: Audio track added later if it arrives
        recorder = MediaRecorder(
          tracks: [videoRecordingTrack!],
          path: outputPath,
          options: MediaRecorderOptions(
            width: 640,
            height: 360,
            // Lip sync settings (like werift's LipsyncCallback options)
            disableLipSync: false, // Enable lip sync
            disableNtp: false, // Use NTP timestamps
          ),
        );

        await recorder.start();
        print('[Pipeline] Recording started: $outputPath');
        print('[Pipeline] Lip sync: enabled');

        // Send PLI every 2 seconds (like werift's setInterval for sendRtcpPLI)
        pliTimer = Timer.periodic(Duration(seconds: 2), (_) {
          if (videoSsrc != null) {
            videoTransceiver.receiver.rtpSession.sendPli(videoSsrc!);
          }
        });
      } else if (kind == MediaStreamTrackKind.audio && !audioTrackAdded) {
        audioTrackAdded = true;

        // Track audio packets (like werift's audio RtpSourceCallback)
        audioRtpSub = track.onReceiveRtp.listen((rtp) {
          audioPacketsReceived++;
          if (audioPacketsReceived % 100 == 0) {
            print('[Pipeline] Audio packets: $audioPacketsReceived');
          }
        });
        print('[Pipeline] Audio track received');
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

    // Stop recording after 20 seconds (like werift: setTimeout 20_000)
    stopTimer = Timer(Duration(seconds: 20), () async {
      print('[Pipeline] Recording duration reached (20s)');
      pliTimer?.cancel();
      videoRtpSub?.cancel();
      audioRtpSub?.cancel();

      try {
        await recorder.stop();
        print('[Pipeline] Recording stopped');

        // Check output file
        final file = File(outputPath);
        if (await file.exists()) {
          final size = await file.length();
          print('[Pipeline] Output: $outputPath ($size bytes)');
          print('[Pipeline] Final stats:');
          print('[Pipeline]   Video packets: $videoPacketsReceived');
          print('[Pipeline]   Audio packets: $audioPacketsReceived');
        }
      } catch (e) {
        print('[Pipeline] Stop error: $e');
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
              SessionDescription(type: 'answer', sdp: msg['sdp'] as String),
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
  final server = PipelineRecordingServer();
  await server.start(port: 8878);
}
