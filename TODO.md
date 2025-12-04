# TODO.md - webrtc_dart

**Last Updated:** December 2025

---

## Current Status

**Phase 4: COMPLETE** - werift Parity Achieved
**Test Count:** 1650 tests passing
**Analyzer:** 0 errors, 0 warnings, 3 info (intentional design choices)
**Browser Interop: WORKING** - Dart ↔ Chrome/Firefox/Safari DataChannel

---

## Remaining Items for werift Parity

### Examples (from werift-webrtc/examples)

| Category | werift Example | Dart Status |
|----------|---------------|-------------|
| **DataChannel** | `local.ts` | ✅ `datachannel_local.dart` |
| **DataChannel** | `offer.ts`, `answer.ts` | ✅ `signaling/offer.dart`, `signaling/answer.dart` |
| **DataChannel** | `string.ts` | ✅ `datachannel_string.dart` |
| **MediaChannel** | `sendonly/`, `recvonly/`, `sendrecv/` | ✅ `mediachannel_local.dart` |
| **MediaChannel** | `simulcast/` | ✅ `simulcast_local.dart` |
| **MediaChannel** | `codec/` (vp8, vp9, h264, av1) | ❌ Need actual codec streams |
| **MediaChannel** | `twcc/` | ✅ `twcc_congestion.dart` |
| **MediaChannel** | `red/` | ✅ `red_redundancy.dart` |
| **MediaChannel** | `rtx/` | ✅ `rtx_retransmission.dart` |
| **save_to_disk** | `vp8.ts`, `opus.ts`, `h264.ts` | ✅ `save_to_disk.dart` |
| **save_to_disk** | `mp4/` | ✅ `save_to_disk_mp4.dart` |
| **ICE** | `restart/` | ✅ `ice_restart.dart` |
| **ICE** | `trickle/` | ✅ `ice_trickle.dart` |
| **ICE** | `turn/` | ✅ `ice_turn.dart` |
| **getStats** | `demo.ts` | ✅ `getstats_demo.dart` |
| **close** | `dc/` | ✅ `close_datachannel.dart` |
| **close** | `pc/` | ✅ `close_peerconnection.dart` |

### Benchmarks

| Benchmark | Status |
|-----------|--------|
| `datachannel.ts` - DataChannel throughput | ✅ `datachannel_benchmark.dart` |

### Code TODOs

Minor items found in codebase (non-blocking):

**Media/Codec:**
- `rtp_transceiver.dart:447` - Video frame encoding to codec format

**Stats:**
- ~~`peer_connection.dart:1307-1336` - Extended getStats implementation~~ ✅ DONE
  - Track selector filtering implemented
  - Data channel open/close counting added

**DTLS:**
- `client_handshake.dart:222` - Certificate chain validation
- `server_handshake.dart:164,224` - Certificate/CertificateVerify parsing
- `server_flights.dart:175` - CertificateRequest message

**SCTP:**
- ~~`association.dart:166` - Stream sequence tracking~~ ✅ DONE (per-stream sequence numbers)
- `association.dart:421,463,509,563` - Collision handling, cookie verification, retransmission

**DataChannel:**
- `data_channel.dart:223` - Graceful close with message delivery

**Other:**
- ~~`peer_connection.dart:725` - ICE-lite detection from SDP~~ ✅ DONE
- `peer_connection.dart:1246` - Remote SSRC matching (requires RtpRouter)

---

## Browser Interop Status

| Browser | DataChannel | Media | Status |
|---------|-------------|-------|--------|
| Chrome | ✅ | ✅ | Working |
| Firefox | ✅ | ✅ | Working |
| Safari (WebKit) | ✅ | ✅ | Working |

Automated Playwright test suite in `interop/automated/`

---

## Completed Features (werift Parity)

### Core Protocols
- [x] STUN message encode/decode with MESSAGE-INTEGRITY and FINGERPRINT
- [x] ICE candidate model (host, srflx, relay, prflx)
- [x] ICE checklists, connectivity checks, nomination
- [x] DTLS 1.2 handshake state machine with mutual certificate authentication
- [x] SRTP/SRTCP implementation (AES-CTR/AES-CM + HMAC-SHA1)
- [x] RTP/RTCP stack (SR, RR, SDES, BYE)
- [x] SCTP association over DTLS
- [x] DataChannel protocol (reliable/unreliable, ordered/unordered)
- [x] SDP parsing and generation

