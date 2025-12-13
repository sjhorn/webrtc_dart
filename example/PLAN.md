# Example Testing Plan

This document tracks verification of each example against werift-webrtc behavior.

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

## 2. DataChannel Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `datachannel/quickstart.dart` | [ ] | Dart-to-Dart | Basic DC creation and messaging |
| `datachannel/local.dart` | [ ] | Terminal | Local loopback test |
| `datachannel/offer.dart` | [ ] | Playwright | Browser answerer |
| `datachannel/answer.dart` | [ ] | Terminal | Dart answers browser offer |
| `datachannel/string.dart` | [ ] | Playwright | String message exchange |
| `datachannel/manual.dart` | [ ] | Manual Browser | Copy/paste SDP flow |
| `datachannel/signaling_server.dart` | [ ] | Playwright | WebSocket signaling |

**Test Plan:**
1. Start with `quickstart.dart` - verify basic DC works Dart-to-Dart
2. Run `signaling_server.dart` + Playwright browser client
3. Test `offer.dart` with Chrome, Firefox, Safari via Playwright
4. Manual browser test with `manual.dart` for debugging

---

## 3. Close Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `close/dc/closed.dart` | [ ] | Dart-to-Dart | Verify DC close event fires |
| `close/dc/closing.dart` | [ ] | Dart-to-Dart | Verify closing state transition |
| `close/pc/closed.dart` | [ ] | Dart-to-Dart | Verify PC close event fires |
| `close/pc/closing.dart` | [ ] | Dart-to-Dart | Verify closing state transition |

**Test Plan:**
1. Run each example and verify state transitions match werift
2. Compare event ordering with TypeScript version

---

## 4. ICE Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `ice/trickle/offer.dart` | [ ] | Playwright | Trickle ICE with browser |
| `ice/trickle/dc.dart` | [ ] | Playwright | Trickle ICE + DataChannel |
| `ice/restart/offer.dart` | [ ] | Playwright | ICE restart flow |
| `ice/restart/quickstart.dart` | [ ] | Dart-to-Dart | Basic restart test |
| `ice/turn/quickstart.dart` | [ ] | Terminal | TURN server connectivity |
| `ice/turn/trickle_offer.dart` | [ ] | Playwright | TURN + trickle ICE |

**Test Plan:**
1. Verify trickle ICE works with all browsers
2. Test ICE restart mid-connection
3. TURN tests require external TURN server (coturn or similar)

---

## 5. MediaChannel Examples

### 5.1 Basic Media

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/sendonly/offer.dart` | [ ] | Playwright | Send video to browser |
| `mediachannel/sendonly/av.dart` | [ ] | Playwright | Send audio+video |
| `mediachannel/sendonly/ffmpeg.dart` | [ ] | Manual Browser | FFmpeg as media source |
| `mediachannel/recvonly/offer.dart` | [ ] | Playwright | Receive from browser |
| `mediachannel/sendrecv/offer.dart` | [ ] | Playwright | Bidirectional media |

### 5.2 Codec-Specific

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/codec/vp8.dart` | [ ] | Playwright | VP8 negotiation |
| `mediachannel/codec/vp9.dart` | [ ] | Playwright | VP9 + SVC layers |
| `mediachannel/codec/h264.dart` | [ ] | Playwright | H.264 profiles |
| `mediachannel/codec/av1.dart` | [ ] | Playwright | AV1 (Chrome only) |

### 5.3 Advanced Features

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `mediachannel/rtx/offer.dart` | [ ] | Playwright | RTX retransmission |
| `mediachannel/twcc/offer.dart` | [ ] | Playwright | Transport-wide CC |
| `mediachannel/simulcast/offer.dart` | [ ] | Playwright | Simulcast layers |
| `mediachannel/rtp_forward/offer.dart` | [ ] | Terminal | RTP forwarding |
| `mediachannel/red/sendrecv.dart` | [ ] | Playwright | RED redundancy |
| `mediachannel/red/adaptive/server.dart` | [S] | - | Documentation only |
| `mediachannel/red/record/server.dart` | [S] | - | Documentation only |
| `mediachannel/lipsync/server.dart` | [S] | - | Documentation only |
| `mediachannel/pubsub/offer.dart` | [ ] | Terminal | Multi-peer routing |
| `mediachannel/sdp/offer.dart` | [S] | - | Documentation only |

**Test Plan:**
1. Start with basic sendonly/recvonly to verify media flow
2. Test each codec with appropriate browsers (AV1 = Chrome)
3. Verify RTX with packet loss simulation
4. Test TWCC feedback loop
5. Simulcast requires browser sending multiple layers

---

## 6. Save to Disk Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `save_to_disk/vp8.dart` | [ ] | Playwright | Record VP8 to WebM |
| `save_to_disk/vp9.dart` | [S] | - | Documentation only |
| `save_to_disk/opus.dart` | [S] | - | Documentation only |
| `save_to_disk/mp4/h264.dart` | [ ] | Playwright | Record H.264 to MP4 |
| `save_to_disk/packetloss/vp8.dart` | [S] | - | Documentation only |
| `save_to_disk/dtx/server.dart` | [S] | - | Documentation only |
| `save_to_disk/gst/recorder.dart` | [S] | - | Documentation only |
| `save_to_disk/encrypt/server.dart` | [S] | - | Documentation only |

**Test Plan:**
1. Run vp8.dart, have browser send video, verify output.webm plays
2. Run mp4/h264.dart, verify output.mp4 is valid
3. Test with varying durations (short clips, long recordings)

---

## 7. Infrastructure Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `certificate/offer.dart` | [ ] | Terminal | Custom DTLS cert |
| `getStats/demo.dart` | [ ] | Playwright | Verify stats match browser |
| `interop/server.dart` | [ ] | Manual Browser | HTTP POST signaling |
| `benchmark/datachannel.dart` | [ ] | Dart-to-Dart | Performance baseline |

**Test Plan:**
1. Certificate: verify custom cert is used in DTLS handshake
2. getStats: compare Dart stats output with browser's RTCStatsReport
3. Benchmark: establish throughput/latency baseline

---

## 8. Specialized Examples

| Example | Status | Method | Notes |
|---------|--------|--------|-------|
| `dash/server/main.dart` | [S] | - | Documentation only |
| `google-nest/server.dart` | [S] | - | Requires Nest camera |
| `playground/signaling/offer.dart` | [ ] | Manual Browser | Experimentation |

---

## Testing Infrastructure

### Playwright Setup

```bash
cd interop/automated
npm install
npx playwright install
```

### Run Automated Tests

```bash
# Test all browsers
npm test

# Test specific browser
npm run test:chrome
npm run test:firefox
npm run test:safari
```

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

1. [ ] Create Playwright test scaffolding for each testable example
2. [ ] Add npm scripts for running individual example tests
3. [ ] Document expected behavior for each example
4. [ ] Track any behavioral differences from werift
