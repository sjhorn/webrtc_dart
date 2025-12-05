# TODO.md - webrtc_dart

**Last Updated:** December 2025

---

## Current Status

**Phase 4: COMPLETE** - werift Parity Achieved
**Test Count:** 1658 tests passing
**Analyzer:** 0 errors, 0 warnings, 0 info
**Browser Interop:** Chrome, Firefox, Safari - All Working

---

## werift Parity: COMPLETE

All features from werift-webrtc TypeScript have been ported to Dart:

- Core protocols (STUN, ICE, DTLS, SRTP, SCTP, RTP/RTCP)
- DataChannel (reliable/unreliable, ordered/unordered)
- Video codec depacketization (VP8, VP9, H.264, AV1)
- RTCP feedback (NACK, PLI, FIR)
- Retransmission (RTX)
- TURN support (UDP with data relay)
- TWCC (Transport-Wide Congestion Control)
- Simulcast with RID/MID
- Jitter buffer
- RED (Redundancy Encoding)
- ICE Restart, ICE TCP, mDNS
- Extended getStats() API
- MediaRecorder (WebM/MP4)
- Stream Reconfiguration (RFC 6525)
- CertificateRequest message (RFC 5246)

---

## Browser Interop Status

| Browser | DataChannel | Media | Status |
|---------|-------------|-------|--------|
| Chrome | Working | Working | Tested |
| Firefox | Working | Working | Tested |
| Safari | Working | Working | Tested |

Automated Playwright test suite in `interop/automated/`

---

## Future (Phase 5) - Beyond werift

These features are NOT in werift-webrtc and would require building from RFCs:

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

### Run Browser Interop Tests
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

See **ROADMAP.md** for detailed implementation history.
