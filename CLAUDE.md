# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a pure Dart port of the [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) TypeScript codebase, implementing WebRTC functionality natively in Dart. The original TypeScript repository is cloned locally in `./werift-webrtc` for reference.

### Porting Philosophy
- Mimic the directory structure, filenames, and classnames of the TypeScript source where possible, while following Dart conventions
- Match input/output behavior of TypeScript methods exactly
- Create small test scripts to capture TypeScript outputs for given inputs, then use these as test cases in Dart tests (avoiding runtime dependency on TypeScript)
- For crypto: replicate TypeScript approach where directly implemented; use `package:cryptography` where TypeScript uses crypto libraries
- For binary operations: use `Uint8List` and `ByteData.view`, implementing helpers similar to Node Buffer/DataView for ergonomic parsing

---

## Current Progress (December 2025)

### Status: 100% werift Parity Achieved

All WebRTC features complete: ICE, DTLS, SRTP, SCTP, RTP/RTCP, DataChannels, Media.
Codecs: VP8, VP9, H.264, AV1, Opus. Features: NACK, PLI/FIR, RTX, TWCC, Simulcast, getStats().

**2661 tests passing, 0 analyzer issues**

### Server-Side WebRTC (v0.25.0)

This is a **server-side** WebRTC library like Pion (Go), aiortc (Python), werift (TS).
- Complete transport layer: ICE, DTLS, SRTP, SCTP, RTP/RTCP
- W3C-compatible API naming: RTCPeerConnection, RTCDataChannel, etc.
- Does NOT include: media capture (getUserMedia), codec encoding/decoding
- For media: use external tools (FFmpeg, GStreamer) to pipe RTP

### Browser Interop Status
- ✅ **Chrome**: DataChannel + Media working
- ✅ **Firefox**: DataChannel + Media working
- ✅ **Safari (WebKit)**: DataChannel + Media working

Automated Playwright test suite in `interop/automated/`

See **ROADMAP.md** for detailed feature status and future plans.

---

## Development Commands

### Setup
```bash
# Install dependencies
dart pub get
```

### Testing

**IMPORTANT: Always pipe test output to `/tmp/` to avoid re-running tests for grep/analysis:**

```bash
# Standard workflow - run once, analyze from file
dart test --exclude-tags=slow 2>&1 | tee /tmp/dart_test.txt
# Then grep/analyze without re-running:
grep -E "passed|failed|Some tests" /tmp/dart_test.txt
tail -20 /tmp/dart_test.txt
grep -i "error\|exception" /tmp/dart_test.txt

# Run all tests (save to file)
dart test 2>&1 | tee /tmp/dart_test.txt

# Run fast tests only (excludes 20-second stability test)
dart test --exclude-tags=slow 2>&1 | tee /tmp/dart_test.txt

# Run slow/integration tests with limited concurrency
dart test --tags=slow --concurrency=1 2>&1 | tee /tmp/dart_test.txt

# Run a specific test file
dart test test/webrtc_dart_test.dart 2>&1 | tee /tmp/dart_test.txt

# Run a single test by name
dart test --plain-name 'test name here' 2>&1 | tee /tmp/dart_test.txt
```

**Test Tags:**
- `slow` - Long-running tests (20+ seconds) that may be flaky when run concurrently
- `performance` - Performance regression tests

### Code Quality
```bash
# Format code
dart format .

# Check for format issues without changing files
dart format --set-exit-if-changed .

# Analyze code for issues
dart analyze
```

### Running Examples
```bash
dart run example/webrtc_dart_example.dart
```

### Browser Interop Tests

**Run all tests (parallel, ~40s):**
```bash
cd interop/automated
./run_all_tests.sh chrome        # 23 tests, 8 parallel (default)
./run_all_tests.sh chrome 4      # Run with 4 parallel
./run_all_tests.sh firefox       # Test Firefox
```

**Run a single test:**
```bash
./run_test.sh browser chrome           # DataChannel test
./run_test.sh ice_trickle firefox      # ICE trickle test
./run_test.sh media_sendonly safari    # Media test
./run_test.sh save_to_disk chrome      # Recording test
./run_test.sh                          # List all available tests
```

**Debug mode** (shows full Dart server output):
```bash
./run_debug_test.sh save_to_disk chrome
```

**Cleanup orphaned processes:**
```bash
./stop_test.sh              # Kill all test processes
./stop_test.sh ice_trickle  # Kill specific test
```

