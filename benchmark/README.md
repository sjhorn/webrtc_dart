# Performance Benchmarks

Compare webrtc_dart (Dart) against werift-webrtc (TypeScript/Node.js) to identify optimization opportunities.

## Quick Start

```bash
# Run all Dart benchmarks
dart run benchmark/run_all.dart

# Run individual benchmarks
dart run benchmark/micro/srtp_encrypt_bench.dart
dart run benchmark/micro/rtp_parse_bench.dart

# Run werift comparison (requires Node.js)
cd benchmark/werift
npm install
node srtp_bench.mjs
```

## Directory Structure

```
benchmark/
├── README.md                    # This file
├── run_all.dart                 # Runner script
├── micro/                       # Component-level benchmarks
│   ├── srtp_encrypt_bench.dart  # SRTP encryption throughput
│   ├── srtp_decrypt_bench.dart  # SRTP decryption throughput
│   ├── rtp_parse_bench.dart     # RTP packet parsing
│   └── sctp_chunk_bench.dart    # SCTP chunk handling
├── macro/                       # End-to-end benchmarks
│   ├── datachannel_bench.dart   # DataChannel throughput
│   └── media_forward_bench.dart # Media forwarding (SFU)
└── werift/                      # TypeScript comparison
    ├── package.json
    ├── srtp_bench.mjs           # SRTP comparison
    └── datachannel_bench.mjs    # DataChannel comparison
```

## Benchmarks

### Micro-Benchmarks

| Benchmark | Metrics | Target |
|-----------|---------|--------|
| SRTP Encrypt | packets/sec, bytes/sec | Match werift |
| SRTP Decrypt | packets/sec, bytes/sec | Match werift |
| RTP Parse | parses/sec, µs/parse | < 1µs/parse |
| SCTP Chunk | chunks/sec | Match werift |

### Macro-Benchmarks

| Benchmark | Metrics | Target |
|-----------|---------|--------|
| DataChannel | messages/sec, latency p50/p95/p99 | Match werift |
| Media Forward | packets/sec in/out | Match werift |

## Known Performance Issues

### Critical: Per-Packet Cipher Instantiation

**Location:** `lib/src/srtp/srtp_cipher.dart`

```dart
// Current: NEW cipher created for EVERY packet
final gcm = GCMBlockCipher(AESEngine());  // Expensive!
gcm.init(true, params);
```

**Fix:** Cache cipher instance per SSRC, only update nonce.

### High: Excessive Memory Allocations

Each encrypted packet creates 6-8 `Uint8List` allocations:
- Nonce buffer (12 bytes)
- Counter buffer (16 bytes)
- Output buffer
- Final result buffer
- Header serialization

**Fix:** Buffer pooling, pre-allocated working buffers.

### Medium: SCTP Queue Operations

```dart
// O(n) operations on List
_sentQueue.indexOf(chunk);  // O(n) search
_sentQueue.removeAt(0);     // O(n) removal
```

**Fix:** Use `Queue<T>` or `LinkedList<T>` for O(1) operations.

## Running Comparison

```bash
# 1. Run Dart benchmark
dart run benchmark/micro/srtp_encrypt_bench.dart > dart_results.txt

# 2. Run werift benchmark
cd benchmark/werift && node srtp_bench.mjs > werift_results.txt

# 3. Compare results
diff dart_results.txt werift_results.txt
```

## Expected Optimization Gains

| Optimization | Expected Gain |
|--------------|---------------|
| Cipher caching per SSRC | 10-50x |
| Pre-allocated nonce buffers | 2-5x |
| Buffer pooling | 2-3x |
| Remove false async | 1.2-1.5x |
| SCTP queue → Queue<T> | 2-10x on large queues |
