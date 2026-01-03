/// SDP Parsing Performance Regression Tests
///
/// Tests SDP parse/serialize throughput.
/// SDP parsing happens on every offer/answer exchange.
///
/// Run: dart test test/performance/sdp_perf_test.dart
@Tags(['performance'])
library;

import 'package:test/test.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

import 'perf_test_utils.dart';

/// Realistic WebRTC SDP with audio, video, and datachannel
const _realisticSdp = '''
v=0
o=- 4495506546851695000 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0 1 2
a=extmap-allow-mixed
a=msid-semantic: WMS stream1
m=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghijklmnopqrstuvwxyz12
a=ice-options:trickle
a=fingerprint:sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99
a=setup:actpass
a=mid:0
a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid
a=sendrecv
a=msid:stream1 audio1
a=rtcp-mux
a=rtpmap:111 opus/48000/2
a=rtcp-fb:111 transport-cc
a=fmtp:111 minptime=10;useinbandfec=1
a=rtpmap:63 red/48000/2
a=fmtp:63 111/111
a=rtpmap:9 G722/8000
a=rtpmap:0 PCMU/8000
a=rtpmap:8 PCMA/8000
a=rtpmap:13 CN/8000
a=rtpmap:110 telephone-event/48000
a=rtpmap:126 telephone-event/8000
a=ssrc:1234567890 cname:abcdefg
a=ssrc:1234567890 msid:stream1 audio1
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99 100 101 102 127 124
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghijklmnopqrstuvwxyz12
a=ice-options:trickle
a=fingerprint:sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99
a=setup:actpass
a=mid:1
a=extmap:14 urn:ietf:params:rtp-hdrext:toffset
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time
a=extmap:13 urn:3gpp:video-orientation
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay
a=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type
a=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing
a=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid
a=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id
a=sendrecv
a=msid:stream1 video1
a=rtcp-mux
a=rtcp-rsize
a=rtpmap:96 VP8/90000
a=rtcp-fb:96 goog-remb
a=rtcp-fb:96 transport-cc
a=rtcp-fb:96 ccm fir
a=rtcp-fb:96 nack
a=rtcp-fb:96 nack pli
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=rtpmap:98 VP9/90000
a=rtcp-fb:98 goog-remb
a=rtcp-fb:98 transport-cc
a=rtcp-fb:98 ccm fir
a=rtcp-fb:98 nack
a=rtcp-fb:98 nack pli
a=fmtp:98 profile-id=0
a=rtpmap:99 rtx/90000
a=fmtp:99 apt=98
a=rtpmap:100 H264/90000
a=rtcp-fb:100 goog-remb
a=rtcp-fb:100 transport-cc
a=rtcp-fb:100 ccm fir
a=rtcp-fb:100 nack
a=rtcp-fb:100 nack pli
a=fmtp:100 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f
a=rtpmap:101 rtx/90000
a=fmtp:101 apt=100
a=rtpmap:102 AV1/90000
a=rtcp-fb:102 goog-remb
a=rtcp-fb:102 transport-cc
a=rtcp-fb:102 ccm fir
a=rtcp-fb:102 nack
a=rtcp-fb:102 nack pli
a=rtpmap:127 rtx/90000
a=fmtp:127 apt=102
a=rtpmap:124 red/90000
a=ssrc-group:FID 2345678901 3456789012
a=ssrc:2345678901 cname:abcdefg
a=ssrc:2345678901 msid:stream1 video1
a=ssrc:3456789012 cname:abcdefg
a=ssrc:3456789012 msid:stream1 video1
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghijklmnopqrstuvwxyz12
a=ice-options:trickle
a=fingerprint:sha-256 AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99
a=setup:actpass
a=mid:2
a=sctp-port:5000
a=max-message-size:262144
''';

void main() {
  group('SDP Performance', () {
    test('parse realistic SDP meets threshold', () {
      const iterations = 10000;

      final result = runBenchmarkSync(
        name: 'SDP parse realistic',
        iterations: iterations,
        warmupIterations: 100,
        operation: () {
          SdpMessage.parse(_realisticSdp);
        },
        metadata: {'sdpSize': _realisticSdp.length, 'mediaCount': 3},
      );

      // Threshold: >5,000 parses/sec
      // SDP parsing is string-heavy, so slower than binary parsing
      result.checkThreshold(PerfThreshold(
        name: 'SDP parse realistic',
        minOpsPerSecond: 5000,
      ));
    });

    test('serialize realistic SDP meets threshold', () {
      const iterations = 10000;

      final parsed = SdpMessage.parse(_realisticSdp);

      final result = runBenchmarkSync(
        name: 'SDP serialize realistic',
        iterations: iterations,
        warmupIterations: 100,
        operation: () {
          parsed.toString();
        },
      );

      // Threshold: >10,000 serializes/sec
      result.checkThreshold(PerfThreshold(
        name: 'SDP serialize realistic',
        minOpsPerSecond: 10000,
      ));
    });

    test('parse simple SDP meets threshold', () {
      const iterations = 50000;

      const simpleSdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
''';

      final result = runBenchmarkSync(
        name: 'SDP parse simple',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          SdpMessage.parse(simpleSdp);
        },
      );

      // Threshold: >20,000 parses/sec for simple SDPs
      result.checkThreshold(PerfThreshold(
        name: 'SDP parse simple',
        minOpsPerSecond: 20000,
      ));
    });

    test('round-trip (parse + serialize) meets threshold', () {
      const iterations = 5000;

      final result = runBenchmarkSync(
        name: 'SDP round-trip',
        iterations: iterations,
        warmupIterations: 100,
        operation: () {
          final parsed = SdpMessage.parse(_realisticSdp);
          parsed.toString();
        },
      );

      // Threshold: >3,000 round-trips/sec
      result.checkThreshold(PerfThreshold(
        name: 'SDP round-trip',
        minOpsPerSecond: 3000,
      ));
    });
  });
}
