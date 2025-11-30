# webrtc_dart Roadmap - Path to Full Feature Parity

## Current Status (November 2025)

### ✅ MVP COMPLETE - DataChannel + Audio Infrastructure

**Implemented Components:**
- Core Protocols: STUN, ICE, DTLS, SRTP/SRTCP, SCTP, RTP/RTCP
- DataChannel: Full DCEP implementation with pre-connection support
- Audio: RTP transport layer complete (Opus payload format)
- PeerConnection: W3C-compatible API
- Test Coverage: 891 tests (100% pass rate)
- Interop: Dart ↔ Chrome Browser **WORKING** (November 2025)
- Interop: Dart ↔ TypeScript (werift) **WORKING** (November 2025)
- Stability: 60-second stability test passing with bidirectional messaging

### ✅ Interop Bugs Fixed (November 2025)

The following bugs were discovered and fixed during Dart ↔ TypeScript interop debugging:

1. **ICE-CONTROLLING/ICE-CONTROLLED BigInt type** (`lib/src/stun/attributes.dart`)
   - Bug: ICE tie-breaker was `BigInt` but encoder used `int`
   - Fix: Added `packUnsigned64BigInt` / `unpackUnsigned64BigInt` functions
   - Root cause: Type mismatch when encoding 64-bit STUN attributes

2. **SCTP CRC32c polynomial** (`lib/src/sctp/packet.dart`)
   - Bug: Used unreflected polynomial `0x1EDC6F41`
   - Fix: Use **reflected** Castagnoli polynomial `0x82F63B78`
   - Test: `CRC32c("123456789") == 0xE3069283`

3. **SCTP checksum endianness** (`lib/src/sctp/packet.dart`)
   - Bug: Wrote checksum as big-endian
   - Fix: Use little-endian per RFC 4960

4. **SCTP State Cookie extraction** (`lib/src/sctp/chunk.dart`, `lib/src/sctp/association.dart`)
   - Bug: Passed raw INIT-ACK parameters to COOKIE-ECHO
   - Fix: Parse TLV parameters to extract State Cookie (type=7)
   - Added: `SctpInitAckChunk.getStateCookie()` method

5. **DTLS Certificate and CertificateVerify support** (`lib/src/dtls/`)
   - Bug: Chrome requires mutual authentication with client certificate
   - Fix: Added Certificate and CertificateVerify message support for DTLS client
   - Added: `certificate_verify.dart`, client handshake certificate signing

6. **DTLS future-epoch record buffering** (`lib/src/dtls/record/record_layer.dart`, `lib/src/dtls/client.dart`)
   - Bug: Encrypted Finished message arrived before ChangeCipherSpec was processed
   - Fix: Buffer future-epoch records and reprocess after CCS

7. **DTLS retransmission handling** (`lib/src/dtls/client_handshake.dart`)
   - Bug: Chrome retransmits ServerHello flight, causing spurious connection failures
   - Fix: Silently ignore retransmitted handshake messages instead of throwing errors

8. **STUN ICE-CONTROLLING/ICE-CONTROLLED attribute accepts int** (`lib/src/stun/attributes.dart`)
   - Bug: Attribute packer only accepted `BigInt`, but callers often passed `int`
   - Fix: Accept both `int` and `BigInt` with automatic conversion

**Feature Parity with werift-webrtc:**
- DataChannel: **100%** ✅
- Audio (RTP transport): **100%** ✅
- Core protocols: **100%** ✅

---

## Post-MVP Roadmap

This roadmap outlines the path from current MVP to full feature parity with the TypeScript werift-webrtc library.

**Total Estimated Effort:** 190-240 developer-days (9-12 months @ 1 FTE)

---

## Phase 1: Critical - Production Readiness (50-60 days)

**Goal:** Enable video conferencing with browsers

### 1.1 Video Codec Depacketization ⭐ HIGH PRIORITY

#### VP8 Depacketization ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests

**Implemented Features:**
- RTP payload header parsing (X, N, S, PID bits)
- Picture ID extraction (7-bit and 15-bit modes)
- Keyframe detection (P bit = 0)
- Partition head detection
- Frame size calculation

