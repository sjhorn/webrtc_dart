/**
 * SDP Parsing Benchmark for werift-webrtc
 *
 * Measures SDP parse/serialize throughput.
 * Compare results against webrtc_dart (test/performance/sdp_perf_test.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node sdp_bench.mjs
 */

import { SessionDescription } from 'werift';

console.log('SDP Benchmark (werift)');
console.log('='.repeat(60));

const iterations = 10000;
const warmupIterations = 100;

// Realistic WebRTC SDP with audio, video, and datachannel
const realisticSdp = `v=0
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
`;

console.log(`SDP size: ${realisticSdp.length} bytes`);

// Benchmark: Parse realistic SDP
console.log('\n--- SDP Parse realistic ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  SessionDescription.parse(realisticSdp);
}

// Benchmark
let start = performance.now();
for (let i = 0; i < iterations; i++) {
  SessionDescription.parse(realisticSdp);
}
let elapsed = performance.now() - start;

let opsPerSec = (iterations / elapsed * 1000).toFixed(0);
let usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Serialize
console.log('\n--- SDP Serialize realistic ---');

const parsed = SessionDescription.parse(realisticSdp);

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  parsed.toString();
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  parsed.toString();
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Simple SDP benchmark
console.log('\n--- SDP Parse simple ---');

const simpleSdp = `v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
`;

const simpleIterations = 50000;

// Warmup
for (let i = 0; i < 500; i++) {
  SessionDescription.parse(simpleSdp);
}

// Benchmark
start = performance.now();
for (let i = 0; i < simpleIterations; i++) {
  SessionDescription.parse(simpleSdp);
}
elapsed = performance.now() - start;

opsPerSec = (simpleIterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / simpleIterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Round-trip benchmark
console.log('\n--- SDP Round-trip (parse + serialize) ---');

const roundTripIterations = 5000;

// Warmup
for (let i = 0; i < 100; i++) {
  const p = SessionDescription.parse(realisticSdp);
  p.toString();
}

// Benchmark
start = performance.now();
for (let i = 0; i < roundTripIterations; i++) {
  const p = SessionDescription.parse(realisticSdp);
  p.toString();
}
elapsed = performance.now() - start;

opsPerSec = (roundTripIterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / roundTripIterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
