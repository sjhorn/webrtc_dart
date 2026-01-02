/// Simulcast Multiple Answer Example
///
/// This example matches werift's mediachannel/simulcast/multiple_answer.ts:
/// - WebSocket server that receives offer and creates answer
/// - Two recvonly video transceivers
/// - Uses RID header extensions (sdes:rtp-stream-id)
///
/// Usage:
///   dart run example/mediachannel/simulcast/multiple_answer.dart
///   Then connect a browser that sends offer with simulcast
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// WebSocket server for browser signaling (answer side)
class SimulcastMultipleAnswerServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Simulcast Multiple Answer Server');
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

    // Track packets per transceiver
    final ridPacketsA = <String, int>{};
    final ridPacketsB = <String, int>{};

    // Handle messages from browser (expects offer first)
    socket.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;

          if (msg['type'] == 'offer') {
            print('[Server] Received offer');

            // Create PeerConnection with STUN and RID header extensions (like werift)
            final pc = RTCPeerConnection(RtcConfiguration(
              iceServers: [
                IceServer(urls: ['stun:stun.l.google.com:19302'])
              ],
            ));

            // Track connection state
            pc.onIceConnectionStateChange.listen((state) {
              print('[Server] ICE state: $state');
            });

            pc.onConnectionStateChange.listen((state) {
              print('[Server] Connection state: $state');
            });

            // First recvonly transceiver (like werift)
            final transceiverA = pc.addTransceiver(
              MediaStreamTrackKind.video,
              direction: RtpTransceiverDirection.recvonly,
            );
            print('[Server] Added transceiverA (recvonly)');

            // Handle tracks from transceiver A
            transceiverA.receiver.onTrack = (track) {
              print(
                  '[Server] TransceiverA track: ${track.id}, RID: ${track.rid}');
              track.onReceiveRtp.listen((rtp) {
                final rid = track.rid ?? 'default';
                ridPacketsA[rid] = (ridPacketsA[rid] ?? 0) + 1;
                if (ridPacketsA[rid]! % 100 == 0) {
                  print(
                      '[Server] TransceiverA RID $rid: ${ridPacketsA[rid]} packets');
                }
              });
            };

            // Second recvonly transceiver (like werift)
            final transceiverB = pc.addTransceiver(
              MediaStreamTrackKind.video,
              direction: RtpTransceiverDirection.recvonly,
            );
            print('[Server] Added transceiverB (recvonly)');

            // Handle tracks from transceiver B
            transceiverB.receiver.onTrack = (track) {
              print(
                  '[Server] TransceiverB track: ${track.id}, RID: ${track.rid}');
              track.onReceiveRtp.listen((rtp) {
                final rid = track.rid ?? 'default';
                ridPacketsB[rid] = (ridPacketsB[rid] ?? 0) + 1;
                if (ridPacketsB[rid]! % 100 == 0) {
                  print(
                      '[Server] TransceiverB RID $rid: ${ridPacketsB[rid]} packets');
                }
              });
            };

            // Also listen via pc.onTrack
            pc.onTrack.listen((transceiver) {
              final track = transceiver.receiver.track;
              print('[Server] pc.onTrack: ${track.id}, RID: ${track.rid}');
            });

            // Set remote description (offer from browser)
            await pc.setRemoteDescription(
              RTCSessionDescription(type: 'offer', sdp: msg['sdp'] as String),
            );
            print('[Server] Remote description set');

            // Create and set local description (answer)
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            print('[Server] Created answer');

            // Send answer back to browser
            socket.add(jsonEncode({
              'type': answer.type,
              'sdp': answer.sdp,
            }));
            print('[Server] Sent answer to browser');

            // Handle socket close
            socket.done.then((_) async {
              print('[Server] Client disconnected');
              print('[Server] TransceiverA final RID counts: $ridPacketsA');
              print('[Server] TransceiverB final RID counts: $ridPacketsB');
              await pc.close();
            });
          }
        } catch (e) {
          print('[Server] Message error: $e');
        }
      },
      onDone: () {
        print('[Server] Socket closed');
      },
    );
  }
}

void main() async {
  final server = SimulcastMultipleAnswerServer();
  await server.start(port: 8888);
}