**Test Coverage:** 22 tests (100% passing)
- Single packet handling
- Extended payload descriptor parsing
- Picture ID boundary values (7-bit and 15-bit)
- Keyframe/partition head detection
- Buffer handling (empty, truncated)

**Files:** `lib/src/codec/vp8.dart`, `test/codec/vp8_test.dart`

---

#### VP9 Depacketization ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests (January 2025)

**Implemented Features:**
- ✅ Basic structure parsing (I, P, L, F, B, E, V, Z bits)
- ✅ Picture ID support (7-bit and 15-bit)
- ✅ Layer indices (TID, SID, U, D) with correct bit field parsing
- ✅ Flexible mode reference indices (P_DIFF)
- ✅ Scalability structure (SS) parsing
- ✅ Resolution and picture group support
- ✅ Keyframe detection
- ✅ Partition head detection

**Test Coverage:** 25 tests (100% passing)
- All VP9 features fully tested and working
- Fixed bit field parsing for layer indices (TID, U, SID, D)
- Fixed scalability structure parsing (N_S, Y, G fields)
- Fixed picture group parsing (T, U, R fields)
- Corrected test data for proper RFC compliance

**Production Readiness:** ✅ Ready for VP9 video streaming with SVC support
**Files:** `lib/src/codec/vp9.dart`, `test/codec/vp9_test.dart`

---

#### H.264 Depacketization ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests

**Implemented Features:**
- NAL unit type detection (types 1-23, 24, 28)
- FU-A (Fragmentation Unit) handling with reassembly
- STAP-A (Single-Time Aggregation) support
- IDR slice detection (keyframes, type 5)
- Annex B formatting with start codes (0x00000001)
- NRI preservation in fragment reassembly

**Test Coverage:** 22 tests (100% passing)
- Single NAL units (types 1-23)
- IDR slice detection
- STAP-A aggregation (single and multiple NAL units)
- FU-A fragmentation (start, middle, end)
- Fragment reassembly for IDR slices
- Edge cases (empty, malformed, truncated packets)

**Files:** `lib/src/codec/h264.dart`, `test/codec/h264_test.dart`

**Note:** Most widely compatible video codec, critical for Safari/iOS support

---

#### AV1 Depacketization ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests (January 2025)

**Implemented Features:**
- ✅ LEB128 encoding/decoding (variable-length integers)
- ✅ OBU (Open Bitstream Unit) deserialization and serialization
- ✅ OBU type detection (sequence header, frame header, frame, etc.)
- ✅ RTP payload aggregation header parsing (Z/Y/W/N bits)
- ✅ Fragment handling (Z=start with fragment, Y=ends with fragment)
- ✅ Multiple OBU support (W field for OBU count)
- ✅ Keyframe detection (N bit for new coded video sequence)
- ✅ Frame reassembly from fragmented packets

**Test Coverage:** 32 tests (100% passing)
- LEB128: encode/decode single/multi-byte values, round-trip
- Av1Obu: deserialize all OBU types, serialize with/without size field, round-trip
- Av1RtpPayload: single/multiple OBU packets, fragment handling, keyframe detection
- Frame reassembly: single OBU, fragmented OBU, multiple OBUs

**Files:** `lib/src/codec/av1.dart`, `test/codec/av1_test.dart`

**Note:** Most modern codec, excellent compression but less browser support. Ported directly from werift-webrtc TypeScript implementation

---

### 1.2 RTCP Feedback Mechanisms ⭐ HIGH PRIORITY

#### NACK (Negative Acknowledgement) ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests (January 2025)

**Implemented Features:**
- ✅ Generic NACK (RFC 4585, fmt=1)
- ✅ PID+BLP packet format (16-bit PID, 16-bit bitmask)
- ✅ Efficient encoding of lost packet ranges
- ✅ Serialization and deserialization
- ✅ Sequence number wraparound handling
- ✅ NackHandler for automatic packet loss detection
- ✅ Periodic NACK retransmission with retry limits
- ✅ Lost packet pruning to prevent unbounded growth

**Test Coverage:** 41 tests (100% passing)
- GenericNack (16 tests): PID+BLP encoding, serialization, wraparound, edge cases
- NackHandler (25 tests): Loss detection, recovery, periodic retries, timer management