**Test Results Logging** (preferred for Claude Code sessions):
```bash
# Results automatically saved to test_results.log
cat interop/automated/test_results.log

# For single tests, pipe to file
./run_test.sh browser chrome 2>&1 | tee /tmp/browser_test.log
grep -E "PASS|FAIL|Error" /tmp/browser_test.log
```

**Serial runner** (if parallel causes issues):
```bash
./run_all_tests_serial.sh chrome  # Sequential execution (~4 min)
```

**Manual testing** (run server and test separately):
```bash
# Terminal 1: Start Dart server
dart run interop/automated/ice_trickle_server.dart

# Terminal 2: Run browser test
cd interop/automated
node ice_trickle_test.mjs chrome
# Or: BROWSER=chrome node ice_trickle_test.mjs

# Manual browser test (open in browser)
dart run interop/browser/server.dart
# Open http://localhost:8080 in Chrome
```

**Legacy npm scripts**:
```bash
cd interop
npm install
npm test              # Test all browsers
npm run test:chrome   # Test Chrome only
npm run test:firefox  # Test Firefox only
npm run test:safari   # Test Safari/WebKit only
```

### TypeScript Interop Test
```bash
node interop/js_answerer.mjs &
dart run interop/dart_offerer.dart
```

---

## Architecture

### Package Structure
```
lib/
  src/
    ice/          # ICE transport, candidate handling
    dtls/         # DTLS handshake and record layer
    srtp/         # SRTP/SRTCP implementation
    rtp/          # RTP/RTCP stack
    sctp/         # SCTP transport, data channels
    sdp/          # SDP parsing and generation
    stun/         # STUN/TURN protocol
    crypto/       # Cryptographic primitives
    utils/        # Binary helpers, buffer utilities
    media/        # Media tracks, transceivers
    rtcp/         # RTCP feedback (NACK, PLI, FIR, TWCC)
    datachannel/  # DataChannel protocol (DCEP)
    audio/        # Audio processing
    container/    # WebM/MP4 containers
    nonstandard/  # Extended APIs (writeRtp, etc.)
    stats/        # getStats() implementation
```

### Layered Architecture
1. **Binary & Crypto Foundations** - Low-level packet parsing, binary helpers, cryptographic primitives
2. **STUN & TURN Layer** - STUN message encoding/decoding, TURN allocation
3. **ICE Agent** - Candidate gathering, connectivity checks, nomination
4. **DTLS Handshake** - DTLS 1.2 state machine, record layer, key extraction for SRTP
5. **SRTP/SRTCP** - Secure RTP implementation (AES-CTR/AES-CM + HMAC-SHA1), replay protection
6. **RTP & RTCP Stack** - RTP header parsing, SSRC handling, RTCP (SR, RR, SDES, BYE)
7. **SCTP & Data Channels** - SCTP over DTLS, datachannel protocol
8. **SDP & Signaling** - SDP parsing/generation, public API (`PeerConnection`, `addIceCandidate`, etc.)
9. **Media Integration** - Audio/video sources, codec support

---

## RTP Forwarding/Echo Debugging Guide

When debugging RTP forwarding issues (echo, relay, SFU scenarios), check these common pitfalls:

### 1. Multiple SSRCs from Browser
Chrome sends packets from **multiple SSRCs** early in a stream:
- **Probing packets**: `ts=0`, small payload (~255 bytes), used for bandwidth estimation
- **RTX packets**: Retransmission stream with different SSRC and PT (typically main PT + 1)
- **Simulcast layers**: Different SSRCs for each quality layer

**Fix**: Lock onto the first valid SSRC and filter out packets from other SSRCs. See `_primarySsrc` in `rtp_sender.dart`.

### 2. Payload Type Mismatch
When Dart is the **answerer**, the browser chooses the codec from our offered list. Chrome may pick AV1 (PT=119) instead of VP8 (PT=96).

**Symptom**: Packets are sent but browser shows 0 frames.
**Fix**: Capture and use the actual payload type from incoming packets, not the configured codec PT.

### 3. Offerer vs Answerer Differences
| Aspect | Dart as Offerer | Dart as Answerer |
|--------|-----------------|------------------|
| MID | Assigned by Dart (e.g., "1") | Assigned by browser (e.g., "0") |
| Extension IDs | Dart's defaults (midExtId=1) | Browser's preferences (midExtId=9) |
| Codec selection | Browser must use our preference | Browser chooses from our list |
| SSRC behavior | Usually single SSRC | May see multiple SSRCs early |

