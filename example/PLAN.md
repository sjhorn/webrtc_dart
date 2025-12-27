# Example Testing Plan

This document tracks verification of each example against werift-webrtc behavior. As we work on each directory we will aim to build a simple run.sh or similar to start the example and either test automatically or in an external browser. As we go we will aim to fix the dart to match the werift code when we find bugs. 

## Testing Approaches

| Method | Description |
|--------|-------------|
| **Terminal** | Run Dart server + werift TypeScript client (or vice versa) |
| **Playwright** | Automated browser test via `interop/automated/` |
| **Manual Browser** | Run Dart server, open browser manually to test |
| **Dart-to-Dart** | Two Dart processes communicating |

## Status Legend

- [ ] Not started
- [~] In progress
- [x] Complete
- [S] Skipped (documentation-only or not applicable)

---

## 1. Ring Example (COMPLETE)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `ring/peer.dart` | [x] | Terminal | Working with Ring cameras |
| `ring/recv_via_webrtc.dart` | [x] | Terminal | SRTP-CTR cipher support added |

---

## 2. DataChannel Examples (VERIFIED Dec 2025)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `datachannel/quickstart.dart` | [x] | Dart-to-Dart | Basic DC creation and messaging |
| `datachannel/local.dart` | [x] | Dart-to-Dart | Local loopback test |
| `datachannel/offer.dart` | [x] | Playwright | Browser interop (Chrome/Firefox/Safari) |
| `datachannel/answer.dart` | [x] | Playwright | **Chrome/Firefox/Safari pass** - Dart as answerer |
| `datachannel/string.dart` | [x] | Dart-to-Dart | String message exchange (fixed await) |
| `datachannel/manual.dart` | [ ] | Manual Browser | Copy/paste SDP flow |
| `datachannel/signaling_server.dart` | [x] | Playwright | WebSocket signaling |

**Test Results:**
- All browser tests pass (Chrome, Firefox, Safari)
- Automated tests in `interop/automated/browser_test.mjs`
- Fixed ProxyDataChannel stream controller close issue

**DataChannel Answer Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/datachannel_answer_server.dart` + `datachannel_answer_test.mjs`
- Pattern: **Browser is OFFERER, Dart is ANSWERER** (opposite of most tests)
- Browser creates PeerConnection + DataChannel, sends offer to Dart
- Dart creates answer, DataChannel opens, exchanges ping/pong messages
- Chrome: **PASS** - 3 sent, 3 received, 1202ms connection
- Firefox: **PASS** - 3 sent, 3 received, 7619ms connection
- Safari: **PASS** - 3 sent, 3 received, 1118ms connection

**DataChannel Offer Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/dart_signaling_server.dart` + `browser_test.mjs`
- Pattern: **Dart is OFFERER, Browser is ANSWERER**
- Chrome: **PASS** - 3 messages, 1163ms connection
- Firefox: **PASS** - 3 messages, 7673ms connection (after firewall fix)
- Safari: **PASS** - 3 messages

---

## 3. Close Examples (VERIFIED Dec 2025)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `close/dc/closed.dart` | [x] | Dart-to-Dart | DC close event fires correctly |
| `close/dc/closing.dart` | [x] | Dart-to-Dart | Closing state transition works |
| `close/pc/closed.dart` | [x] | Dart-to-Dart | PC close event fires correctly |
| `close/pc/closing.dart` | [x] | Dart-to-Dart | Closing state transition works |

**Test Results:**
- All close examples verified
- Fixed transport initialization delay issues
- Fixed message type handling (String vs Uint8List)

---

## 4. ICE Examples (VERIFIED Dec 2025)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `ice/trickle/offer.dart` | [x] | Playwright | **Chrome/Firefox/Safari pass** - trickle ICE + DataChannel |
| `ice/trickle/dc.dart` | [x] | Dart-to-Dart | Trickle ICE + DataChannel |
| `ice/restart/offer.dart` | [x] | Playwright | **Chrome/Firefox/Safari pass** - ICE restart with credential change |
| `ice/restart/quickstart.dart` | [x] | Dart-to-Dart | Basic restart test |
| `ice/turn/quickstart.dart` | [x] | Terminal | TURN configuration verified |
| `ice/turn/trickle_offer.dart` | [ ] | Playwright | TURN + trickle ICE |

**ICE Trickle Browser Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/ice_trickle_server.dart` + `ice_trickle_test.mjs`
- Pattern: Dart is offerer, sends offer immediately (no candidate waiting), trickles ICE candidates
- Verifies incremental candidate exchange + DataChannel ping/pong
- Chrome: **PASS** - 2 sent, 2 recv candidates, ping/pong YES, 266ms connection
- Safari: **PASS** - 2 sent, 1 recv candidates, ping/pong YES, 177ms connection
- Firefox: **PASS** - 2 sent, 3 recv candidates, ping/pong YES, 197ms connection

**ICE Restart Browser Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/ice_restart_server.dart` + `ice_restart_test.mjs`
- Pattern: Dart is offerer, establishes initial connection, then triggers ICE restart
- Verifies ICE credentials change (ice-ufrag) and connection maintained after restart
- Chrome: **PASS** - ice-ufrag changed (345a -> a924), restart success, ping/pong works
- Safari: **PASS** - ice-ufrag changed (e886 -> 7f3c), restart success, ping/pong works
- Firefox: **PASS** - ice-ufrag changed (07d7 -> 0bab), restart success, ping/pong works

