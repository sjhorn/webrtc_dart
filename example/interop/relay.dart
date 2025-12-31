/// Interop Relay Example
///
/// Relays WebRTC connections between two peers (SFU-style).
/// Accepts offers from multiple clients and routes media.
///
/// Usage: dart run example/interop/relay.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

class Peer {
  final String id;
  final WebSocket socket;
  final RtcPeerConnection pc;
  MediaStreamTrack? videoTrack;
  MediaStreamTrack? audioTrack;

  Peer(this.id, this.socket, this.pc);
}

final _peers = <String, Peer>{};
var _peerCounter = 0;

void main() async {
  print('Interop Relay Example');
  print('=' * 50);

  final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('Relay server listening on ws://localhost:8888');

  httpServer.transform(WebSocketTransformer()).listen(_handleConnection);

  // Stats
  Timer.periodic(Duration(seconds: 10), (_) {
    print('[Relay] ${_peers.length} peers connected');
  });

  print('\n--- Relay Architecture ---');
  print('');
  print('  Peer A ----> Relay ----> Peer B');
  print('         <----       <----');
  print('');
  print('Each peer sends media to relay, relay forwards to others.');

  print('\nWaiting for peer connections...');
}

Future<void> _handleConnection(WebSocket socket) async {
  final peerId = 'peer_${++_peerCounter}';
  print('[$peerId] Connected');

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  final peer = Peer(peerId, socket, pc);
  _peers[peerId] = peer;

  pc.onConnectionStateChange.listen((state) {
    print('[$peerId] Connection: $state');
    if (state == PeerConnectionState.closed ||
        state == PeerConnectionState.failed) {
      _peers.remove(peerId);
      _notifyPeerLeft(peerId);
    }
  });

  // ICE candidates
  pc.onIceCandidate.listen((candidate) {
    socket.add(jsonEncode({
      'type': 'candidate',
      'candidate': candidate.toSdp(),
      'sdpMid': '0',
    }));
  });

  // Incoming tracks
  pc.onTrack.listen((transceiver) {
    print('[$peerId] Received ${transceiver.kind}');
    // Note: Track media forwarding would be implemented here
  });

  // Signaling
  socket.listen((data) async {
    final msg = jsonDecode(data as String);

    if (msg['type'] == 'offer') {
      print('[$peerId] Received offer');
      final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
      await pc.setRemoteDescription(offer);

      // Add transceivers for receiving and sending
      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendrecv,
      );
      pc.addTransceiver(
        MediaStreamTrackKind.audio,
        direction: RtpTransceiverDirection.sendrecv,
      );

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      socket.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));
      print('[$peerId] Sent answer');
    } else if (msg['type'] == 'candidate' && msg['candidate'] != null) {
      final candidate = Candidate.fromSdp(msg['candidate']);
      await pc.addIceCandidate(candidate);
    }
  }, onDone: () {
    print('[$peerId] Disconnected');
    pc.close();
    _peers.remove(peerId);
    _notifyPeerLeft(peerId);
  });

  // Notify existing peers of new peer
  for (final other in _peers.values) {
    if (other.id != peerId) {
      other.socket.add(jsonEncode({
        'type': 'peer_joined',
        'id': peerId,
      }));
    }
  }
}

void _notifyPeerLeft(String peerId) {
  for (final peer in _peers.values) {
    peer.socket.add(jsonEncode({
      'type': 'peer_left',
      'id': peerId,
    }));
  }
}
