/// Multi-Offer Receive Only Example
///
/// Demonstrates handling multiple browser connections, each
/// sending video to the server independently.
///
/// Usage: dart run example/mediachannel/recvonly/multi_offer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

class ClientConnection {
  final String id;
  final RtcPeerConnection pc;
  int packetsReceived = 0;

  ClientConnection(this.id, this.pc);
}

final _clients = <String, ClientConnection>{};
var _clientCounter = 0;

void main() async {
  print('Multi-Offer Receive Only Example');
  print('=' * 50);

  // WebSocket signaling server
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  // Stats timer
  Timer.periodic(Duration(seconds: 5), (_) {
    if (_clients.isNotEmpty) {
      print('\n--- Client Stats ---');
      for (final client in _clients.values) {
        print('  ${client.id}: ${client.packetsReceived} packets');
      }
    }
  });

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    final clientId = 'client_${++_clientCounter}';
    print('[$clientId] Connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    final client = ClientConnection(clientId, pc);
    _clients[clientId] = client;

    pc.onConnectionStateChange.listen((state) {
      print('[$clientId] Connection: $state');
      if (state == PeerConnectionState.closed ||
          state == PeerConnectionState.failed ||
          state == PeerConnectionState.disconnected) {
        _clients.remove(clientId);
        print('[$clientId] Removed from clients');
      }
    });

    // Add receive-only video transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[$clientId] Receiving video track');
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      client.packetsReceived++;
    });

    // Create offer and send to browser
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer from browser
    socket.listen(
      (data) async {
        final msg = jsonDecode(data as String);
        final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
        await pc.setRemoteDescription(answer);
        print('[$clientId] Remote description set');
      },
      onDone: () {
        print('[$clientId] WebSocket closed');
        pc.close();
        _clients.remove(clientId);
      },
    );
  });

  print('\n--- Multi-Client Architecture ---');
  print('');
  print('Each browser gets its own PeerConnection:');
  print('  Browser 1 -> PC1 -> receive video');
  print('  Browser 2 -> PC2 -> receive video');
  print('  Browser N -> PCN -> receive video');
  print('');
  print('Stats printed every 5 seconds.');

  print('\nWaiting for browser connections...');
}
