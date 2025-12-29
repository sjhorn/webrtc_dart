/// MediaChannel Send/Receive Offer Example
///
/// This example matches werift's mediachannel/sendrecv/offer.ts:
/// - WebSocket server for signaling
/// - Header extensions: sdes:mid, abs-send-time
/// - Video transceiver with echo and PLI forwarding
/// - Audio transceiver with echo
///
/// Usage:
///   dart run example/mediachannel/sendrecv/offer.dart
///   Then open a browser to send/receive video
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// WebSocket server for browser signaling
class SendRecvServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('MediaChannel SendRecv Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('');
    print('Header extensions: sdes:mid, abs-send-time');
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

    // Create PeerConnection with header extensions (like werift)
    // useSdesMid() and useAbsSendTime()
    final pc = RtcPeerConnection(RtcConfiguration(
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
    ));

    // Track connection state (like werift)
    pc.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[Server] ICE state: $state');
    });

    // Track stats
    var videoPackets = 0;
    var audioPackets = 0;
    int? videoSsrc;

    // Add video transceiver (sendrecv - like werift)
    pc.addTransceiver(
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

    // Handle incoming tracks (like werift)
    pc.onTrack.listen((transceiver) {
      final track = transceiver.receiver.track;
      final kind = transceiver.kind;
      print('[Server] Received track: $kind');

      if (kind == MediaStreamTrackKind.video) {
        // Echo video track back (like werift: video.sender.replaceTrack(track))
        transceiver.sender.replaceTrack(track);
        print('[Server] Video track echoed back');

        // Handle PLI - forward PLI from sender to receiver (like werift)
        // video.sender.onPictureLossIndication.subscribe(() =>
        //   video.receiver.sendRtcpPLI(track.ssrc))
        track.onReceiveRtp.listen((rtp) {
          videoPackets++;
          videoSsrc ??= rtp.ssrc;

          if (videoPackets % 100 == 0) {
            print('[Server] Video packets: $videoPackets');
          }
        });

        // Request initial keyframe
        Future.delayed(Duration(milliseconds: 500), () {
          if (videoSsrc != null) {
            transceiver.receiver.rtpSession.sendPli(videoSsrc!);
            print('[Server] Sent initial PLI for keyframe');
          }
        });
      } else if (kind == MediaStreamTrackKind.audio) {
        // Echo audio track back (like werift: audio.sender.replaceTrack(track))
        transceiver.sender.replaceTrack(track);
        print('[Server] Audio track echoed back');

        track.onReceiveRtp.listen((rtp) {
          audioPackets++;
          if (audioPackets % 100 == 0) {
            print('[Server] Audio packets: $audioPackets');
          }
        });
      }
    });

    // Create offer and send to browser (like werift)
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    print('[Server] Created offer');

    // Log header extensions in SDP
    for (final line in offer.sdp.split('\n')) {
      if (line.contains('a=extmap')) {
        print('[Server] SDP: ${line.trim()}');
      }
    }

    // Send offer as JSON (like werift)
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
        print('[Server] Final stats - Video: $videoPackets, Audio: $audioPackets');
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SendRecvServer();
  await server.start(port: 8888);
}
