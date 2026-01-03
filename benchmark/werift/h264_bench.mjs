/**
 * H.264 Depacketization Benchmark for werift-webrtc
 *
 * Measures H.264 NAL unit depacketization throughput.
 * Compare results against webrtc_dart (test/performance/codec_perf_test.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node h264_bench.mjs
 */

import { H264RtpPayload } from 'werift';

console.log('H.264 Depacketization Benchmark (werift)');
console.log('='.repeat(60));

const iterations = 100000;
const warmupIterations = 1000;

// Create test payloads for different NAL unit types

// Single NAL Unit (type 1-23, non-IDR slice = type 1)
// Format: [F(1)|NRI(2)|Type(5)] + payload
const singleNalPayload = Buffer.alloc(500);
singleNalPayload[0] = 0x41; // F=0, NRI=2, Type=1 (non-IDR slice)
for (let i = 1; i < singleNalPayload.length; i++) {
  singleNalPayload[i] = i & 0xff;
}

// FU-A Start fragment (type 28)
// Format: [F(1)|NRI(2)|Type=28(5)] + [S(1)|E(1)|R(1)|Type(5)] + payload
const fuaStartPayload = Buffer.alloc(500);
fuaStartPayload[0] = 0x5c; // F=0, NRI=2, Type=28 (FU-A)
fuaStartPayload[1] = 0x85; // S=1, E=0, R=0, Type=5 (IDR)
for (let i = 2; i < fuaStartPayload.length; i++) {
  fuaStartPayload[i] = i & 0xff;
}

// FU-A End fragment
const fuaEndPayload = Buffer.alloc(500);
fuaEndPayload[0] = 0x5c; // F=0, NRI=2, Type=28 (FU-A)
fuaEndPayload[1] = 0x45; // S=0, E=1, R=0, Type=5 (IDR)
for (let i = 2; i < fuaEndPayload.length; i++) {
  fuaEndPayload[i] = i & 0xff;
}

// STAP-A (type 24) - Aggregation packet
// Format: [F(1)|NRI(2)|Type=24(5)] + [Size(16)] + NAL + [Size(16)] + NAL...
// Total size: 1 + (2+50) + (2+50) = 105 bytes
const stapAPayload = Buffer.alloc(105);
let offset = 0;
stapAPayload[offset++] = 0x58; // F=0, NRI=2, Type=24 (STAP-A)
// First NAL (50 bytes)
stapAPayload.writeUInt16BE(50, offset);
offset += 2;
stapAPayload[offset] = 0x41; // NAL header for first unit
for (let i = 1; i < 50; i++) {
  stapAPayload[offset + i] = i & 0xff;
}
offset += 50;
// Second NAL (50 bytes)
stapAPayload.writeUInt16BE(50, offset);
offset += 2;
stapAPayload[offset] = 0x41; // NAL header for second unit
for (let i = 1; i < 50; i++) {
  stapAPayload[offset + i] = i & 0xff;
}

// Benchmark: Single NAL unit
console.log('\n--- H.264 Single NAL Unit Depacketize ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  H264RtpPayload.deSerialize(singleNalPayload);
}

// Benchmark
let start = performance.now();
for (let i = 0; i < iterations; i++) {
  H264RtpPayload.deSerialize(singleNalPayload);
}
let elapsed = performance.now() - start;

let opsPerSec = (iterations / elapsed * 1000).toFixed(0);
let usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: FU-A fragments (typical video frame scenario)
console.log('\n--- H.264 FU-A Fragment Depacketize ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  const result = H264RtpPayload.deSerialize(fuaStartPayload);
  H264RtpPayload.deSerialize(fuaEndPayload, result.fragment);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  const result = H264RtpPayload.deSerialize(fuaStartPayload);
  H264RtpPayload.deSerialize(fuaEndPayload, result.fragment);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec} (2 packets per iteration)`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: STAP-A aggregation
console.log('\n--- H.264 STAP-A Depacketize ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  H264RtpPayload.deSerialize(stapAPayload);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  H264RtpPayload.deSerialize(stapAPayload);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
