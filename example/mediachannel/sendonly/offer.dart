/// MediaChannel Sendonly Offer Example
///
/// This example matches werift's mediachannel/sendonly/offer.ts:
/// - WebSocket server for signaling
/// - GStreamer (gst-launch-1.0) for video source
/// - Sendonly transceiver to send video to browser
/// - Uses writeRtp() to forward RTP packets
///
/// Usage:
///   dart run example/mediachannel/sendonly/offer.dart
///   Then open a browser to the answer.html (or use automated test)
///
/// Requires:
///   - GStreamer installed (gst-launch-1.0 command)
///   - VP8 encoder (libvpx)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

/// WebSocket server for browser signaling
class SendonlyServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('MediaChannel Sendonly Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('');
    print('Starting GStreamer video source...');
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

    // Cleanup
    RawDatagramSocket? udpSocket;
    Process? gstProcess;
    StreamSubscription? udpSub;

    // Create PeerConnection with VP8 codec (like werift)
    final pc = RtcPeerConnection(
      RtcConfiguration(
        codecs: RtcCodecs(
          audio: [], // No audio
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
              payloadType: 96,
            ),
          ],
        ),
      ),
    );

    // Create video track for sendonly (using nonstandard track with writeRtp)
    final track = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    // Bind UDP socket first to get port (like werift's randomPort())
    udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final udpPort = udpSocket.port;
    print('[Server] UDP listening on port $udpPort');

    // Forward RTP packets from GStreamer UDP to WebRTC track (like werift)
    var rtpPacketCount = 0;
    udpSub = udpSocket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = udpSocket!.receive();
        if (datagram != null) {
          // writeRtp accepts raw bytes (like werift)
          track.writeRtp(datagram.data);
          rtpPacketCount++;
          if (rtpPacketCount % 100 == 0) {
            print('[Server] Sent $rtpPacketCount RTP packets');
          }
        }
      }
    });

    // Add sendonly transceiver with track (like werift)
    pc.addTransceiver(track, direction: RtpTransceiverDirection.sendonly);
    print('[Server] Added sendonly video transceiver');

    // Track connection state
    pc.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');

      // Start GStreamer when connected (like werift)
      if (state == PeerConnectionState.connected && gstProcess == null) {
        _startGStreamer(udpPort).then((process) {
          gstProcess = process;
        });
      }
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[Server] ICE state: $state');
    });

    // Create offer and send to browser (like werift)
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    print('[Server] Created offer');

    // Send offer as JSON
    socket.add(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Server] Sent offer to browser');

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

        // Cleanup
        udpSub?.cancel();
        gstProcess?.kill();
        udpSocket?.close();
        await pc.close();

        print('[Server] Total RTP packets sent: $rtpPacketCount');
      },
    );
  }

  /// Start GStreamer pipeline for video source (matches werift)
  Future<Process?> _startGStreamer(int udpPort) async {
    // GStreamer pipeline (matches werift):
    // videotestsrc ! video/x-raw,width=640,height=480,format=I420 !
    // vp8enc error-resilient=partitions keyframe-max-dist=10 auto-alt-ref=true cpu-used=5 deadline=1 !
    // rtpvp8pay ! udpsink host=127.0.0.1 port=<udpPort>
    final gstArgs = [
      '-q',
      'videotestsrc',
      '!',
      'video/x-raw,width=640,height=480,format=I420',
      '!',
      'vp8enc',
      'error-resilient=partitions',
      'keyframe-max-dist=10',
      'auto-alt-ref=true',
      'cpu-used=5',
      'deadline=1',
      '!',
      'rtpvp8pay',
      '!',
      'udpsink',
      'host=127.0.0.1',
      'port=$udpPort',
    ];

    try {
      final process = await Process.start('gst-launch-1.0', gstArgs);
      print('[Server] GStreamer started');

      // Log GStreamer errors
      process.stderr.transform(utf8.decoder).listen((line) {
        if (line.trim().isNotEmpty) {
          print('[GStreamer] $line');
        }
      });

      return process;
    } catch (e) {
      print('[Server] Failed to start GStreamer: $e');
      print('[Server] Make sure GStreamer is installed:');
      print('  brew install gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad');
      return null;
    }
  }
}

void main() async {
  final server = SendonlyServer();
  await server.start(port: 8888);
}
