/// Shared Utilities for Examples
///
/// Common helper functions used across multiple examples.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// Creates a simple WebSocket signaling server on the given port.
/// Returns a function to close the server.
Future<HttpServer> createSignalingServer(int port) async {
  final server = await HttpServer.bind('localhost', port);
  print('[Signaling] Server running on ws://localhost:$port');
  return server;
}

/// Waits for a RTCDataChannel to reach the open state.
Future<void> waitForDataChannelOpen(
  RTCDataChannel channel, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (channel.state == DataChannelState.open) return;

  final completer = Completer<void>();
  final sub = channel.onStateChange.listen((state) {
    if (state == DataChannelState.open && !completer.isCompleted) {
      completer.complete();
    }
  });

  try {
    await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

/// Waits for ICE connection to reach connected state.
Future<void> waitForIceConnected(
  RTCPeerConnection pc, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (pc.iceConnectionState == IceConnectionState.connected) return;

  final completer = Completer<void>();
  final sub = pc.onIceConnectionStateChange.listen((state) {
    if (state == IceConnectionState.connected && !completer.isCompleted) {
      completer.complete();
    }
  });

  try {
    await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

/// Performs a local offer/answer exchange between two peer connections.
Future<void> exchangeOfferAnswer(
  RTCPeerConnection offerer,
  RTCPeerConnection answerer,
) async {
  final offer = await offerer.createOffer();
  await offerer.setLocalDescription(offer);
  await answerer.setRemoteDescription(offer);

  final answer = await answerer.createAnswer();
  await answerer.setLocalDescription(answer);
  await offerer.setRemoteDescription(answer);
}

/// Sets up ICE candidate exchange between two local peer connections.
void setupIceCandidateExchange(
  RTCPeerConnection pc1,
  RTCPeerConnection pc2,
) {
  pc1.onIceCandidate.listen((c) => pc2.addIceCandidate(c));
  pc2.onIceCandidate.listen((c) => pc1.addIceCandidate(c));
}

/// Prints SDP summary (media lines only).
void printSdpSummary(String label, RTCSessionDescription sdp) {
  print('--- $label ---');
  print('Type: ${sdp.type}');
  final mediaLines =
      sdp.sdp.split('\n').where((l) => l.startsWith('m=')).toList();
  for (final line in mediaLines) {
    print('  $line');
  }
}

/// Creates a simple HTTP server that serves a test page.
Future<HttpServer> createTestPageServer(
  int port,
  String html,
) async {
  final server = await HttpServer.bind('localhost', port);
  print('[HTTP] Server running on http://localhost:$port');

  server.listen((request) {
    if (request.uri.path == '/' || request.uri.path == '/index.html') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(html);
    } else if (request.uri.path == '/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'status': 'ok'}));
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found');
    }
    request.response.close();
  });

  return server;
}

/// Default STUN servers for examples.
List<IceServer> get defaultIceServers => [
      IceServer(urls: ['stun:stun.l.google.com:19302']),
      IceServer(urls: ['stun:stun1.l.google.com:19302']),
    ];

/// Creates a peer connection with default STUN configuration.
RTCPeerConnection createPeerConnectionWithStun() {
  return RTCPeerConnection(RtcConfiguration(iceServers: defaultIceServers));
}
