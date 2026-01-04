# webrtc_dart Roadmap

## Current Status (v0.24.0)

webrtc_dart is a **server-side** WebRTC library with complete transport implementation and W3C-compatible API naming.

### What We Are

A server-side WebRTC library like [Pion](https://github.com/pion/webrtc) (Go), [aiortc](https://github.com/aiortc/aiortc) (Python), and [werift](https://github.com/shinyoshiaki/werift-webrtc) (TypeScript).

| Category | Status |
|----------|--------|
| **Transport Layer** | Complete (ICE, DTLS, SRTP, SCTP, RTP/RTCP) |
| **API Naming** | W3C-compatible (RTCPeerConnection, etc.) |
| **Werift Parity** | 100% feature complete |
| **Browser Interop** | Chrome, Firefox, Safari working |
| **Test Coverage** | 2625 tests passing |

### Server-Side vs Browser

| Feature | Browser | webrtc_dart |
|---------|---------|-------------|
| ICE/DTLS/SRTP transport | Yes | Yes |
| DataChannels | Yes | Yes |
| RTP packet handling | Limited | Full control |
| Camera/mic capture | Yes | No (use FFmpeg) |
| Video/audio encoding | Yes | No |
| Video/audio decoding | Yes | Depacketization only |

### Transport Layer - 100% Complete

| Protocol | Coverage |
|----------|----------|
| **ICE** | RFC 8445 + consent freshness + TCP + mDNS |
| **DTLS** | ECDHE with AES-GCM, AES-256, ChaCha20 |
| **SRTP** | AES-CM-128, AES-GCM, replay protection |
| **SCTP** | Partial reliability (RFC 3758) |
| **RTP/RTCP** | SR, RR, SDES, BYE, NACK, PLI, FIR, REMB, TWCC |

### API Classes

| Interface | Notes |
|-----------|-------|
| `RTCPeerConnection` | Full transport API |
| `RTCDataChannel` | Full API |
| `RTCRtpTransceiver` | Full API |
| `RTCRtpSender` | Includes DTMF |
| `RTCRtpReceiver` | Raw RTP access |
| `RTCIceCandidate` | Full API |
| `RTCSessionDescription` | Full API |

### Codec Depacketization

Extracts codec frames from RTP - does NOT encode/decode:

| Codec | Depacketize | Encode | Decode |
|-------|:-----------:|:------:|:------:|
| VP8 | ✅ | - | - |
| VP9 | ✅ | - | - |
| H.264 | ✅ | - | - |
| AV1 | ✅ | - | - |
| Opus | ✅ | - | - |

---

## Future Roadmap

### Short-term: Performance Optimization

**Benchmark Results (1000-byte payload):**

| Implementation | Packets/sec | Throughput | Per-packet |
|----------------|-------------|------------|------------|
| werift (Node.js) | 418,134 | 399 MB/s | 2.4 µs |
| webrtc_dart (optimized) | 23,753 | 22.7 MB/s | 42 µs |
| webrtc_dart (before) | 1,903 | 1.8 MB/s | 526 µs |
| **Improvement** | **12.5x faster** | | |
| **Remaining gap** | **~18x vs werift** | | |

Run benchmarks: `dart run benchmark/micro/srtp_encrypt_bench.dart`

**Completed Optimizations:**
- ✅ **SCTP immediate SACK (261x faster DataChannel RTT)**
- ✅ SCTP queue batch removal (230x faster at 5000 chunks)
- ✅ SRTP cipher caching with `package:cryptography` (12.5x faster)

**DataChannel Round-Trip Benchmark:**

| Message Size | Before | After | Speedup |
|--------------|--------|-------|---------|
| 100B | 204ms | 0.5ms | **408x** |
| 1KB | 204ms | 0.78ms | **261x** |

Run benchmark: `dart run example/benchmark/datachannel.dart`

**Comparison with werift (1KB RTT):**

| Implementation | RTT | Gap |
|----------------|-----|-----|
| werift (Node.js) | 0.23ms | 1x |
| webrtc_dart | 0.78ms | 3.4x |

**DataChannel Throughput:** ~200 MB/s (4KB messages)

**Investigated & Deferred:**

| Issue | Finding |
|-------|---------|
| Buffer pooling | Only 0.1% of SRTP time - not worthwhile |
| scheduleMicrotask vs Timer | 15x faster scheduling (~0.2µs vs 3.4µs) but negligible impact on RTT |
| Synchronous SACK | Caused 10x throughput regression - Timer batching is better |
| Native crypto FFI | Would close remaining gap but requires significant effort |

**Note:** The remaining ~3.4x gap vs werift is due to Dart event loop overhead
and JIT differences. Further optimization would require native FFI bindings.

### Benchmarking Infrastructure

**Performance Regression Tests** (`test/performance/`) - 38 tests:
- Automated tests that warn when performance drops below thresholds
- Run: `dart test test/performance/` or `./benchmark/run_perf_tests.sh`

| Test File | Coverage |
|-----------|----------|
| `srtp_perf_test.dart` | SRTP encrypt/decrypt |
| `rtp_perf_test.dart` | RTP parse/serialize |
| `sdp_perf_test.dart` | SDP parse/serialize |
| `stun_perf_test.dart` | STUN parse/serialize |
| `sctp_perf_test.dart` | SCTP queue operations |
| `dtls_perf_test.dart` | DTLS anti-replay window |
| `codec_perf_test.dart` | VP8/H.264 depacketization |
| `rtcp_perf_test.dart` | RTCP NACK serialize/parse |
| `ice_perf_test.dart` | ICE candidate parse/serialize |

**Current Performance (webrtc_dart v0.24.0 vs werift v0.22.2):**

| Operation | webrtc_dart | werift | Comparison |
|-----------|-------------|--------|------------|
| RTP parse | 3.5M ops/s | 1.4M ops/s | **2.5x faster** |
| RTP serialize | 4.8M ops/s | 3.8M ops/s | 1.3x faster |
| STUN parse | 1.2M ops/s | 0.6M ops/s | **2x faster** |
| SDP parse | 67K ops/s | 22K ops/s | **3x faster** |
| H.264 depacketize | 2.9M ops/s | 1.1M ops/s | **2.6x faster** |
| ICE candidate parse | 5.0M ops/s | 13M ops/s | 2.6x slower* |
| Anti-replay window | 71M ops/s | - | - |
| SRTP encrypt 1KB | 20K ops/s | 418K ops/s | 21x slower* |

\*SRTP gap is due to Node.js native crypto vs Dart pure implementation

**Benchmark Commands:**
```bash
# Run Dart performance tests
./benchmark/run_perf_tests.sh

# Run werift comparison benchmarks
./benchmark/run_werift_benchmarks.sh

# Compare both side-by-side
./benchmark/compare.sh

# Save results for a release
dart run benchmark/save_results.dart v0.24.0
```

**Historical Results:** Stored in `benchmark/results/<version>.json`

### Medium-term

- ICE-LITE for server deployments
- Enhanced SVC layer control
- Insertable Streams API
- **DataChannel close() deadlock fix**: When both peers close simultaneously, RFC 6525 stream reset requests can deadlock. Options:
  - Add timeout to graceful close
  - Process incoming reconfig requests while in closing state
  - Provide non-blocking close option
- **RTCP Extended Reports (XR)** - RFC 3611: Advanced QoS metrics for SFU analytics
  - Priority: Low (browsers don't generate, not required for basic WebRTC)
  - Use cases: VoIP monitoring, quality dashboards, SFU operators

### Long-term

- Flutter platform channel bindings
- WebTransport (HTTP/3 QUIC)
- WHIP/WHEP protocols

---

## Backward Compatibility

v0.23.1 maintains backward compatibility via deprecated typedefs:

```dart
@Deprecated('Use RTCPeerConnection instead')
typedef RtcPeerConnection = RTCPeerConnection;
```

---

## Architecture

```
RTCPeerConnection API
        |
   SDP Manager
        |
  RTP/RTCP Stack
        |
   SRTP/SRTCP
        |
      DTLS
        |
      ICE
        |
   UDP/TCP Sockets
```

---

## References

- [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) - Original TypeScript implementation
- [Pion](https://github.com/pion/webrtc) - Go WebRTC
- [aiortc](https://github.com/aiortc/aiortc) - Python WebRTC