### 4. Header Extension IDs
Extension IDs are negotiated per-session. When Dart is answerer:
- The browser's offer specifies extension IDs (e.g., `a=extmap:9 sdes:mid`)
- Dart's answer must echo these IDs
- `setRemoteRTP()` updates sender's extension IDs from remote SDP

### 5. Debugging RTP Issues
```bash
# Save test output to file to avoid repeated runs
./run_test.sh sendrecv_answer chrome 2>&1 | tee /tmp/test_output.txt

# Then grep for specific info
grep "SSRC\|PT=" /tmp/test_output.txt
grep "Skipping\|Forwarding" /tmp/test_output.txt
```

Key debug points in `rtp_sender.dart:_attachNonstandardTrack`:
- Log incoming SSRC, PT, seq, ts for first N packets
- Track which packets are filtered vs forwarded

---

## Code Style & Conventions

- Follow [Dart style guide](https://dart.dev/guides/language/effective-dart/style)
- Two spaces for indentation
- Use `final` and `const` where possible
- Document public APIs with `///` (Dartdoc comments)
- Private members start with `_`
- Avoid `dynamic` unless absolutely necessary
- Null-safety is enforced
- Import organization:
  1. Dart SDK imports
  2. Third-party package imports
  3. Local package imports
  (Each group separated by a blank line)

---

## Testing Requirements

- All new features must include tests in `test/`
- Use descriptive test names
- Follow arrange/act/assert pattern
- Use golden tests for binary serialization/deserialization (encode/decode round-trips)
- Validate against known test vectors for crypto operations
- Before merging, verify:
  ```bash
  dart format --set-exit-if-changed .
  dart analyze
  dart test
  ```

---

## macOS Network Entitlements

When creating Flutter examples requiring network access:
- Add network entitlements to both Debug and Release configurations:
  - `macos/Runner/DebugProfile.entitlements` - Add `com.apple.security.network.client` and `com.apple.security.network.server`
  - `macos/Runner/Release.entitlements` - Add `com.apple.security.network.client`

Example DebugProfile.entitlements:
```xml
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## Interop & Validation Strategy

The port's correctness is validated through:
- **Unit tests** with captured TypeScript outputs as expected values
- **Golden tests** for binary packet formats
- **Interop testing** between Dart implementation and:
  - Chrome/Firefox/Safari browsers
  - TypeScript werift-webrtc
  - Other implementations (Pion, libdatachannel)

Each layer should be validated independently before building on top of it.

---

## Pull Request Guidelines

- Title format: `<component>: <short description>` or `bugfix(<component>): <short description>`
- PR description should contain:
  - Summary of change
  - Motivation / context
  - How to test the change
- Link to any relevant issue(s) or discussion(s)
- After approval, merge via "Squash & merge"
- Post-merge: create a new release tag (`vX.Y.Z`) and update `CHANGELOG.md`

---

## Versioning & CHANGELOG

- Use [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`
- **IMPORTANT**: When releasing a new version, follow these steps:

### Release Checklist
```bash
# 1. Run all tests (must pass)
dart test

# 2. Run dart analyze (no errors or warnings, infos OK for FFI naming)
dart analyze

# 3. Run performance tests (check for regressions)
./benchmark/run_perf_tests.sh

# 4. Save benchmark results for this release
dart run benchmark/save_results.dart vX.Y.Z

# 5. Update version in all files:
#    - pubspec.yaml - version field
#    - README.md - installation example (webrtc_dart: ^X.Y.Z)
#    - README.md - ensure acronyms have expanded names on first use
#      (e.g., "SFU (Selective Forwarding Unit)", "ICE (Interactive Connectivity Establishment)")
#    - CHANGELOG.md - add new version section
#    - REFACTOR.md - test count if changed
#    - CLAUDE.md - test count if changed

# 6. Commit and tag
git add .
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Release version X.Y.Z"
git push origin main --tags

# 7. Publish to pub.dev
dart pub publish
```

---

## Security & Compliance

- Avoid committing secrets (API keys, credentials) in the repository
- Use `.gitignore` for local settings, build artifacts, and analysis caches
- For dependencies: review license compliance and check for vulnerabilities (`dart pub outdated`)
- If your package interacts with platform channels (Flutter) or native code, validate memory safety and concurrency issues

---

## Dart Package Conventions

- **example/example.md**: Required by Dart package conventions for pub.dev Example tab. Keep this file with a simple, runnable example.

---

## References

- TypeScript source: `./werift-webrtc`
- Technical comparison: See `REFACTOR.md`