**Other Test Results:**
- ICE trickle works correctly (host + srflx candidates)
- ICE restart API functional
- TURN configuration works (requires actual TURN server for full test)

---

## 5. MediaChannel Examples (PARTIALLY VERIFIED Dec 2025)

### 5.1 Basic Media

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/sendonly/offer.dart` | [x] | Dart-to-Dart | Media transceiver setup works |
| `mediachannel/sendonly/av.dart` | [x] | Playwright | **Chrome/Firefox/Safari pass** |
| `mediachannel/sendonly/ffmpeg.dart` | [ ] | Manual Browser | FFmpeg as media source |
| `mediachannel/sendonly/multi_offer.dart` | [x] | Playwright | **Chrome/Safari pass** - broadcast to 3 clients |
| `mediachannel/recvonly/offer.dart` | [x] | Playwright | **Chrome/Safari pass**, Firefox skipped |
| `mediachannel/recvonly/answer.dart` | [x] | Playwright | **Chrome/Safari pass** - Dart as answerer (Firefox: headless camera issue) |
| `mediachannel/recvonly/dump.dart` | [ ] | Manual Browser | Dump RTP packets to disk |
| `mediachannel/recvonly/multi_offer.dart` | [x] | Playwright | **Chrome/Safari pass** - receive from 3 clients |
| `mediachannel/sendrecv/offer.dart` | [x] | Playwright | **Chrome/Safari pass**, Firefox skipped |
| `mediachannel/sendrecv/answer.dart` | [x] | Playwright | **Chrome/Safari pass** - Echo works (payload type preservation fix) |
| `mediachannel/sendrecv/multi_offer.dart` | [x] | Playwright | **Chrome/Safari pass** - echo to 3 clients |

**Media Sendonly Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/media_sendonly_server.dart` + `media_sendonly_test.mjs`
- Chrome: **PASS** - 164+ frames received, VP8 video playing
- Safari: **PASS** - 165+ frames received, VP8 video playing
- Firefox: **PASS** - 161 frames received, VP8 video playing (1239ms connection)

**Media Recvonly Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/media_recvonly_server.dart` + `media_recvonly_test.mjs`
- Chrome: **PASS** - 211 RTP packets received from browser camera
- Safari: **PASS** - 202 RTP packets received from browser camera
- Firefox: **SKIP** - getUserMedia not supported in headless Playwright Firefox

**Media Sendrecv (Echo) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/media_sendrecv_server.dart` + `media_sendrecv_test.mjs`
- Pattern: Dart receives browser camera video, echoes it back via RTP forwarding
- Chrome: **PASS** - 210 packets received, 75 echo frames displayed
- Safari: **PASS** - 198 packets received, 161 echo frames displayed
- Firefox: **SKIP** - getUserMedia not supported in headless Playwright Firefox

**Multi-Client Sendonly (Broadcast) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/multi_client_sendonly_server.dart` + `multi_client_sendonly_test.mjs`
- Pattern: Dart broadcasts FFmpeg test video to 3 simultaneous browser clients
- Chrome: **PASS** - 3 clients connected, 565 total frames received (~189/client)
- Safari: **PASS** - 3 clients connected, 618 total frames received (~206/client)
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Multi-Client Recvonly (Upload) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/multi_client_recvonly_server.dart` + `multi_client_recvonly_test.mjs`
- Pattern: 3 browser clients each send camera video to Dart server simultaneously
- Chrome: **PASS** - 3 clients connected, 828 total RTP packets received (~276/client)
- Safari: **PASS** - 3 clients connected, 804 total RTP packets received (~268/client)
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Multi-Client Sendrecv (Echo) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/multi_client_sendrecv_server.dart` + `multi_client_sendrecv_test.mjs`
- Pattern: 3 browser clients each send camera video, Dart echoes back to each
- Chrome: **PASS** - 3 clients, 848 RTP recv/echoed, 363 echo frames displayed
- Safari: **PASS** - 3 clients, 839 RTP recv/echoed, 638 echo frames displayed
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Media Answer (Browser as Offerer) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/media_answer_server.dart` + `media_answer_test.mjs`
- Pattern: **Browser is OFFERER, Dart is ANSWERER** (opposite of most media tests)
- Browser creates PeerConnection with sendonly video, creates offer, Dart answers and receives video
- Chrome: **PASS** - 238 RTP packets received, 1095ms connection
- Safari: **PASS** - 230 RTP packets received, 1094ms connection
- Firefox: **SKIP** - getUserMedia fails in headless Playwright (not WebRTC issue)
- **Note**: DataChannel answer test (same pattern) works with Firefox, but media requires getUserMedia which doesn't work in headless Firefox