**NackHandler Tests:**
- Packet loss detection (single, multiple, consecutive gaps)
- Late packet recovery and state updates
- Periodic NACK retransmission with retry limits
- Sequence number wraparound handling
- Lost packet pruning for large gaps
- Timer lifecycle (start, stop on recovery)
- Error handling and cleanup
- Edge cases (duplicates, out-of-order, rapid arrival)

**Production Readiness:** ✅ Ready for packet loss recovery
**Files:** `lib/src/rtcp/nack.dart`, `lib/src/rtp/nack_handler.dart`, `test/rtcp/nack_test.dart`, `test/rtp/nack_handler_test.dart`

---

#### PLI/FIR (Picture Loss/Full Intra Request) ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests (January 2025)

**Implemented Features:**
- ✅ PLI (Picture Loss Indication, RFC 4585, fmt=1)
  - ✅ Sender/Media SSRC formatting
  - ✅ Serialization and deserialization
- ✅ FIR (Full Intra Request, RFC 5104, fmt=4)
  - ✅ Multi-entry support (multiple SSRCs per request)
  - ✅ 8-bit sequence number per entry
  - ✅ Serialization and deserialization

**Test Coverage:** 48 tests (100% passing)
- PictureLossIndication: constants, serialization, deserialization, round-trip, equality, toString
- FirEntry: basic properties, equality
- FullIntraRequest: serialization (0/1/multiple entries), deserialization, round-trip, length calculation, equality

**Files:** `lib/src/rtcp/psfb/pli.dart`, `lib/src/rtcp/psfb/fir.dart`, `test/rtcp/pli_fir_test.dart`

**TODO:**
- Rate limiting implementation
- Integration with video receiver

---

### 1.3 RTX (Retransmission) ✅ COMPLETE
**Status:** Fully implemented with comprehensive tests including SDP negotiation (January 2025)

**Implemented Features:**
- ✅ RTX SSRC management (separate from original stream)
- ✅ Packet wrapping (add RTX header with OSN)
- ✅ Packet unwrapping (restore original sequence number)
- ✅ Original sequence number (OSN) preservation (2-byte prepend)
- ✅ RTX sequence number tracking with wraparound
- ✅ CSRC and extension header preservation
- ✅ uint16 comparison helpers for sequence number handling
- ✅ RetransmissionBuffer (128-packet circular buffer for sent packets)
- ✅ NACK-triggered retransmission in RtpSession
- ✅ RTX unwrapping on receiver side via SSRC mapping
- ✅ SDP negotiation: `a=rtpmap:97 rtx/90000` + `a=fmtp:97 apt=96`
- ✅ SSRC-group:FID attribute support in offers/answers
- ✅ RTX codec info parsing from remote SDP
- ✅ RTX SDP generation in createOffer/createAnswer

**Test Coverage:** 85 tests (100% passing)
- RTX wrapping/unwrapping: 11 tests
- RetransmissionBuffer: 20 tests (store, retrieve, wraparound, circular behavior)
- RTX Integration: 14 tests (NACK→retransmission flow, receiver unwrapping, end-to-end)
- RTX SDP: 34 tests (parsing, building, round-trip)
- PeerConnection RTX SDP: 6 tests (offer/answer generation, codec refs)

**Files:**
- `lib/src/rtp/rtx.dart` - RTX wrapping/unwrapping
- `lib/src/rtp/retransmission_buffer.dart` - Packet cache
- `lib/src/rtp/rtp_session.dart` - NACK handling and RTX integration
- `lib/src/sdp/rtx_sdp.dart` - RTX SDP parsing and generation
- `lib/src/peer_connection.dart` - RTX SDP in offer/answer
- `test/rtp/rtx_test.dart`, `test/rtp/retransmission_buffer_test.dart`, `test/rtp/rtx_integration_test.dart`
- `test/sdp/rtx_sdp_test.dart`, `test/peer_connection_test.dart`

---

### 1.4 TURN Support ⭐ CRITICAL FOR NAT ✅ COMPLETE
**Effort:** 8-10 days | **Complexity:** Medium-High | **Status:** Complete with Data Relay (January 2025)

