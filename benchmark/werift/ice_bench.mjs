/**
 * ICE Candidate Benchmark for werift-webrtc
 *
 * Measures ICE candidate parse/serialize throughput.
 * Compare results against webrtc_dart (test/performance/ice_perf_test.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node ice_bench.mjs
 */

import { Candidate } from 'werift';

console.log('ICE Candidate Benchmark (werift)');
console.log('='.repeat(60));

const iterations = 200000;
const warmupIterations = 1000;

// Test SDP strings for different candidate types
const hostSdp = '6815297761 1 udp 2130706431 192.168.1.100 31102 typ host generation 0 ufrag b7l3';
const srflxSdp = '842163049 1 udp 1694498815 203.0.113.50 54321 typ srflx raddr 192.168.1.100 rport 31102 generation 0 ufrag b7l3';
const relaySdp = '3745641921 1 udp 41885439 203.0.113.100 54322 typ relay raddr 203.0.113.50 rport 54321 generation 0 ufrag b7l3';
const tcpSdp = '1234567890 1 tcp 2105458943 192.168.1.100 9 typ host tcptype passive generation 0';

// Pre-create a candidate for serialize tests
const hostCandidate = new Candidate(
  '6815297761',
  1,
  'udp',
  2130706431,
  '192.168.1.100',
  31102,
  'host',
  undefined,  // relatedAddress
  undefined,  // relatedPort
  undefined,  // tcptype
  0,          // generation
  'b7l3'      // ufrag
);

// Benchmark: Parse host candidate
console.log('\n--- ICE Parse Host Candidate ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  Candidate.fromSdp(hostSdp);
}

// Benchmark
let start = performance.now();
for (let i = 0; i < iterations; i++) {
  Candidate.fromSdp(hostSdp);
}
let elapsed = performance.now() - start;

let opsPerSec = (iterations / elapsed * 1000).toFixed(0);
let usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Parse srflx candidate
console.log('\n--- ICE Parse Srflx Candidate ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  Candidate.fromSdp(srflxSdp);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  Candidate.fromSdp(srflxSdp);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Parse relay candidate
console.log('\n--- ICE Parse Relay Candidate ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  Candidate.fromSdp(relaySdp);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  Candidate.fromSdp(relaySdp);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Parse TCP candidate
console.log('\n--- ICE Parse TCP Candidate ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  Candidate.fromSdp(tcpSdp);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  Candidate.fromSdp(tcpSdp);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Serialize candidate
console.log('\n--- ICE Serialize Candidate ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  hostCandidate.toSdp();
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  hostCandidate.toSdp();
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Round-trip (parse + serialize)
console.log('\n--- ICE Round-trip (parse + serialize) ---');

const roundTripIterations = 100000;

// Warmup
for (let i = 0; i < 500; i++) {
  const c = Candidate.fromSdp(hostSdp);
  c.toSdp();
}

// Benchmark
start = performance.now();
for (let i = 0; i < roundTripIterations; i++) {
  const c = Candidate.fromSdp(hostSdp);
  c.toSdp();
}
elapsed = performance.now() - start;

opsPerSec = (roundTripIterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / roundTripIterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