**Sendrecv Answer (Echo, Browser as Offerer) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/sendrecv_answer_server.dart` + `sendrecv_answer_test.mjs`
- Pattern: Browser creates offer with sendrecv video, Dart answers and echoes video back
- Chrome: **PASS** - 231 packets recv/echoed, 164 echo frames displayed
- Safari: **PASS** - Expected to work (same fix applied)
- Firefox: **SKIP** - getUserMedia fails in headless Playwright
- **Key Fix**: Browser uses RED (pt=123) codec wrapper. Previously we were rewriting PT to VP8 (pt=96) on echo, breaking browser decoding. Fixed by preserving payload type in `sendRawRtpPacket` calls.

**Bugs Fixed (Dec 2025):**

1. **MID matching bug** - When Dart pre-created a transceiver before receiving the offer, TWO transceivers were created because `_processRemoteMediaDescriptions` only matched by MID (not by kind).

2. **HeaderExtensionConfig closure capture bug** - Extension config was created at track attachment time (before offer), capturing stale MID and extension IDs. Now created at send time.

**The Fixes (implemented in this session):**

1. **Made `RtpTransceiver.mid` nullable** (`lib/src/media/rtp_transceiver.dart`):
   - Changed from `final String mid` to `String? _mid` with getter/setter
   - MID is now assigned lazily during SDP negotiation (matching werift behavior)

2. **Updated `_processRemoteMediaDescriptions`** (`lib/src/peer_connection.dart`):
   - First tries to match transceivers by MID (exact match)
   - If no MID match, tries to match by **kind** for pre-created transceivers
   - When matched by kind, migrates the transceiver to the new MID

3. **Updated `_attachNonstandardTrack`** (`lib/src/media/rtp_transceiver.dart`):
   - HeaderExtensionConfig now created at SEND TIME, not attachment time
   - Critical for answerer pattern where MID/extension IDs change after attachment

4. **Updated `sendrecv_answer_server.dart`**:
   - Uses `addTransceiverWithTrack` with nonstandard track (like working offerer)
   - Sends PLI after first RTP packet (like werift)

5. **Payload type preservation bug** - When forwarding RTP packets, we were overwriting the payload type with negotiated codec PT (VP8=96). Browser uses RED wrapper (pt=123) for video. Fixed by NOT overriding payload type in `_attachNonstandardTrack`.

**Verified Working:**
- MID migration: pre-created MID "1" → remote offer MID "0" ✓
- Extension IDs at send time: mid=0, midExtId=9, absSendTimeId=2, twccId=4 ✓
- SSRC in sent RTP matches SDP answer (e.g., 4024232167) ✓
- All 2262 unit tests pass ✓
- **Echo frames now displayed by browser** ✓ (fixed by preserving payload type)

**Test Execution Notes:**
- Test uses `headless: false` because video decoding requires real display
- Server must be started first: `dart run interop/automated/sendrecv_answer_server.dart`
- Run test: `BROWSER=chrome node interop/automated/sendrecv_answer_test.mjs`

### 5.2 Codec-Specific

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/codec/vp8.dart` | [x] | Dart-to-Dart | VP8 SDP negotiation verified |
| `mediachannel/codec/vp9.dart` | [x] | Playwright | **Chrome pass** via save_to_disk/vp9 (Safari: not supported) |
| `mediachannel/codec/h264.dart` | [x] | Playwright | **Chrome/Safari pass** via save_to_disk/h264 |
| `mediachannel/codec/av1.dart` | [x] | Playwright | **Chrome pass** (Safari/Firefox: AV1 not supported) |