**Completed Implementation:**
- ✅ TURN allocation (RFC 5766)
  - ✅ Allocate request/response with 401 authentication
  - ✅ 5-tuple allocation (client IP/port, server IP/port, protocol)
  - ✅ Lifetime management and refresh
- ✅ TURN channel binding
  - ✅ ChannelBind request/response
  - ✅ Channel number assignment (0x4000-0x7FFF)
  - ✅ Channel data messages (0x40-0x7F prefix)
- ✅ Permission management
  - ✅ CreatePermission request/response
  - ✅ IP address permissions
  - ✅ Permission refresh (5 min lifetime)
- ✅ Send/Data indications
  - ✅ Send indication (client → server)
  - ✅ Data indication (server → client)
  - ✅ XOR-PEER-ADDRESS attribute
- ✅ UDP transport (TCP planned)
- ✅ TURN URL parsing (turn:/turns: schemes)
- ✅ MD5-based MESSAGE-INTEGRITY authentication

**Reference:** `lib/src/turn/turn_client.dart` (529 lines), `werift-webrtc/packages/ice/src/turn/protocol.ts`

**ICE Integration Complete:**
- ✅ ICE candidate gathering with relay type
- ✅ TURN client lifecycle management
- ✅ Relay candidate generation during gatherCandidates()
- ✅ Proper cleanup on connection close/restart

**Data Relay Complete:**
- ✅ Data send via TURN for relay candidates (Send indication + ChannelData)
- ✅ Channel binding for efficient relay (4-byte header vs 36+ bytes)
- ✅ TURN receive stream wired to ICE data delivery
- ✅ Connectivity checks routed through TURN for relay candidates
- ✅ Automatic channel binding on first send (lazy optimization)

**Test Coverage (50 tests - all passing):**
- ✅ ChannelData encoding/decoding (8 tests)
- ✅ TurnAllocation lifecycle and expiry (15 tests)
- ✅ TURN URL parsing (11 tests)
- ✅ TURN Relay integration (16 tests)

**Files:**
- `lib/src/turn/turn_client.dart` - TURN client implementation
- `lib/src/turn/channel_data.dart` - ChannelData encoding
- `lib/src/ice/ice_connection.dart` - ICE/TURN integration
- `test/turn/`, `test/ice/turn_relay_test.dart`

**Remaining Work:**
- TCP transport support
- Integration testing with real TURN servers
- Multiple TURN servers (fallback)

---

### 1.5 Basic getStats() API ⭐ OBSERVABILITY ✅ MVP COMPLETE
**Effort:** 5-6 days | **Complexity:** Medium | **Status:** MVP COMPLETE (January 2025)

**MVP Implementation Complete:**
- ✅ `getStats()` method in RtcPeerConnection
- ✅ `RTCPeerConnectionStats`: connection-level stats
- ✅ `RTCInboundRtpStreamStats`: packets received, bytes, jitter, packet loss
- ✅ `RTCOutboundRtpStreamStats`: packets sent, bytes
- ✅ `RTCStatsReport`: Map-like container for stats
- ✅ Test coverage: 9 tests covering core functionality

**TODO for Full Implementation:**
- Data Channel Stats: `RTCDataChannelStats` (label, state, messages sent/received, bytes)
- Media Source Stats: Track-level metrics
- Codec Stats: payload type, MIME type, clock rate
- Transport Stats: `RTCIceCandidatePairStats`, `RTCIceCandidateStats`, `RTCDtlsTransportStats`
- Track selector filtering (MediaStreamTrack parameter)

**Reference:**
- W3C Spec: https://www.w3.org/TR/webrtc-stats/
- TypeScript: `werift-webrtc/packages/webrtc/src/media/stats.ts`
- Implementation: `lib/src/peer_connection.dart:1135`
- Tests: `test/get_stats_test.dart`

---

**Phase 1 Summary:**
- **Total Effort:** 50-60 days
- **Outcome:** Video calls with Chrome/Firefox, improved reliability
- **Deliverables:** VP8/VP9/H.264 support, RTX/NACK, TURN, basic stats

