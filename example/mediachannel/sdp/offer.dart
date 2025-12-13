/// SDP Manipulation Example
///
/// Demonstrates SDP parsing and manipulation for customizing
/// codec preferences, bitrate limits, and media configuration.
///
/// Usage: dart run example/mediachannel/sdp/offer.dart
library;

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('SDP Manipulation Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Add transceivers for video and audio
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.sendrecv,
  );
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.sendrecv,
  );

  // Create offer
  final offer = await pc.createOffer();

  print('\n--- Original SDP ---');
  _printSdpSummary(offer.sdp);

  // Demonstrate SDP manipulation techniques
  // ignore: unused_local_variable
  var modifiedSdp = offer.sdp;

  // 1. Codec preference: Prefer VP8 over other codecs
  print('\n--- SDP Manipulation Techniques ---');
  print('');
  print('1. Codec Preference (reorder m= line formats):');
  print('   Original: m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99');
  print('   Modified: m=video 9 UDP/TLS/RTP/SAVPF 97 96 98 99');
  print('   (Move preferred codec PT to front)');

  // 2. Bitrate limiting: Add b=AS line
  print('');
  print('2. Bitrate Limiting (add b= line after c= line):');
  print('   b=AS:500  (500 kbps application-specific limit)');
  print('   b=TIAS:500000  (500 kbps transport-independent limit)');

  // 3. Remove codecs: Filter out unwanted codec lines
  print('');
  print('3. Remove Codecs:');
  print('   Remove a=rtpmap, a=rtcp-fb, and a=fmtp lines for unwanted PT');
  print('   Remove PT from m= line format list');

  // 4. Simulcast configuration
  print('');
  print('4. Simulcast (add to video m-section):');
  print('   a=simulcast:send h;m;l');
  print('   a=rid:h send');
  print('   a=rid:m send');
  print('   a=rid:l send');

  // 5. RTCP feedback modification
  print('');
  print('5. RTCP Feedback (modify a=rtcp-fb lines):');
  print('   a=rtcp-fb:96 nack         (generic NACK)');
  print('   a=rtcp-fb:96 nack pli     (picture loss indication)');
  print('   a=rtcp-fb:96 ccm fir      (full intra request)');
  print('   a=rtcp-fb:96 transport-cc (transport-wide CC)');

  print('\n--- SDP Sections ---');
  final lines = offer.sdp.split('\n');

  // Session section
  print('\nSession Section (before first m=):');
  for (final line in lines) {
    if (line.startsWith('m=')) break;
    if (line.startsWith('v=') ||
        line.startsWith('o=') ||
        line.startsWith('s=') ||
        line.startsWith('t=')) {
      print('  $line');
    }
  }

  // Media sections
  print('\nMedia Sections:');
  var inMedia = false;
  var mediaType = '';
  for (final line in lines) {
    if (line.startsWith('m=')) {
      mediaType = line.split(' ')[0].substring(2);
      print('\n  [$mediaType]');
      print('    $line');
      inMedia = true;
    } else if (inMedia && (line.startsWith('a=rtpmap:') || line.startsWith('a=fmtp:'))) {
      print('    $line');
    }
  }

  print('\n--- Usage ---');
  print('SDP manipulation is useful for:');
  print('- Forcing specific codec selection');
  print('- Limiting bandwidth consumption');
  print('- Enabling/disabling features (simulcast, RTX)');
  print('- Interop workarounds for specific browsers');

  await pc.close();
  print('\nDone.');
}

void _printSdpSummary(String sdp) {
  final lines = sdp.split('\n');
  var lineCount = 0;
  for (final line in lines) {
    if (line.startsWith('m=') ||
        line.startsWith('a=rtpmap:') ||
        line.startsWith('a=mid:')) {
      print(line);
      lineCount++;
      if (lineCount > 15) {
        print('... (truncated)');
        break;
      }
    }
  }
}