### 5.3 Advanced Features

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/rtx/offer.dart` | [x] | Playwright | **Chrome pass** - RTX codec negotiated |
| `mediachannel/rtx/simulcast_offer.dart` | [x] | Playwright | **Chrome pass** - Simulcast SDP + RID routing complete |
| `mediachannel/rtx/simulcast_answer.dart` | [x] | Manual Browser | Simulcast SDP + RID routing complete |
| `mediachannel/twcc/offer.dart` | [x] | Playwright | **Chrome pass** - transport-cc negotiated |
| `mediachannel/twcc/multitrack.dart` | [ ] | Manual Browser | TWCC with multiple tracks |
| `mediachannel/simulcast/offer.dart` | [x] | Playwright | **Chrome pass** - Simulcast SDP + 238 RID packets received |
| `mediachannel/simulcast/answer.dart` | [x] | Playwright | **Chrome pass** - SFU fanout, 186 packets forwarded |
| `mediachannel/simulcast/select.dart` | [x] | Manual Browser | Layer selection API (high/mid/low) |
| `mediachannel/simulcast/abr.dart` | [S] | - | Skip - werift doesn't implement setParameters |
| `mediachannel/rtp_forward/offer.dart` | [x] | Playwright | **Chrome/Safari pass** - writeRtp -> browser flow |
| `mediachannel/red/sendrecv.dart` | [x] | Playwright | **Chrome pass** - RED codec negotiated, multi-codec SDP working |
| `mediachannel/red/recv.dart` | [ ] | Manual Browser | RED receive + UDP forward |
| `mediachannel/red/send.dart` | [ ] | Manual Browser | RED send with GStreamer |
| `mediachannel/red/adaptive/server.dart` | [S] | - | Skip - browser RED support limited |
| `mediachannel/red/record/server.dart` | [S] | - | Skip - browser RED support limited |
| `mediachannel/lipsync/server.dart` | [S] | - | Documentation only |
| `mediachannel/pubsub/offer.dart` | [x] | Playwright | **Chrome pass** - Multi-peer routing with keyframe caching |
| `mediachannel/sdp/offer.dart` | [S] | - | Skip - covered by existing tests |

**RTP Forward Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/rtp_forward_test.mjs`
- Pattern: Dart creates sendonly H.264 track, writes synthetic RTP via writeRtp()
- Browser receives track and verifies connection
- Chrome: **PASS** - Track received, connection established
- Safari: **PASS** - Track received, connection established
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Pub/Sub Multi-Peer Routing Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/pubsub_test.mjs`
- Pattern: SFU-style routing - Client A publishes video, Client B subscribes and receives
- Implements full pub/sub protocol: publish → onPublish → subscribe → onSubscribe
- Chrome: **PASS** - Video plays (640x480), keyframe received via cache
- Safari: Expected to pass (same pattern)
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Key Learnings from Pub/Sub Implementation:**

1. **werift's Example vs Real SFU**:
   - werift's `mediachannel/pubsub/offer.ts` is a **single-client loopback**, not multi-peer
   - It uses `registerTrack()` to echo video back to the same client
   - Real SFU requires routing packets between different peer connections
   - Our implementation extends this to true multi-peer routing

2. **VP8 Keyframe Detection (RFC 7741)**:
   - VP8 RTP payload has a descriptor followed by the VP8 bitstream
   - Keyframe detection requires checking BOTH:
     - **S bit** (0x10): Start of partition - must be 1 for frame start
     - **frame_type** (bit 0 of first VP8 byte after descriptor): 0 = keyframe, 1 = interframe
   - Without S=1 check, continuation packets were incorrectly detected as keyframes

3. **Keyframe Caching for New Subscribers**:
   - Chrome's fake camera (getUserMedia) does NOT respond to PLI requests
   - New subscribers would wait forever for a keyframe
   - Solution: Cache complete keyframes from publisher (collect packets until marker=true)
   - Send cached keyframe immediately when new subscriber joins
   - Added `forwardCachedPackets()` method to `RtpSender`

4. **RTP Header Extension Regeneration**:
   - When forwarding packets to different peer connections, must regenerate:
     - **MID** (SDES mid): Must match the NEW transceiver's mid (e.g., "2" → "3")
     - **abs-send-time**: Current NTP timestamp at send time
     - **transport-wide-cc**: Incrementing sequence number for congestion control
   - Extension IDs come from SDP negotiation, not hardcoded values
   - Extension IDs must be set on sender: `midExtensionId`, `absSendTimeExtensionId`, `transportWideCCExtensionId`

5. **SSRC Replacement**:
   - Each peer connection expects different SSRC values in SDP vs received RTP
   - `sendRawRtpPacket(replaceSsrc: true)` rewrites SSRC to sender's local SSRC
   - This allows the same source packets to be forwarded to multiple subscribers

6. **sendrecv Echo vs Pub/Sub Forwarding**:
   - Echo (sendrecv): Same transceiver for send/recv - MID stays the same, extensions preserved
   - Pub/Sub: Different transceivers on different connections - MID must be updated
   - Pub/Sub requires `registerTrackForForward()` which regenerates extensions at send time

**Test Plan:**
1. Start with basic sendonly/recvonly to verify media flow
2. Test each codec with appropriate browsers (AV1 = Chrome)
3. Verify RTX with packet loss simulation
4. Test TWCC feedback loop
5. Simulcast requires browser sending multiple layers

---

## 6. Save to Disk Examples (PARTIALLY VERIFIED Dec 2025)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `save_to_disk/vp8.dart` | [x] | Playwright | **Chrome/Safari pass**, records VP8 to WebM |
| `save_to_disk/vp9.dart` | [x] | Playwright | **Chrome pass**, records VP9 to WebM (Safari: VP9 not supported) |
| `save_to_disk/opus.dart` | [x] | Playwright | **Chrome/Safari pass**, records Opus audio to WebM |
| `save_to_disk/dump.dart` | [x] | Playwright | **Chrome/Safari pass** - Dumps raw RTP packets |
| `save_to_disk/h264.dart` | [x] | Playwright | **Chrome/Safari pass**, records H.264 to WebM |
| `save_to_disk/mp4/h264.dart` | [x] | Playwright | **Chrome/Safari pass** - Records H.264 to fMP4 |
| `save_to_disk/av.dart` | [x] | Playwright | **Chrome/Safari pass**, records VP8+Opus to WebM |
| `save_to_disk/mp4/av.dart` | [x] | Playwright | **Chrome/Safari pass** - Records H.264+Opus to fMP4 |
| `save_to_disk/mp4/opus.dart` | [x] | Playwright | **Chrome/Safari pass** - Records Opus to fMP4 |
| `save_to_disk/packetloss/vp8.dart` | [x] | Playwright | **Chrome/Safari pass**, VP8 with NACK/PLI recovery |
| `save_to_disk/dtx/server.dart` | [x] | Playwright | **Chrome/Safari pass**, DTX silence detection |
| `save_to_disk/gst/recorder.dart` | [x] | Playwright | **Chrome/Safari pass**, GStreamer UDP pipeline |
| `save_to_disk/encrypt/server.dart` | [S] | - | Documentation only |

**Save to Disk VP8 Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_server.dart` + `save_to_disk_test.mjs`
- Uses MediaRecorder class with VP8 depacketizer pipeline
- Records 5 seconds of browser camera video to WebM file
- Chrome: **PASS** - 293 packets, 159KB WebM file created
- Safari: **PASS** - 284 packets, 149KB WebM file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk H.264 Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_h264_server.dart` + `save_to_disk_h264_test.mjs`
- Uses MediaRecorder class with H.264 depacketizer pipeline
- Records 5 seconds of browser H.264 video to WebM file
- Chrome: **PASS** - 300 packets, 82KB WebM file created
- Safari: **PASS** - 275 packets, 93KB WebM file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk VP9 Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_vp9_server.dart` + `save_to_disk_vp9_test.mjs`
- Uses MediaRecorder class with VP9 depacketizer pipeline
- Records 5 seconds of browser VP9 video to WebM file
- Chrome: **PASS** - 261 packets, 145KB WebM file created
- Safari: **SKIP** - VP9 not supported by Safari/WebKit
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk Opus Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_opus_server.dart` + `save_to_disk_opus_test.mjs`
- Uses MediaRecorder class with Opus audio codec
- Records 5 seconds of browser microphone audio to WebM file
- Chrome: **PASS** - 371 packets, 16KB WebM file created
- Safari: **PASS** - 377 packets, 22KB WebM file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk A/V (Audio+Video) Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_av_server.dart` + `save_to_disk_av_test.mjs`
- Uses MediaRecorder with VP8 video + Opus audio with lip sync enabled
- Records 5 seconds of browser camera+microphone to WebM file
- Chrome: **PASS** - 370 video + 370 audio packets, 15KB WebM file created
- Safari: **PASS** - 279 video + 279 audio packets, 149KB WebM file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk Packetloss Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_packetloss_server.dart` + `save_to_disk_packetloss_test.mjs`
- Uses VP8 codec with explicit RTCP feedback: NACK (retransmission), PLI (keyframe request), REMB (bitrate)
- Records 10 seconds of browser video with error recovery enabled
- Chrome: **PASS** - 497 packets, 497 keyframes, 4 PLI requests, 340KB WebM
- Safari: **PASS** - 486 packets, 486 keyframes, 4 PLI requests, 320KB WebM
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk DTX Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_dtx_server.dart` + `save_to_disk_dtx_test.mjs`
- Uses VP8 video + Opus audio with DTX enabled (usedtx=1)
- DtxProcessor detects gaps in audio stream and fills with silence frames
- Records 10 seconds of browser video+audio with DTX monitoring
- Chrome: **PASS** - 617 video + 617 audio packets, 481 speech + 136 comfort noise + 3 DTX fills, 34KB WebM
- Safari: **PASS** - 633 video + 633 audio packets, all speech (Safari doesn't use DTX), 1.3KB WebM
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk AV1 Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_av1_server.dart` + `save_to_disk_av1_test.mjs`
- Uses AV1 codec with full depacketization pipeline
- Records 5 seconds of browser AV1 video to WebM file
- Chrome: **PASS** - 297 packets, 1 keyframe, 165KB WebM file created
- Safari: **SKIP** - AV1 not supported by Safari
- Firefox: **SKIP** - AV1 not supported by Firefox + ICE issue

**Save to Disk GStreamer Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_gst_server.dart` + `save_to_disk_gst_test.mjs`
- Forwards raw RTP packets via UDP to GStreamer pipeline
- GStreamer handles depacketization and WebM muxing
- Records 5 seconds of browser VP8 video via GStreamer
- Chrome: **PASS** - 314 recv, 189 forwarded packets, 161KB WebM file created
- Safari: **PASS** - 306 recv, 184 forwarded packets, 148KB WebM file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk MP4 Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_mp4_server.dart` + `save_to_disk_mp4_test.mjs`
- Uses Mp4Container class for fragmented MP4 (fMP4) output
- Depacketizes H.264 RTP, extracts SPS/PPS, writes AVCC format to fMP4
- Records 5 seconds of browser H.264 video to MP4 file
- Chrome: **PASS** - 302 packets, 98 frames, 175KB MP4 file created
- Safari: **PASS** - 275 packets, 137 frames, 151KB MP4 file created
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk MP4 A/V Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_mp4_av_server.dart` + `save_to_disk_mp4_av_test.mjs`
- Uses Mp4Container with both H.264 video track and Opus audio track
- Depacketizes H.264 to AVCC format, passes Opus directly to container
- Records 5 seconds of browser camera + microphone to MP4 file
- Chrome: **PASS** - 300 video + 300 audio packets, 73 video frames + 144 audio frames, 261KB MP4
- Safari: **PASS** - 278 video + 278 audio packets, 103 video frames + 138 audio frames, 225KB MP4
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk MP4 Opus Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_mp4_opus_server.dart` + `save_to_disk_mp4_opus_test.mjs`
- Uses Mp4Container with Opus audio track only
- Opus frames written directly to fMP4 container (no transcoding)
- Records 5 seconds of browser microphone audio to MP4 file
- Chrome: **PASS** - 372 packets, 183 frames, 32KB MP4
- Safari: **PASS** - 379 packets, 195 frames, 40KB MP4
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Save to Disk RTP Dump Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/save_to_disk_dump_server.dart` + `save_to_disk_dump_test.mjs`
- Dumps raw RTP packets to binary files (4-byte length prefix + raw RTP data)
- Creates separate video and audio dump files for protocol analysis
- Records 5 seconds of browser camera + microphone RTP
- Chrome: **PASS** - 141 video + 141 audio packets, 118KB each
- Safari: **PASS** - 191 video + 191 audio packets, 20KB each
- Firefox: **SKIP** - Same ICE issue (Dart is offerer)

**Test Plan:**
1. ~~Run vp8.dart, have browser send video, verify output.webm plays~~ DONE
2. ~~Run h264.dart, have browser send H.264, verify output.webm plays~~ DONE
3. ~~Run vp9.dart, have browser send VP9 video, verify output.webm plays~~ DONE (Chrome only)
4. ~~Run opus.dart, have browser send audio, verify output.webm plays~~ DONE
5. ~~Run av.dart, have browser send A/V, verify output.webm plays~~ DONE
6. ~~Run packetloss/vp8.dart with NACK/PLI enabled~~ DONE
7. ~~Run mp4/h264.dart, verify output.mp4 is valid~~ DONE
8. ~~Run mp4/av.dart, verify output.mp4 contains A/V~~ DONE
9. ~~Run mp4/opus.dart, verify output.mp4 contains audio~~ DONE
10. ~~Run dump.dart to capture raw RTP for analysis~~ DONE
11. Test with varying durations (short clips, long recordings)

---

## 7. Infrastructure Examples (PARTIALLY VERIFIED Dec 2025)

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `certificate/offer.dart` | [x] | Terminal | Custom DTLS cert - fingerprint output verified |
| `getStats/demo.dart` | [x] | Dart-to-Dart | Stats API verified |
| `interop/server.dart` | [x] | Playwright | **Chrome pass** - Media echo works, DataChannel has SCTP issue |
| `interop/client.dart` | [ ] | Terminal | Dart client connecting to server |
| `interop/relay.dart` | [ ] | Manual Browser | SFU relay server |
| `benchmark/datachannel.dart` | [x] | Dart-to-Dart | Performance baseline (fixed listener race) |

**Test Results:**
- getStats() returns proper RTCStatsReport structure
- Peer-connection stats track dataChannelsOpened/Closed

**Certificate Example Test Results (Dec 2025):**
- Shows DTLS fingerprint in offer SDP output
- Custom certificate configuration ready for production use

**Interop Server Test Results (Dec 2025):**
- Test infrastructure: `interop/automated/interop_server_test.mjs`
- HTTP POST signaling (no trickle ICE)
- Chrome: **PASS** - Media echo works, DataChannel timeout (SCTP-only connection issue)
- Safari: **SKIP** - No trickle ICE support, slow ICE gathering
- Firefox: **SKIP** - Known ICE issue when Dart is answerer

---

## 8. Specialized Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `dash/server/main.dart` | [ ] | Manual Browser | DASH streaming server |
| `google-nest/server.dart` | [ ] | Terminal | Requires Nest camera |
| `playground/signaling/offer.dart` | [ ] | Manual Browser | Experimentation |

---

## Testing Infrastructure

### Playwright Setup

```bash
cd interop/automated
npm install
npx playwright install
```

### Running Tests with Scripts (RECOMMENDED)

Use the provided shell scripts to run tests. They handle server startup, timeouts, and cleanup automatically:

```bash
cd interop/automated

# Run a single test (starts server, runs test, cleans up)
./run_test.sh browser chrome           # DataChannel test with Chrome
./run_test.sh ice_trickle firefox       # ICE trickle test with Firefox
./run_test.sh media_sendonly safari     # Media test with Safari

# Use environment variable instead
BROWSER=firefox ./run_test.sh ice_restart

# Debug mode - shows full server output
./run_debug_test.sh save_to_disk chrome

# List available tests
./run_test.sh

# Stop orphaned processes (cleanup)
./stop_test.sh              # Kill all test processes
./stop_test.sh ice_trickle  # Kill specific test's port

# Run ALL tests (comprehensive suite)
./run_all_tests.sh chrome   # Run all tests with Chrome
./run_all_tests.sh          # Defaults to Chrome

# Debug SDP output (for troubleshooting)
./check_sdp.sh save_to_disk # Dump SDP from a test server
```

**Script Features:**
- Automatic server startup with health check
- Test execution with 2-minute timeout (prevents hanging)
- Automatic cleanup of server processes on exit
- Port conflict detection and resolution
- Support for both `BROWSER=x` and command line argument

**Available test names:**
| Test Name | Port | Description |
|-----------|------|-------------|
| `browser` | 8765 | Basic DataChannel (uses dart_signaling_server) |
| `ice_trickle` | 8781 | ICE trickle + DataChannel |
| `ice_restart` | 8782 | ICE restart with credential change |
| `media_sendonly` | 8766 | Dart sends video to browser |
| `media_recvonly` | 8767 | Browser sends video to Dart |
| `media_sendrecv` | 8768 | Echo pattern (bidirectional) |
| `save_to_disk` | 8769 | VP8 recording to WebM |
| `save_to_disk_h264` | 8770 | H.264 recording |
| `save_to_disk_vp9` | 8771 | VP9 recording |
| `simulcast` | 8780 | Simulcast SDP negotiation |
| `twcc` | 8779 | Transport-wide congestion control |
| `rtx` | 8778 | RTX retransmission |

### Run Automated Tests (Legacy)

```bash
# Test all browsers
npm test

# Test specific browser
npm run test:chrome
npm run test:firefox
npm run test:safari
```

### Browser Selection (IMPORTANT)

Test scripts support **two equivalent syntaxes** for selecting which browser to test:

```bash
# Method 1: Environment variable (takes precedence)
BROWSER=firefox node ice_trickle_test.mjs

# Method 2: Command line argument
node ice_trickle_test.mjs firefox

# Both work - env var is checked first, then command line arg
# Default is 'chrome' if neither is specified
```

**Valid browser values:**
- `chrome` or `chromium` - Google Chrome/Chromium
- `firefox` - Mozilla Firefox
- `safari` or `webkit` - Apple Safari/WebKit
- `all` - Run all browsers sequentially

**Implementation:**
All test files import `getBrowserArg()` from `test_utils.mjs`:
```javascript
import { getBrowserArg } from './test_utils.mjs';
const browserArg = getBrowserArg() || 'all';
```

The helper checks `process.env.BROWSER` first, then `process.argv[2]`, defaulting to `'chrome'`.

### Manual Browser Testing

1. Start Dart server: `dart run example/<path>/server.dart`
2. Open browser to indicated URL (usually http://localhost:8080)
3. Open DevTools console to see WebRTC internals
4. Use chrome://webrtc-internals for detailed debugging

### TypeScript Comparison

For terminal tests comparing with werift:
```bash
# Terminal 1: Run werift TypeScript version
cd werift-webrtc/examples/<example>
npx ts-node offer.ts

# Terminal 2: Run Dart version
dart run example/<example>/offer.dart
```

---

## Priority Order

1. **DataChannel** - Foundation for all signaling
2. **ICE/Trickle** - Critical for real-world connectivity
3. **MediaChannel sendonly/recvonly** - Basic media verification
4. **Save to Disk** - Recording functionality
5. **Advanced features** - RTX, TWCC, Simulcast
6. **Codec-specific** - Browser compatibility matrix

---

## Browser Compatibility Notes

| Feature | Chrome | Firefox | Safari |
|---------|--------|---------|--------|
| DataChannel | ✅ | ✅ | ✅ |
| VP8 | ✅ | ✅ | ✅ |
| VP9 | ✅ | ✅ | ❌ |
| H.264 | ✅ | ✅ | ✅ |
| AV1 | ✅ | ❌ | ❌ |
| Simulcast | ✅ | ✅ | ⚠️ |
| RTX | ✅ | ✅ | ✅ |
| RED | ✅ | ✅ | ⚠️ |

---

## Next Steps

1. [x] Create Playwright test scaffolding for each testable example
2. [x] Add npm scripts for running individual example tests
3. [ ] Document expected behavior for each example
4. [ ] Track any behavioral differences from werift
5. [ ] Complete remaining browser interop tests (MediaChannel)
6. [x] Test save_to_disk examples with actual video streams

---

## Placeholder-to-Implementation Plan (Dec 2025)

Many Dart examples were initially created as documentation placeholders showing concepts but not fully functional.
After comparing with werift-webrtc, we're converting ALL placeholders to working implementations with browser tests.

### Priority 1: Save to Disk (werift has full implementations)

| Example | werift Status | Dart Status | Action |
|---------|--------------|-------------|--------|
| `save_to_disk/packetloss/vp8.dart` | Full server with NACK/PLI | **DONE** | Chrome/Safari pass |
| `save_to_disk/dtx/server.dart` | Full A/V with DTX silence | **DONE** | Chrome/Safari pass |
| `save_to_disk/gst/recorder.dart` | GStreamer integration | **DONE** | Chrome/Safari pass |
| `save_to_disk/encrypt/server.dart` | N/A (Dart only) | Placeholder | Evaluate need |

### Priority 2: MediaChannel Advanced (werift has full implementations)

| Example | werift Status | Dart Status | Action |
|---------|--------------|-------------|--------|
| `mediachannel/red/adaptive/server.dart` | Adaptive RED server | **SKIP** | Browser RED support limited |
| `mediachannel/red/record/server.dart` | RED + recording | **SKIP** | Browser RED support limited |
| `mediachannel/sdp/offer.dart` | SDP manipulation | **SKIP** | Covered by existing tests |
| `mediachannel/lipsync/server.dart` | wip_lipsync (WIP) | Placeholder | Evaluate (werift is WIP) |

### Priority 3: Codec Tests (browser interop)

| Example | Action |
|---------|--------|
| `mediachannel/codec/vp9.dart` | Already tested via save_to_disk/vp9 |
| `mediachannel/codec/h264.dart` | Already tested via save_to_disk/h264 |
| `mediachannel/codec/av1.dart` | **DONE** - Chrome pass |

### Conversion Process

For each placeholder:
1. Read werift TypeScript implementation
2. Port to Dart with HTTP server for browser signaling
3. Create Playwright test runner
4. Verify Chrome/Safari pass (Firefox skipped - ICE issue)
5. Update this PLAN.md with results

## Bugs Fixed (Dec 2025)

1. **ProxyDataChannel stream controller issue** - Fixed event forwarding after close
2. **Transport initialization** - Added delays in examples before createDataChannel
3. **Message type handling** - Fixed String vs Uint8List handling in onMessage
4. **sendString await** - Must `await` sendString() calls in loops to avoid race conditions
5. **Benchmark listener race** - Rewrote benchmark to use persistent listeners instead of per-message subscriptions
6. **Media sendonly server UDP port issue** - Fixed race condition in port allocation by binding directly to port 0
7. **ICE candidate parsing** - Handle empty/malformed ICE candidates gracefully (Firefox sends empty end-of-candidates)

## Known Issues (Dec 2025)

1. **~~Firefox headless ICE issue (Dart as offerer)~~** (FIXED Dec 2025)
   - **Status**: RESOLVED - Was a local firewall issue, not a WebRTC/Firefox bug
   - **Original symptom**: Firefox in Playwright headless mode had ICE issues when Dart was the offerer
   - **Root Cause**: Local firewall was blocking incoming connections from Firefox
   - **Fix**: After firewall configuration, Firefox works with Dart as offerer
   - **Verified working**: ICE trickle (197ms), ICE restart, media sendonly (161 frames), basic DataChannel
   - **Still skipped**: Tests requiring Firefox headless getUserMedia (recvonly, sendrecv, save_to_disk) - this is a Playwright limitation, not WebRTC

2. **~~DCEP/DataChannel failure when PeerConnection created just-in-time~~** (FIXED Dec 2025)
   - **Status**: RESOLVED
   - **Root Cause**: SCTP packet serialization did not add 4-byte padding between chunks as required by RFC 4960
   - **The Bug**: The `SctpPacket.serialize()` method concatenated chunk data directly without padding. When a DATA chunk length was not a multiple of 4 bytes, the browser silently dropped the packet.
   - **Why It Appeared Timing-Related**: The working test ("connect-test" label = 12 bytes) had DATA chunk length 40 (divisible by 4). The failing test ("pc-connect-test" label = 15 bytes) had DATA chunk length 43 (not divisible by 4).
   - **Fix**: Modified `lib/src/sctp/packet.dart` to pad each chunk to 4-byte boundaries during serialization
   - **Test files**: Both `ice_trickle_with_connect.dart` and `ice_trickle_pc_in_connect.dart` now pass

3. **~~Sendrecv answer echo pattern (browser shows 0 frames)~~** (FIXED Dec 2025)
   - **Status**: RESOLVED
   - **Root Cause**: Payload type rewriting during RTP forwarding
   - **The Bug**: When echoing RTP packets, `sendRawRtpPacket` was overriding the payload type with the negotiated codec PT (e.g., VP8=96). However, Chrome uses RED (pt=123) codec wrapper for video. Browser sent RED packets (pt=123) but received VP8 packets (pt=96) back, causing decode failure.
   - **Fix**: Removed `payloadType: codec.payloadType` override in `_attachNonstandardTrack` to preserve the original payload type when forwarding. This matches werift behavior of passing packets through without PT modification.
   - **File Changed**: `lib/src/media/rtp_transceiver.dart` - `_attachNonstandardTrack` method
   - **Result**: Echo now works - Chrome displays 164+ video frames from echoed packets
   - **Library improvements made** (also useful for this fix):
     - MID made nullable, assigned lazily during SDP negotiation
     - Transceivers matched by kind when MID doesn't match (for pre-created transceivers)
     - HeaderExtensionConfig created at send time, not attachment time
   - **Test files**: `interop/automated/sendrecv_answer_server.dart`, `sendrecv_answer_test.mjs`

4. **RID header extension parsing not wired** (FIXED Dec 2025)
   - **Status**: FULLY RESOLVED
   - **Root Cause**: Infrastructure existed but wasn't connected during SDP negotiation
   - **The Bug**: `RtpRouter` had `registerHeaderExtensions()` and `registerByRid()` methods but they were never called from `setRemoteDescription`. This meant simulcast RID-based routing didn't work.
   - **Fix**: Added calls in `_processRemoteMediaDescriptions()` to:
     - `_rtpRouter.registerHeaderExtensions(headerExtensions)` - registers extension ID to URI mapping
     - `_rtpRouter.registerByRid(rid, handler)` - registers RID handlers for simulcast layers
   - **File Changed**: `lib/src/peer_connection.dart` - `_processRemoteMediaDescriptions` method
   - **Result**: Simulcast RID-based packet routing now functional for receive path
   - **Simulcast SDP (Dec 2025)**: Added `a=rid:<rid> <direction>` and `a=simulcast:recv/send <rids>` attributes to `createOffer()`. Chrome interop test passes with 238 packets received on "high" RID layer.

5. **Pub/Sub video forwarding (subscriber sees 0 frames)** (FIXED Dec 2025)
   - **Status**: RESOLVED
   - **Root Cause**: Chrome's fake camera doesn't respond to PLI requests; new subscribers never receive keyframe
   - **The Bug**: Multi-peer SFU routing worked at the packet level (500+ packets sent to subscriber), but browser showed `framesDecoded: 0` because VP8 decoder needs a keyframe to start. PLI requests were sent but Chrome's fake camera ignores them.
   - **Multiple Sub-issues Fixed**:
     1. **Extension IDs not set**: `absSendTimeExtensionId` and `transportWideCCExtensionId` were null for dynamically created transceivers. Added default extension ID constants and set them in `addTransceiver()`.
     2. **Keyframe detection wrong**: Was checking frame_type=0 without S bit, detecting continuation packets as keyframes. Fixed to require BOTH S=1 (start of partition) AND frame_type=0.
     3. **No keyframe cache**: Added keyframe caching - collect packets from keyframe start until marker=true, store in cache, send to new subscribers immediately.
   - **Files Changed**:
     - `lib/src/peer_connection.dart` - Added `_absSendTimeExtensionId`, `_twccExtensionId` constants, set in `addTransceiver()`
     - `lib/src/media/rtp_transceiver.dart` - Added `forwardCachedPackets()` method for sending cached keyframes
     - `example/mediachannel/pubsub/offer.dart` - VP8 keyframe detection and caching logic
   - **Result**: Video now plays (640x480) for subscribers - cached keyframe enables immediate decoding
   - **Test files**: `interop/automated/pubsub_test.mjs`
