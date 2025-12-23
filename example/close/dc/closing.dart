/// Close DataChannel - Closing State Example
///
/// This example demonstrates the DataChannel closing process,
/// focusing on the 'closing' state transition before 'closed'.
/// Sends pings then gracefully closes the channel.
///
/// Usage: dart run example/close/dc/closing.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('DataChannel Closing Example');
  print('=' * 50);

  // Create two peer connections
  final pc1 = RtcPeerConnection();
  final pc2 = RtcPeerConnection();

  // Wait for transport initialization
  await Future.delayed(Duration(milliseconds: 500));

  final dcReady = Completer<dynamic>();
  late dynamic dc1;

  // Exchange ICE candidates
  pc1.onIceCandidate.listen((c) => pc2.addIceCandidate(c));
  pc2.onIceCandidate.listen((c) => pc1.addIceCandidate(c));

  // Handle incoming datachannel
  pc2.onDataChannel.listen((channel) {
    print('[DC2] Received: ${channel.label}');
    channel.onStateChange.listen((s) => print('[DC2] State: $s'));
    channel.onMessage.listen((data) {
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[DC2] Got: $msg');
      if (channel.state == DataChannelState.open) {
        channel.sendString('pong');
      }
    });
    if (!dcReady.isCompleted) dcReady.complete(channel);
  });

  // Create datachannel
  dc1 = pc1.createDataChannel('chat', protocol: 'bob');
  dc1.onStateChange.listen((s) => print('[DC1] State: $s'));
  dc1.onMessage.listen((d) => print('[DC1] Got: ${d is String ? d : String.fromCharCodes(d)}'));

  // Connect
  final offer = await pc1.createOffer();
  await pc1.setLocalDescription(offer);
  await pc2.setRemoteDescription(offer);
  final answer = await pc2.createAnswer();
  await pc2.setLocalDescription(answer);
  await pc1.setRemoteDescription(answer);

  // Wait for open
  await dcReady.future.timeout(Duration(seconds: 5));
  await Future.delayed(Duration(milliseconds: 500));

  // Send pings then close
  print('\nSending pings...');
  for (var i = 0; i < 4; i++) {
    await dc1.sendString('ping$i');
    await Future.delayed(Duration(seconds: 1));
  }

  print('\nClosing datachannel...');
  await dc1.close();

  await Future.delayed(Duration(milliseconds: 500));
  print('\nFinal states:');
  print('  DC1: ${dc1.state}');

  await pc1.close();
  await pc2.close();
  print('Done.');
}
