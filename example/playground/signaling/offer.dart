/// Playground Signaling Example
///
/// A simple playground for experimenting with WebRTC signaling.
/// Useful for testing and debugging signaling flows.
///
/// Usage: dart run example/playground/signaling/offer.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Playground - Signaling Experiment');
  print('=' * 50);

  // Simple signaling server for experimentation
  final server = await HttpServer.bind('localhost', 9999);
  print('Signaling server: ws://localhost:9999');
  print('');
  print('This playground allows you to:');
  print('- Test offer/answer exchange');
  print('- Experiment with ICE candidate trickling');
  print('- Debug SDP negotiation issues');

  final peers = <String, RTCPeerConnection>{};
  final sockets = <String, WebSocket>{};

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      final peerId = 'peer_${DateTime.now().millisecondsSinceEpoch}';

      print('\n[$peerId] Connected');
      sockets[peerId] = socket;

      // Create peer connection for this client
      final pc = RTCPeerConnection(RtcConfiguration(
        iceServers: [
          IceServer(urls: ['stun:stun.l.google.com:19302'])
        ],
      ));
      peers[peerId] = pc;

      // Log all state changes
      pc.onConnectionStateChange
          .listen((s) => print('[$peerId] Connection: $s'));
      pc.onIceConnectionStateChange.listen((s) => print('[$peerId] ICE: $s'));
      pc.onIceGatheringStateChange
          .listen((s) => print('[$peerId] Gathering: $s'));

      // Forward ICE candidates
      pc.onIceCandidate.listen((candidate) {
        print('[$peerId] ICE candidate: ${candidate.type}');
        socket.add(json.encode({
          'type': 'candidate',
          'candidate': {
            'candidate':
                '${candidate.foundation} ${candidate.component} ${candidate.transport} ${candidate.priority} ${candidate.host} ${candidate.port} typ ${candidate.type}',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        }));
      });

      // Handle incoming messages
      socket.listen(
        (data) => _handleMessage(peerId, pc, socket, data),
        onDone: () {
          print('[$peerId] Disconnected');
          pc.close();
          peers.remove(peerId);
          sockets.remove(peerId);
        },
      );

      // Send welcome message
      socket.add(json.encode({
        'type': 'welcome',
        'peerId': peerId,
        'message': 'Connected to playground signaling server',
      }));
    }
  }
}

void _handleMessage(
  String peerId,
  RTCPeerConnection pc,
  WebSocket socket,
  dynamic data,
) async {
  try {
    final msg = json.decode(data as String) as Map<String, dynamic>;
    final type = msg['type'] as String;

    print('[$peerId] Received: $type');

    switch (type) {
      case 'create-offer':
        // Client requests us to create an offer
        pc.addTransceiver(MediaStreamTrackKind.video,
            direction: RtpTransceiverDirection.sendrecv);
        pc.addTransceiver(MediaStreamTrackKind.audio,
            direction: RtpTransceiverDirection.sendrecv);

        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        socket.add(json.encode({
          'type': 'offer',
          'sdp': offer.sdp,
        }));

      case 'offer':
        // Client sent us an offer
        await pc.setRemoteDescription(RTCSessionDescription(
          type: 'offer',
          sdp: msg['sdp'] as String,
        ));

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        socket.add(json.encode({
          'type': 'answer',
          'sdp': answer.sdp,
        }));

      case 'answer':
        // Client sent us an answer
        await pc.setRemoteDescription(RTCSessionDescription(
          type: 'answer',
          sdp: msg['sdp'] as String,
        ));

      case 'candidate':
        // Client sent ICE candidate
        // ignore: unused_local_variable
        final candidate = msg['candidate'] as Map<String, dynamic>;
        print('[$peerId] Adding remote ICE candidate');
      // Parse and add candidate...

      default:
        print('[$peerId] Unknown message type: $type');
    }
  } catch (e) {
    print('[$peerId] Error: $e');
  }
}