**Phase 1 Progress (January 2025):**
| Feature | Status | Tests |
|---------|--------|-------|
| VP8 Depacketization | ✅ Complete | 22 tests |
| VP9 Depacketization | ✅ Complete | 25 tests |
| H.264 Depacketization | ✅ Complete | 22 tests |
| AV1 Depacketization | ✅ Complete | 32 tests |
| NACK | ✅ Complete | 41 tests |
| PLI/FIR | ✅ Complete | 48 tests |
| RTX | ✅ Complete | 85 tests |
| TURN | ✅ Complete | 50 tests |
| getStats() | ✅ MVP Complete | 9 tests |

**Phase 1 Complete!** All video codec depacketizers implemented

---

## Phase 2: Important - Common Use Cases (50-60 days)

**Goal:** Enterprise-grade quality and features

### 2.1 RED (Redundancy Encoding)
**Effort:** 4-5 days | **Complexity:** Medium

**Implementation:**
- Primary + redundant packet encoding (RFC 2198)
- Timestamp offset handling
- Block length management
- Duplicate detection and removal
- Configurable redundancy level (1-3 generations)

**Use Case:** Improve audio quality on lossy networks (VoIP)

**Reference:** `werift-webrtc/packages/rtp/src/rtp/red/`

**Tests Required:**
- Encoding with different redundancy levels
- Decoding with packet loss
- Duplicate packet handling
- Bandwidth overhead calculation

---

### 2.2 Transport-Wide CC (TWCC - Bandwidth Estimation) ⭐ HIGH VALUE
**Effort:** 10-12 days | **Complexity:** High

**Implementation:**
- Transport-wide sequence numbers (RTP header extension)
- Receive delta encoding/decoding
- Packet status chunks:
  - Run-length chunks
  - Status vector chunks (1-bit/2-bit symbols)
- Bandwidth estimation algorithm:
  - Delay-based congestion detection
  - Loss-based rate reduction
  - Probe-based rate increase
- Congestion control feedback (RTCP TWCC)

**Reference:** `werift-webrtc/packages/rtp/src/rtcp/rtpfb/twcc.ts`

**Integration:**
- RTP header extension (transport-cc, ID 1)
- RTCP feedback generation (fmt=15)
- Bitrate adaptation in sender
- Encoder target bitrate updates

**Tests Required:**
- Sequence number tracking
- Delta calculation accuracy
- Chunk encoding/decoding (all types)
- Bandwidth adaptation under congestion
- Packet loss handling
- RTT measurement integration

**Impact:** Critical for adaptive streaming quality

---

### 2.3 Simulcast Support ⭐ HIGH VALUE
**Effort:** 12-15 days | **Complexity:** High

**Implementation:**
- RID (Restriction Identifier) support (RFC 8851)
- Multiple encoding layers per track:
  - Low: 320x180 @ 150kbps
  - Medium: 640x360 @ 500kbps
  - High: 1280x720 @ 1.5Mbps
- SDP simulcast attribute parsing: `a=simulcast:send 1;2;3`
- RID attribute parsing: `a=rid:1 send`
- Layer selection/switching
- SSRC-based layer routing
- Transceiver sender enhancement for multiple encodings

**Reference:** Spread across TypeScript transceiver, sender, SDP modules

**Integration:**
- Multiple RTP senders per track
- Bandwidth-based layer selection
- SDP offer/answer with simulcast
- Receiver-side layer switching

**Tests Required:**
- Three-layer simulcast setup
- Layer switching (client-side select)
- SDP negotiation with simulcast
- Browser interop (Chrome simulcast)
- Bandwidth-constrained scenarios

**Impact:** Essential for scalable video conferencing (SFU scenarios)

---

### 2.4 Media Track Management
**Effort:** 6-8 days | **Complexity:** Medium

**Implementation:**
- `addTrack(track, streams)` - Add track to connection
- `removeTrack(sender)` - Remove track from connection
- `replaceTrack(track)` - Replace track without renegotiation
- Track enabled/disabled state
- Multiple tracks per connection (multi-stream)
- Track ID and stream ID management
- Integration with transceiver model

**Reference:** TypeScript PeerConnection track management

**Integration:**
- Triggers renegotiation when needed
- Updates SDP m-lines
- Maintains transceiver state

