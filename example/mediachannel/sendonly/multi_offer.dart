/// Multi-Offer Send Only Example
///
/// Sends the same video to multiple browser clients.
/// Each client gets its own PeerConnection with the same media.
///
/// Usage: dart run example/mediachannel/sendonly/multi_offer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

final _clients = <String, RtcPeerConnection>{};
final _tracks = <String, nonstandard.MediaStreamTrack>{};
var _clientCounter = 0;

void main() async {
  print('Multi-Offer Send Only Example');
  print('=' * 50);

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    final clientId = 'client_${++_clientCounter}';
    print('[$clientId] Connected');

    final pc = RtcPeerConnection(RtcConfiguration(
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
        _tracks.remove(clientId);
      }
    });

    // Create track for this client
    final track =
        nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
    _tracks[clientId] = track;

    pc.addTransceiver(
      track,
      direction: RtpTransceiverDirection.sendonly,
    );

    // Create and send offer
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer
    socket.listen(
      (data) async {
        final msg = jsonDecode(data as String);
        final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
        await pc.setRemoteDescription(answer);
        print('[$clientId] Remote description set');
      },
      onDone: () {
        print('[$clientId] Disconnected');
        pc.close();
        _clients.remove(clientId);
        _tracks.remove(clientId);
      },
    );
  });

  // Stats timer
  Timer.periodic(Duration(seconds: 5), (_) {
    print('[Stats] ${_clients.length} clients connected');
  });

  print('\n--- Broadcast Architecture ---');
  print('');
  print('Video Source -> Dart Server -> Multiple Browsers');
  print('');
  print('Each client gets independent PeerConnection');
  print('Same video packets sent to all clients');

  print('\nWaiting for browser connections...');
}
