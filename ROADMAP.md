# webrtc_dart Roadmap - Path to Full Feature Parity

## Current Status (January 2025)

### ✅ MVP COMPLETE - DataChannel + Audio Infrastructure

**Implemented Components:**
- Core Protocols: STUN, ICE, DTLS, SRTP/SRTCP, SCTP, RTP/RTCP
- DataChannel: Full DCEP implementation
- Audio: RTP transport layer complete (Opus payload format)
- PeerConnection: W3C-compatible API
- Test Coverage: 546+ tests (99.6% pass rate)
- Interop: Dart ↔ TypeScript signaling infrastructure

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

#### VP8 Depacketization
**Effort:** 3-4 days | **Complexity:** Medium

**Implementation:**
- RTP payload header parsing (X, N, S, PID bits)
- Picture ID extraction (7-bit or 15-bit)
- Keyframe detection (P bit = 0)
- Partition head detection
- Frame assembly from fragments

**Reference:** `werift-webrtc/packages/rtp/src/codec/vp8.ts`

**Tests Required:**
- Single packet keyframes
- Fragmented frames across packets
- Picture ID rollover (15-bit)
- Partition boundary handling

---

#### VP9 Depacketization
**Effort:** 5-6 days | **Complexity:** Medium-High

**Implementation:**
- Flexible mode (F bit) support
- Layer indices (TID, SID for temporal/spatial scalability)
- Scalability structure (SS) parsing
- Picture dependencies (P_DIFF)
- Keyframe detection with SVC awareness
- Inter-picture predicted frames

**Reference:** `werift-webrtc/packages/rtp/src/codec/vp9.ts`

**Tests Required:**
- Basic single-layer streams
- SVC temporal layers
- Temporal layer switching
- Scalability structure changes
- Picture dependency chains

---

#### H.264 Depacketization
**Effort:** 6-7 days | **Complexity:** Medium-High

**Implementation:**
- NAL unit type detection
- FU-A (Fragmentation Unit) handling
- STAP-A (Single-Time Aggregation) support
- IDR slice detection (keyframes)
- Annex B formatting with start codes (0x00000001)
- Packetization modes 0/1

**Reference:** `werift-webrtc/packages/rtp/src/codec/h264.ts`

**Tests Required:**
- Single NAL units
- Fragmentation units (FU-A)
- Aggregation packets (STAP-A)
- Parameter sets (SPS/PPS)
- Annex B conversion

**Note:** Most widely compatible video codec, critical for Safari/iOS support

---

#### AV1 Depacketization
**Effort:** 7-8 days | **Complexity:** High

**Implementation:**
- OBU (Open Bitstream Unit) aggregation
- Fragment handling (Z/Y continuation bits)
- LEB128 size decoding
- OBU type detection (sequence header, frame header, frame, etc.)
- Dependency descriptor parsing

**Reference:** `werift-webrtc/packages/rtp/src/codec/av1.ts`

**Dependencies:**
- May need LEB128 library (check pub.dev or port from TypeScript)

**Tests Required:**
- OBU aggregation in single packet
- Fragment continuation across packets
- Coded video sequence starts
- Temporal/spatial layer handling

**Note:** Most modern codec, excellent compression but less browser support

---

### 1.2 RTCP Feedback Mechanisms ⭐ HIGH PRIORITY

#### NACK (Negative Acknowledgement)
**Effort:** 2-3 days | **Complexity:** Low-Medium

**Implementation:**
- Generic NACK (RFC 4585, fmt=1)
- Packet loss detection via sequence gap
- Bitmask of lost packets (BLP - Bitmask of following Lost Packets)
- NACK generation and parsing
- Integration with receiver packet tracking

**Reference:** `werift-webrtc/packages/rtp/src/rtcp/rtpfb/nack.ts`

**Tests Required:**
- Single packet loss
- Multiple packet loss (BLP)
- NACK parsing/generation
- Duplicate NACK handling

---

#### PLI/FIR (Picture Loss/Full Intra Request)
**Effort:** 2 days | **Complexity:** Low

**Implementation:**
- PLI (Payload-Specific Feedback, fmt=1) for requesting keyframes
- FIR (Full Intra Request, fmt=4) for forcing keyframe
- Proper RTCP packet formatting
- Rate limiting to avoid RTCP storms

**Reference:** `werift-webrtc/packages/rtp/src/rtcp/psfb/`