**Tests Required:**
- Add/remove track during active call
- Track replacement (camera switch)
- Multiple audio/video tracks
- Track enabled/disabled
- Stream association

---

### 2.5 ICE Restart
**Effort:** 4-5 days | **Complexity:** Medium

**Implementation:**
- New ICE credentials generation (ufrag/pwd)
- Connection reestablishment without full renegotiation
- SDP offer with new ICE credentials
- Graceful fallback on restart failure
- Preserve existing media state

**Reference:** TypeScript ICE agent restart logic

**Tests Required:**
- Restart during active call
- Restart after network change
- Multiple consecutive restarts
- Restart failure handling

---

### 2.6 Jitter Buffer
**Effort:** 8-10 days | **Complexity:** Medium-High

**Implementation:**
- Packet reordering by RTP timestamp
- Timestamp-based smoothing
- Adaptive buffer sizing (trade latency vs quality)
- Late packet handling (discard vs insert)
- Gap detection and concealment
- Clock drift compensation
- Configurable min/max delay

**Reference:** `werift-webrtc/packages/rtp/src/extra/processor/jitterBuffer*.ts`

**Integration:**
- Between RTP receiver and codec/renderer
- Works with NACK for retransmission
- Audio and video variants (different characteristics)

**Tests Required:**
- Out-of-order packet handling
- Packet loss gap detection
- Clock drift scenarios
- Latency vs quality tradeoff
- Buffer overflow/underflow
- Timestamp wrap-around

**Impact:** Critical for audio/video quality

---

**Phase 2 Summary:**
- **Total Effort:** 50-60 days
- **Outcome:** Production-grade quality, scalable architecture
- **Deliverables:** TWCC, Simulcast, Track management, Jitter buffer

---

## Phase 3: Nice-to-Have - Advanced Features (40-50 days)

**Goal:** Advanced use cases and edge case support

### 3.1 SVC (Scalable Video Coding)
**Effort:** 10-12 days

- Temporal/spatial layer support (VP9)
- Layer dependency parsing
- Selective forwarding
- TL0PICIDX handling

### 3.2 ICE TCP Candidates
**Effort:** 6-8 days

- TCP active/passive/so types
- TCP connectivity checks
- STUN multiplexing over TCP

### 3.3 mDNS Candidate Obfuscation
**Effort:** 3-4 days

- `.local` hostname generation
- ICE candidate privacy (hide local IPs)

### 3.4 IPv6 Support Improvements
**Effort:** 3-4 days

- IPv6 ICE candidates
- Dual-stack operation
- IPv6 TURN

### 3.5 DTX (Discontinuous Transmission)
**Effort:** 3-4 days

- Silence detection (audio VAD)
- Comfort noise generation
- Bandwidth saving

**Reference:** `werift-webrtc/packages/rtp/src/extra/processor/dtx*.ts`

### 3.6 Lip Sync (Audio/Video Synchronization)
**Effort:** 5-6 days

- NTP timestamp correlation (RTCP SR)
- A/V delay calculation
- Synchronized playback

**Reference:** `werift-webrtc/packages/rtp/src/extra/processor/lipsync*.ts`

### 3.7 Extended getStats() API
**Effort:** 4-5 days

- Remote inbound/outbound RTP stats
- Media source stats
- Certificate stats
- Quality metrics (MOS, jitter detailed)

### 3.8 Perfect Negotiation Pattern
**Effort:** 3-4 days

- Collision resolution
- Rollback support
- Polite/impolite peer roles

**Phase 3 Summary:**
- **Total Effort:** 40-50 days
- **Outcome:** Advanced use cases supported

---

## Phase 4: Future - Experimental (50-70 days)

**Goal:** Cutting-edge features and maximum flexibility

### 4.1 Media Recording (Save to Disk)
**Effort:** 10-15 days

- WebM container writing
- MP4 container writing (H.264)
- Ogg container (Opus)
- Audio + video muxing

**Reference:** `werift-webrtc/packages/rtp/src/extra/container/`

### 4.2 Insertable Streams API
**Effort:** 8-10 days

- Transform streams for RTP
- E2E encryption hooks
- Custom processing pipeline

### 4.3 Advanced Bandwidth Estimation (GCC)
**Effort:** 12-15 days

