# TODO.md - webrtc_dart

**Last Updated:** November 2025

---

## Current Status

**Phase 1: COMPLETE** - 891 tests passing
**Browser Interop: WORKING** - Dart ↔ Chrome DataChannel

---

## Completed (Phase 1)

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

### Observability
- [x] getStats() MVP - RTCPeerConnectionStats, Inbound/Outbound RTP stats (9 tests)

### Interop
- [x] Dart ↔ TypeScript (werift) DataChannel
- [x] Dart ↔ Chrome Browser DataChannel

---

## In Progress (Phase 2)

### Browser Interop Testing
- [ ] Firefox ↔ webrtc_dart
- [ ] Safari ↔ webrtc_dart (H.264)
- [ ] Automated browser test suite

### TWCC (Transport-Wide Congestion Control)
- [ ] Transport-wide sequence numbers (RTP header extension)
- [ ] Receive delta encoding/decoding
- [ ] Packet status chunks (run-length, status vector)
- [ ] Bandwidth estimation algorithm
- [ ] Congestion control feedback (RTCP TWCC)

### Simulcast Support
- [ ] RID (Restriction Identifier) support (RFC 8851)
- [ ] Multiple encoding layers per track
- [ ] SDP simulcast attribute parsing
- [ ] Layer selection/switching

### Jitter Buffer
- [ ] Packet reordering by RTP timestamp
- [ ] Adaptive buffer sizing
- [ ] Late packet handling
- [ ] Gap detection

---

## Planned (Phase 3)

### Quality Features
- [ ] RED (Redundancy Encoding) for audio
- [ ] Media Track Management (addTrack, removeTrack, replaceTrack)
- [ ] ICE Restart
- [ ] Extended getStats() API

### Advanced Features
- [ ] SVC (Scalable Video Coding) for VP9
- [ ] ICE TCP Candidates
- [ ] mDNS Candidate Obfuscation
- [ ] IPv6 Support Improvements
- [ ] DTX (Discontinuous Transmission)
- [ ] Lip Sync (A/V synchronization)

---

## Future (Phase 4)

- [ ] Media Recording (WebM, MP4, Ogg containers)
- [ ] Insertable Streams API
- [ ] Advanced Bandwidth Estimation (GCC/REMB)
- [ ] FEC (Forward Error Correction)
- [ ] Advanced RTCP Features (XR, SDES, APP)

---

## Bugs Fixed (November 2025)

1. **ICE-CONTROLLING/ICE-CONTROLLED BigInt type** - Type mismatch in 64-bit STUN attributes
2. **SCTP CRC32c polynomial** - Use reflected Castagnoli polynomial
3. **SCTP checksum endianness** - Use little-endian per RFC 4960
4. **SCTP State Cookie extraction** - Parse TLV parameters correctly
5. **DTLS Certificate and CertificateVerify** - Support mutual authentication
6. **DTLS future-epoch record buffering** - Buffer out-of-order encrypted records
7. **DTLS retransmission handling** - Ignore duplicate handshake messages
8. **STUN ICE-CONTROLLING/ICE-CONTROLLED int acceptance** - Accept both int and BigInt

---

## Quick Reference

### Run Tests
```bash
dart test
```

### Run Browser Interop Test
```bash
dart run interop/browser/server.dart
# Open http://localhost:8080 in Chrome
```

### Run TypeScript Interop Test
```bash
node interop/js_answerer.mjs &
dart run interop/dart_offerer.dart
```

---

See **ROADMAP.md** for detailed implementation plans and timelines.
