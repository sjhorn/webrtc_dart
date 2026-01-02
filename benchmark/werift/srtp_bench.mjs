/**
 * SRTP Encryption Benchmark for werift-webrtc
 *
 * Compare results against webrtc_dart (benchmark/micro/srtp_encrypt_bench.dart)
 *
 * Usage:
 *   cd benchmark/werift
 *   npm install
 *   node srtp_bench.mjs
 */

import { RtpHeader, SrtpSession, ProtectionProfileAeadAes128Gcm } from 'werift';

console.log('SRTP Encryption Benchmark (werift)');
console.log('='.repeat(60));

// Test parameters
const payloadSizes = [100, 500, 1000, 1200];
const iterations = 10000;
const warmupIterations = 1000;

// Setup keys
const masterKey = Buffer.from(Array.from({ length: 16 }, (_, i) => i));
const masterSalt = Buffer.from(Array.from({ length: 14 }, (_, i) => i + 16));

for (const payloadSize of payloadSizes) {
  console.log(`\n--- Payload size: ${payloadSize} bytes ---`);

  // Create SRTP session
  const session = new SrtpSession({
    keys: {
      localMasterKey: masterKey,
      localMasterSalt: masterSalt,
      remoteMasterKey: masterKey,
      remoteMasterSalt: masterSalt,
    },
    profile: ProtectionProfileAeadAes128Gcm,
  });

  // Create test packets
  const packets = [];
  for (let i = 0; i < iterations + warmupIterations; i++) {
    const header = new RtpHeader();
    header.payloadType = 96;
    header.sequenceNumber = i & 0xFFFF;
    header.timestamp = i * 3000;
    header.ssrc = 0x12345678;
    header.marker = false;
    header.padding = false;
    header.extension = false;

    const payload = Buffer.alloc(payloadSize);
    packets.push({ header, payload });
  }

  // Warmup
  console.log(`Warming up (${warmupIterations} iterations)...`);
  for (let i = 0; i < warmupIterations; i++) {
    session.encrypt(packets[i].payload, packets[i].header);
  }

  // Benchmark
  console.log(`Running benchmark (${iterations} iterations)...`);
  const start = performance.now();

  for (let i = 0; i < iterations; i++) {
    session.encrypt(packets[warmupIterations + i].payload, packets[warmupIterations + i].header);
  }

  const end = performance.now();
  const totalMs = end - start;

  // Calculate metrics
  const totalBytes = iterations * payloadSize;
  const packetsPerSecond = totalMs > 0 ? (iterations / totalMs * 1000).toFixed(1) : 'N/A';
  const bytesPerSecond = totalMs > 0 ? ((totalBytes / totalMs * 1000) / 1024 / 1024).toFixed(2) : 'N/A';
  const usPerPacket = totalMs > 0 ? (totalMs * 1000 / iterations).toFixed(2) : 'N/A';

  console.log('Results:');
  console.log(`  Total time:       ${totalMs.toFixed(0)} ms`);
  console.log(`  Packets/second:   ${packetsPerSecond}`);
  console.log(`  Throughput:       ${bytesPerSecond} MB/s`);
  console.log(`  Time per packet:  ${usPerPacket} us`);
}

console.log('\n' + '='.repeat(60));
console.log('Benchmark complete');