- Google Congestion Control
- REMB (Receiver Estimated Max Bitrate)
- Encoder bitrate adaptation
- Quality scaling

**Reference:** `werift-webrtc/packages/webrtc/src/media/sender/senderBWE.ts`

### 4.4 FEC (Forward Error Correction)
**Effort:** 15-20 days

- FlexFEC (RFC 8627)
- ULP FEC (RFC 5109)
- Loss recovery without retransmission

### 4.5 Advanced RTCP Features
**Effort:** 6-8 days

- Extended Reports (XR)
- RTCP SDES
- Application-specific RTCP (APP)

**Phase 4 Summary:**
- **Total Effort:** 50-70 days
- **Outcome:** Full feature parity with werift-webrtc

---

## Recommended Implementation Order (by Business Value)

1. **VP8 Depacketization** (3-4 days) - Most common codec
2. **VP9 Depacketization** (5-6 days) - Chrome/Firefox default
3. **RTX + NACK** (6-8 days) - Reliability foundation
4. **Basic getStats()** (5-6 days) - Observability
5. **TURN Support** (8-10 days) - NAT traversal (production requirement)
6. **H.264 Depacketization** (6-7 days) - Safari/iOS compatibility
7. **TWCC** (10-12 days) - Quality/bandwidth management
8. **Simulcast** (12-15 days) - Scalable conferencing
9. **Track Management** (6-8 days) - Flexibility
10. **Jitter Buffer** (8-10 days) - Quality

**First Milestone (Video MVP):** Items 1-6 = ~33-41 days
**Second Milestone (Production Ready):** Items 1-9 = ~70-88 days
**Full Parity:** All phases = ~190-240 days

---

## Testing Strategy

### Unit Tests (Per Feature)
- Codec depacketizers: 15-20 tests each
- RTX wrap/unwrap: 10 tests
- RTCP feedback: 10-15 tests per type
- TURN protocol: 20-25 tests
- Stats generation: 15-20 tests
- **Target Coverage:** >90%

### Integration Tests
- End-to-end video calls with each codec
- Packet loss scenarios (RTX/NACK)
- TURN relay connectivity
- Simulcast layer switching
- Track add/remove/replace

### Browser Interop Tests ⭐ CRITICAL
**Chrome ↔ webrtc_dart:**
- DataChannel + Audio + Video
- Simulcast
- TURN relay
- Track management

**Firefox ↔ webrtc_dart:**
- Same test suite as Chrome

**Safari ↔ webrtc_dart:**
- H.264 video (Safari requirement)
- Basic feature set

### Performance Tests
- Throughput: 100+ Mbps video
- Latency: <50ms glass-to-glass target
- Packet loss: Up to 10% with RTX
- CPU profiling: Codec operations
- Memory: Long-duration call leak detection

---

## External Dependencies

### Libraries Needed
- **LEB128**: For AV1 (check pub.dev or port)
- **Video decoders** (optional, for end-to-end testing):
  - VP8: libvpx FFI bindings
  - H.264: openh264 or platform decoders
  - AV1: dav1d FFI bindings

### Development Tools
- Wireshark for RTP/RTCP inspection
- Chrome/Firefox for interop testing
- RTP dump/replay tools
- Network simulation (tc, netem)

---

## Quality Requirements

### Code Coverage Targets
- Unit tests: >90%
- Integration tests: All critical paths
- E2E tests: All codecs × major browsers

### Documentation
- API documentation (dartdoc)
- Architecture documentation (update existing)
- Protocol implementation notes
- Examples for each major feature
- Migration guide from werift-webrtc

### Performance Baselines
- Codec processing time
- Memory per connection
- Throughput capacity
- Latency distribution
- Track in CI, alert on regression

---

## Risk Mitigation

### High Risk Items
- **AV1 Codec:** Complex, may have edge cases → Start with VP8
- **FEC:** Complex mathematics → Phase 4 (defer)
- **Simulcast:** Coordination between layers → Extensive testing
- **BWE:** Network-dependent tuning → Real-world testing