**Tests Required:**
- PLI generation on packet loss
- FIR request handling
- Rate limiting
- RTCP compound packet formatting

---

### 1.3 RTX (Retransmission) ⭐ HIGH PRIORITY
**Effort:** 4-5 days | **Complexity:** Medium

**Implementation:**
- RTX SSRC management (separate from original stream)
- Packet wrapping (add RTX header)
- Packet unwrapping (restore original sequence)
- Original sequence number (OSN) preservation
- RTX payload type mapping in SDP
- Sender: Packet cache (recent N packets)
- Receiver: RTX unwrapping and insertion into sequence

**Reference:** `werift-webrtc/packages/rtp/src/rtp/rtx.ts`

**Integration:**
- Works with NACK (NACK triggers RTX)
- SDP negotiation: `a=rtpmap:96 rtx/90000` + `a=fmtp:96 apt=95`

**Tests Required:**
- RTX wrapping/unwrapping
- NACK-triggered retransmission
- RTX SSRC negotiation
- Cache size limits
- Duplicate handling

---

### 1.4 TURN Support ⭐ CRITICAL FOR NAT
**Effort:** 8-10 days | **Complexity:** Medium-High

**Implementation:**
- TURN allocation (RFC 5766)
  - Allocate request/response
  - 5-tuple allocation (client IP/port, server IP/port, protocol)
  - Lifetime management and refresh
- TURN channel binding
  - ChannelBind request/response
  - Channel number assignment (0x4000-0x7FFF)
  - Channel data messages (0x40-0x7F prefix)
- Permission management
  - CreatePermission request/response
  - IP address permissions
  - Permission refresh (5 min lifetime)
- Send/Data indications
  - Send indication (client → server)
  - Data indication (server → client)
  - XOR-PEER-ADDRESS attribute
- TCP/UDP transport
- STUN-over-TURN for ICE connectivity checks

**Reference:** `werift-webrtc/packages/ice/src/turn/protocol.ts`

**Integration:**
- ICE candidate gathering with relay type
- TURN server configuration in RtcConfiguration
- Credential management

**Tests Required:**
- Allocation lifecycle (allocate → refresh → delete)
- Channel data vs Send indication modes
- Permission expiry and refresh
- Reconnection handling
- TURN over TCP
- Multiple TURN servers (fallback)

---

### 1.5 Basic getStats() API ⭐ OBSERVABILITY
**Effort:** 5-6 days | **Complexity:** Medium

**Implementation (W3C WebRTC Stats):**

**Inbound/Outbound RTP Stats:**
- `RTCInboundRtpStreamStats`: packets received, bytes, packets lost, jitter
- `RTCOutboundRtpStreamStats`: packets sent, bytes, retransmissions
- Codec stats: payload type, MIME type, clock rate

**Transport Stats:**
- `RTCIceCandidatePairStats`: bytes sent/received, RTT, current state
- `RTCIceCandidateStats`: candidate type, IP, port, protocol
- `RTCDtlsTransportStats`: selected cipher suite, certificate

**Data Channel Stats:**
- `RTCDataChannelStats`: label, state, messages sent/received, bytes

**Reference:**
- W3C Spec: https://www.w3.org/TR/webrtc-stats/
- TypeScript: `werift-webrtc/packages/webrtc/src/media/stats.ts`

**Tests Required:**
- Stats collection during active call
- Stats type coverage (all required types)
- Stats ID consistency
- Stats timestamp accuracy
- Stats delta calculation

---

**Phase 1 Summary:**
- **Total Effort:** 50-60 days
- **Outcome:** Video calls with Chrome/Firefox, improved reliability
- **Deliverables:** VP8/VP9/H.264 support, RTX/NACK, TURN, basic stats

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

1. **Implement VP8 depacketizer** (Week 1-2)
   - Start with simplest video codec
   - Establish testing patterns
   - Validate approach

2. **Set up browser interop testing** (Week 2-3)
   - Chrome ↔ webrtc_dart test harness
   - Automated testing infrastructure
   - Packet capture validation

3. **Implement VP9 depacketizer** (Week 3-4)
   - Build on VP8 patterns
   - Add SVC support
   - Validate with Chrome

4. **RTX + NACK** (Week 5-6)
   - Reliability layer
   - Critical for production

With these four items complete, webrtc_dart would support basic video conferencing with modern browsers.

---

**Document Version:** 1.0
**Last Updated:** January 2025
**Status:** Current MVP complete, planning post-MVP features
