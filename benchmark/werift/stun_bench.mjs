/**
 * STUN Message Benchmark for werift-webrtc
 *
 * Measures STUN message parse/serialize throughput.
 * Compare results against webrtc_dart (test/performance/stun_perf_test.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node stun_bench.mjs
 */

import { Message, parseMessage, methods, classes } from 'werift';

console.log('STUN Message Benchmark (werift)');
console.log('='.repeat(60));

const iterations = 50000;
const warmupIterations = 500;

// Create a typical binding request
const transactionId = Buffer.from([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);

const message = new Message(methods.BINDING, classes.REQUEST, transactionId);
message.setAttribute('USERNAME', 'abcd1234:efgh5678');
message.setAttribute('PRIORITY', 2130706431);
message.setAttribute('ICE-CONTROLLED', BigInt(123456789));

const serialized = message.bytes;

console.log(`Message size: ${serialized.length} bytes`);

// Benchmark: Parse binding request
console.log('\n--- STUN Parse binding request ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  parseMessage(serialized);
}

// Benchmark
let start = performance.now();
for (let i = 0; i < iterations; i++) {
  parseMessage(serialized);
}
let elapsed = performance.now() - start;

let opsPerSec = (iterations / elapsed * 1000).toFixed(0);
let usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Serialize
console.log('\n--- STUN Serialize binding request ---');

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  message.bytes;
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  message.bytes;
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Parse response with XOR-MAPPED-ADDRESS
console.log('\n--- STUN Parse binding response ---');

const response = new Message(methods.BINDING, classes.RESPONSE, transactionId);
response.setAttribute('XOR-MAPPED-ADDRESS', ['192.168.1.100', 54321]);
response.setAttribute('MAPPED-ADDRESS', ['192.168.1.100', 54321]);
const responseSerialized = response.bytes;

// Warmup
for (let i = 0; i < warmupIterations; i++) {
  parseMessage(responseSerialized);
}

// Benchmark
start = performance.now();
for (let i = 0; i < iterations; i++) {
  parseMessage(responseSerialized);
}
elapsed = performance.now() - start;

opsPerSec = (iterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / iterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

// Benchmark: Round-trip
console.log('\n--- STUN Round-trip (serialize + parse) ---');

const roundTripIterations = 30000;

// Warmup
for (let i = 0; i < 300; i++) {
  const s = message.bytes;
  parseMessage(s);
}

// Benchmark
start = performance.now();
for (let i = 0; i < roundTripIterations; i++) {
  const s = message.bytes;
  parseMessage(s);
}
elapsed = performance.now() - start;

opsPerSec = (roundTripIterations / elapsed * 1000).toFixed(0);
usPerOp = (elapsed * 1000 / roundTripIterations).toFixed(2);
console.log(`  Ops/second: ${opsPerSec}`);
console.log(`  Time per op: ${usPerOp} us`);

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
