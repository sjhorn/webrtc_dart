/// Multi-Offer Send/Receive Example
///
/// Handles multiple clients with bidirectional media.
/// Each client can send and receive video independently.
///
/// Usage: dart run example/mediachannel/sendrecv/multi_offer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

final _clients = <String, RTCPeerConnection>{};
var _clientCounter = 0;

void main() async {
  print('Multi-Offer Send/Receive Example');
  print('=' * 50);

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    final clientId = 'client_${++_clientCounter}';
    print('[$clientId] Connected');

    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));
    _clients[clientId] = pc;

    pc.onConnectionStateChange.listen((state) {
      print('[$clientId] Connection: $state');
      if (state == PeerConnectionState.closed ||
          state == PeerConnectionState.failed) {
        _clients.remove(clientId);
      }
    });

    // Handle incoming video from this client
    pc.onTrack.listen((transceiver) {
      print('[$clientId] Received ${transceiver.kind}');
    });

    // Track for sending to this client
    final outTrack =
        nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    // Add bidirectional video transceiver
    pc.addTransceiver(
      outTrack,
      direction: RtpTransceiverDirection.sendrecv,
    );

    // Create and send offer
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer and ICE candidates
    socket.listen(
      (data) async {
        final msg = jsonDecode(data as String);
        if (msg['type'] == 'answer') {
          final answer = RTCSessionDescription(type: 'answer', sdp: msg['sdp']);
          await pc.setRemoteDescription(answer);
          print('[$clientId] Remote description set');
        } else if (msg['candidate'] != null) {
          final candidate = RTCIceCandidate.fromSdp(msg['candidate']);
          await pc.addIceCandidate(candidate);
        }
      },
      onDone: () {
        print('[$clientId] Disconnected');
        pc.close();
        _clients.remove(clientId);
      },
    );
  });

  // Stats
  Timer.periodic(Duration(seconds: 5), (_) {
    print('[Stats] ${_clients.length} clients connected');
  });

  print('\n--- Multi-Client Mesh ---');
  print('');
  print('Each client sends video to all others:');
  print('  Client A <-> Server <-> Client B');
  print('              Server <-> Client C');
  print('');
  print('Video from each client is broadcast to all others.');

  print('\nWaiting for browser connections...');
}