### Video Codec Depacketization
- [x] VP8 depacketization (22 tests)
- [x] VP9 depacketization with SVC support (25 tests)
- [x] H.264 depacketization with FU-A/STAP-A (22 tests)
- [x] AV1 depacketization with OBU parsing (32 tests)

### RTCP Feedback
- [x] NACK (Generic Negative Acknowledgement) with NackHandler (41 tests)
- [x] PLI (Picture Loss Indication) (48 tests)
- [x] FIR (Full Intra Request) (48 tests)

### Retransmission
- [x] RTX packet wrapping/unwrapping (85 tests)
- [x] RetransmissionBuffer (128-packet circular buffer)
- [x] RTX SDP negotiation (a=rtpmap, a=fmtp apt=, ssrc-group:FID)

### TURN
- [x] TURN allocation with 401 authentication (RFC 5766)
- [x] Channel binding (0x4000-0x7FFF)
- [x] Permission management
- [x] Send/Data indications
- [x] ICE integration with relay candidates
- [x] Data relay via TURN (50 tests)

### TWCC (Transport-Wide Congestion Control)
- [x] Transport-wide sequence numbers (RTP header extension)
- [x] Receive delta encoding/decoding
- [x] Packet status chunks (RunLengthChunk, StatusVectorChunk)
- [x] Bandwidth estimation algorithm (SenderBWE)
- [x] Congestion control feedback (RTCP TWCC)

### Simulcast Support
- [x] RID (Restriction Identifier) support (RFC 8851)
- [x] RTP header extension parsing for RID/MID
- [x] SDP simulcast attribute parsing (a=rid, a=simulcast)
- [x] RtpRouter for RID-based packet routing
- [x] Multiple encoding layers per track
- [x] Layer selection/switching API

### Jitter Buffer
- [x] Packet reordering by RTP timestamp
- [x] Configurable buffer sizing with overflow protection
- [x] Late packet handling (timeout-based loss detection)
- [x] Gap detection and sequence wraparound handling

### Quality Features
- [x] RED (Redundancy Encoding) for audio (RFC 2198)
- [x] Media Track Management (addTrack, removeTrack, replaceTrack)
- [x] ICE Restart
- [x] Extended getStats() API (ICE, transport, data channel stats)

### Advanced Features
- [x] SVC (Scalable Video Coding) for VP9
- [x] ICE TCP Candidates
- [x] mDNS Candidate Obfuscation
- [x] DTX (Discontinuous Transmission)
- [x] Lip Sync (A/V synchronization)
- [x] IPv6 Support (global unicast)

### Media Recording (WebM/MP4)
- [x] EBML encoding/decoding
- [x] WebM container builder
- [x] WebM processor
- [x] MP4 container support (fMP4)

### Nonstandard Media APIs
- [x] MuteHandler for silence frame insertion
- [x] RtpStream for stream-based processing
- [x] MediaStreamTrack/MediaStream
- [x] Navigator/MediaDevices API

### REMB (Receiver Estimated Max Bitrate)
- [x] REMB RTCP packet parsing/serialization

### Processor Framework
- [x] Processor base interface
- [x] NtpTime processor
- [x] StreamStatistics class

### OGG Container
- [x] OGG page parsing
- [x] OGG Opus packet extraction

---

## Future (Phase 5) - Beyond werift

> These features are NOT in werift-webrtc and would need to be built from RFCs.

- [ ] FEC (Forward Error Correction) - FlexFEC/ULPFEC
- [ ] RTCP XR (Extended Reports) - RFC 3611
- [ ] RTCP APP (Application-defined packets)
- [ ] Full GCC (Google Congestion Control) algorithm
- [ ] Insertable Streams API (W3C standard)

---

## Quick Reference

### Run Tests
```bash
dart test
```

### Run Browser Interop Test (Manual)
```bash
dart run interop/browser/server.dart
# Open http://localhost:8080 in Chrome
```

### Run Automated Browser Tests (Playwright)
```bash
cd interop
npm install
npm test              # Test all browsers
npm run test:chrome   # Test Chrome only
npm run test:firefox  # Test Firefox only
npm run test:safari   # Test Safari/WebKit only
```

### Run TypeScript Interop Test
```bash
node interop/js_answerer.mjs &
dart run interop/dart_offerer.dart
```

---

See **ROADMAP.md** for detailed implementation plans.
