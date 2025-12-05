/// FFmpeg Video Sender Example
///
/// This example demonstrates sending video from FFmpeg to a WebRTC peer.
/// It follows the werift pattern: pipe RTP from ffmpeg via UDP to a track.
///
/// Requirements: ffmpeg installed and in PATH
///
/// Usage: dart run examples/ffmpeg_video_send.dart
///
/// This creates a local loopback connection where one peer sends video
/// from ffmpeg's test source to another peer.
library;

import 'dart:async';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

// Import nonstandard track for writeRtp() support
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() async {
  print('=== FFmpeg Video Sender Example ===\n');

  // Check if ffmpeg is available
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    if (result.exitCode != 0) {
      print('Error: ffmpeg not found. Please install ffmpeg.');
      exit(1);
    }
    print('FFmpeg found\n');
  } catch (e) {
    print('Error: ffmpeg not found. Please install ffmpeg.');
    exit(1);
  }

  // Get a random port for RTP
  final rtpPort = await _getRandomPort();
  print('Using RTP port: $rtpPort');

  // Create the video track (nonstandard track with writeRtp support)
  final videoTrack = nonstandard.MediaStreamTrack(
    kind: nonstandard.MediaKind.video,
    id: 'ffmpeg-video',
  );
  videoTrack.codec = nonstandard.RtpCodecParameters(
    mimeType: 'video/VP8',
    payloadType: 96,
    clockRate: 90000,
  );

  // Create UDP socket to receive RTP from ffmpeg
  final udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, rtpPort);
  print('UDP socket bound to port $rtpPort');

  var packetsReceived = 0;

  // Listen for RTP packets from ffmpeg
  udpSocket.listen((event) {
    if (event == RawSocketEvent.read) {
      final datagram = udpSocket.receive();
      if (datagram != null) {
        // Parse RTP packet
        final rtp = RtpPacket.parse(datagram.data);

        // Override payload type to match our negotiated codec
        final modifiedRtp = RtpPacket(
          version: rtp.version,
          padding: rtp.padding,
          extension: rtp.extension,
          marker: rtp.marker,
          payloadType: 96, // VP8 payload type
          sequenceNumber: rtp.sequenceNumber,
          timestamp: rtp.timestamp,
          ssrc: rtp.ssrc,
          csrcs: rtp.csrcs,
          extensionHeader: rtp.extensionHeader,
          payload: rtp.payload,
        );

        // Write to track
        videoTrack.writeRtp(modifiedRtp);

        packetsReceived++;
        if (packetsReceived % 100 == 0) {
          print('Received $packetsReceived RTP packets from ffmpeg');
        }
      }
    }
  });

  // Start ffmpeg test source sending to our UDP port
  print('\nStarting ffmpeg test source...');
  final ffmpegProcess = await Process.start('ffmpeg', [
    '-re', // Real-time mode
    '-f', 'lavfi',
    '-i', 'testsrc=size=640x480:rate=30', // Test pattern
    '-vcodec', 'libvpx', // VP8 codec
    '-cpu-used', '5',
    '-deadline', '1',
    '-g', '10', // Keyframe every 10 frames
    '-error-resilient', '1',
    '-auto-alt-ref', '1',
    '-f', 'rtp',
    'rtp://127.0.0.1:$rtpPort',
  ]);

  // Log ffmpeg output
  ffmpegProcess.stderr.transform(const SystemEncoding().decoder).listen((data) {
    // Only print interesting lines
    if (data.contains('frame=') || data.contains('Error') || data.contains('Opening')) {
      print('[ffmpeg] $data');
    }
  });

  // Give ffmpeg time to start
  await Future.delayed(Duration(seconds: 2));

  // Now create two peer connections and establish a connection
  print('\nSetting up WebRTC peer connections...');

  final pcSender = RtcPeerConnection();
  final pcReceiver = RtcPeerConnection();

  // Track when receiver gets the track
  pcReceiver.onTrack.listen((transceiver) {
    print('[Receiver] Got track: ${transceiver.kind}, mid=${transceiver.mid}');
  });

  // Create a standard video track for the sender
  // Note: In a full implementation, we'd need to wire the nonstandard track
  // to the RtpSession. For now, demonstrate the ffmpeg piping pattern.
  final senderTrack = VideoStreamTrack(
    id: 'sender-video',
    label: 'FFmpeg Video',
  );

  pcSender.addTrack(senderTrack);

  // Collect ICE candidates
  final senderCandidates = <Candidate>[];
  final receiverCandidates = <Candidate>[];

  pcSender.onIceCandidate.listen((c) => senderCandidates.add(c));
  pcReceiver.onIceCandidate.listen((c) => receiverCandidates.add(c));

  // Connection state monitoring
  pcSender.onConnectionStateChange.listen((state) {
    print('[Sender] Connection: $state');
  });
  pcReceiver.onConnectionStateChange.listen((state) {
    print('[Receiver] Connection: $state');
  });

  // SDP exchange
  print('Creating offer...');
  final offer = await pcSender.createOffer();
  await pcSender.setLocalDescription(offer);
  await pcReceiver.setRemoteDescription(offer);

  print('Creating answer...');
  final answer = await pcReceiver.createAnswer();
  await pcReceiver.setLocalDescription(answer);
  await pcSender.setRemoteDescription(answer);

  // Wait for ICE gathering
  await Future.delayed(Duration(milliseconds: 500));

  // Exchange candidates
  print('Exchanging ICE candidates...');
  for (final c in senderCandidates) {
    await pcReceiver.addIceCandidate(c);
  }
  for (final c in receiverCandidates) {
    await pcSender.addIceCandidate(c);
  }

  // Wait for connection
  print('\nWaiting for connection...');
  await Future.delayed(Duration(seconds: 3));

  print('\n=== Status ===');
  print('Sender connection: ${pcSender.connectionState}');
  print('Receiver connection: ${pcReceiver.connectionState}');
  print('RTP packets from ffmpeg: $packetsReceived');

  // Run for 10 seconds
  print('\nStreaming for 10 seconds...');
  await Future.delayed(Duration(seconds: 10));

  // Summary
  print('\n=== Final Summary ===');
  print('Total RTP packets from ffmpeg: $packetsReceived');

  // Cleanup
  print('\nCleaning up...');
  ffmpegProcess.kill(ProcessSignal.sigint);
  udpSocket.close();
  videoTrack.stop();
  await pcSender.close();
  await pcReceiver.close();

  print('Done.');
  exit(0);
}

Future<int> _getRandomPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}