### Mitigation Strategies
- Start with simpler codecs (VP8) before complex (AV1)
- Extensive fuzzing for all parser code
- Early browser interop testing
- Profile and optimize critical paths
- Consider native extensions for CPU-intensive ops

---

## Timeline Estimates

### Minimum Video Support (Video MVP)
**Goal:** Video calls with Chrome/Firefox
**Includes:** VP8, VP9, RTX/NACK, basic stats
**Effort:** 30-40 days
**Timeline:** 6-8 weeks @ 1 FTE

### Production Ready
**Goal:** Enterprise-grade stack
**Includes:** Phase 1 + TWCC + Track management
**Effort:** 75-90 days
**Timeline:** 15-18 weeks @ 1 FTE

### Full Feature Parity
**Goal:** Match all werift-webrtc features
**Includes:** All phases
**Effort:** 190-240 days
**Timeline:**
- 9-12 months @ 1 FTE
- 4-6 months @ 2-3 FTE (parallelizable work)

---

## Success Metrics

**Video MVP Complete When:**
- ✅ VP8/VP9 video calls work with Chrome
- ✅ H.264 video calls work with Safari
- ✅ RTX recovers from packet loss
- ✅ TURN enables calls behind NAT
- ✅ getStats() provides observability

**Production Ready When:**
- ✅ All Video MVP criteria
- ✅ TWCC adapts to bandwidth changes
- ✅ Simulcast enables scalable conferencing
- ✅ Track management allows dynamic participants
- ✅ Browser interop tests pass (Chrome, Firefox, Safari)

**Full Parity When:**
- ✅ All TypeScript features ported
- ✅ Test coverage >90%
- ✅ Performance matches TypeScript
- ✅ Documentation complete
- ✅ Example apps for major use cases

---

## Next Steps (Immediate)

### ✅ COMPLETED (Phase 1 - ALL COMPLETE)
1. ~~**VP8 depacketizer**~~ ✅ Complete (22 tests)
2. ~~**VP9 depacketizer**~~ ✅ Complete (25 tests)
3. ~~**H.264 depacketizer**~~ ✅ Complete (22 tests)
4. ~~**AV1 depacketizer**~~ ✅ Complete (32 tests)
5. ~~**NACK**~~ ✅ Complete (41 tests)
6. ~~**PLI/FIR**~~ ✅ Complete (48 tests)
7. ~~**RTX + SDP Negotiation**~~ ✅ Complete (85 tests)
8. ~~**TURN (Core + Data Relay)**~~ ✅ Complete (50 tests)
9. ~~**getStats() MVP**~~ ✅ Complete (9 tests)

**Phase 1 Complete!** Total: 334 tests for Phase 1 features

### 🔜 NEXT PRIORITIES (Phase 2)

1. **Browser Interop Testing** (immediate)
   - Chrome ↔ webrtc_dart test harness
   - Firefox ↔ webrtc_dart
   - Safari ↔ webrtc_dart (H.264)

2. **TWCC (Transport-Wide Congestion Control)** (10-12 days)
   - Transport-wide sequence numbers
   - Bandwidth estimation
   - Adaptive bitrate

3. **Simulcast Support** (12-15 days)
   - RID support
   - Multiple encoding layers
   - Layer selection/switching

4. **Jitter Buffer** (8-10 days)
   - Packet reordering
   - Adaptive buffer sizing
   - Gap detection

---

## ✅ Chrome Browser Interop WORKING (November 2025)

### Completed Interop Testing

**Dart ↔ Chrome Browser DataChannel:**
- ✅ Full DTLS 1.2 handshake with mutual certificate authentication
- ✅ SCTP association establishment
- ✅ Bidirectional DataChannel messaging
- ✅ Connection state properly transitions to `connected`
- ✅ No spurious error states during operation

**Test Setup:**
```bash
dart run interop/browser/server.dart
# Open http://localhost:8080 in Chrome
# Click "Connect to Dart Peer" button
```

**Verified Working:**
- Chrome → Dart: Text messages delivered correctly
- Dart → Chrome: Echo messages delivered correctly
- Connection lifecycle: new → connecting → connected → closed

---

**Document Version:** 1.6
**Last Updated:** November 2025
**Status:** Phase 1 COMPLETE (891 tests passing), Chrome browser interop WORKING
