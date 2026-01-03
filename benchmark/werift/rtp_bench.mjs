/**
 * RTP Packet Benchmark for werift-webrtc
 *
 * Measures RTP packet parse/serialize throughput.
 * Compare results against webrtc_dart (test/performance/rtp_perf_test.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node rtp_bench.mjs
 */

import { RtpHeader, RtpPacket } from 'werift';

console.log('RTP Packet Benchmark (werift)');
console.log('='.repeat(60));

const iterations = 100000;
const warmupIterations = 1000;

// Create a realistic RTP packet (1200 byte payload)
const testHeader = new RtpHeader();
testHeader.payloadType = 96;
testHeader.sequenceNumber = 12345;
testHeader.timestamp = 3000000;
testHeader.ssrc = 0x12345678;
testHeader.marker = true;
testHeader.padding = false;
testHeader.extension = false;

const payload = Buffer.alloc(1200);

// RtpPacket combines header + payload
const packet = new RtpPacket(testHeader, payload);
const serialized = packet.serialize();

console.log(`Packet size: ${serialized.length} bytes`);

// Benchmark: Parse
console.log('\n--- RTP Parse ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  RtpPacket.deSerialize(serialized);
}

// Benchmark
let start = performance.now();
for (let i = 0; i < iterations; i++) {
  RtpPacket.deSerialize(serialized);
}
let elapsed = performance.now() - start;

let opsPerSec = (iterations / elapsed * 1000).toFixed(0);
let usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Serialize
console.log('\n--- RTP Serialize ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  packet.serialize();
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  packet.serialize();
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Round-trip
console.log('\n--- RTP Round-trip (serialize + parse) ---');

const roundTripIterations = 50000;

// Warmup
for (let i = 0; i < 500; i++) {
  const s = packet.serialize();
  RtpPacket.deSerialize(s);
}

// Benchmark
start = performance.now();
for (let i = 0; i < roundTripIterations; i++) {
  const s = packet.serialize();
  RtpPacket.deSerialize(s);
}
elapsed = performance.now() - start;

opsPerSec = (roundTripIterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / roundTripIterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
