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

### Status: Phase 4 COMPLETE - werift Parity Achieved

| Component | Status | Tests |
|-----------|--------|-------|
| Core Protocols (STUN/ICE/DTLS/SRTP/SCTP/RTP) | ✅ Complete | 500+ |
| DataChannel | ✅ Complete | Full DCEP |
| VP8 Depacketization | ✅ Complete | 22 |
| VP9 Depacketization | ✅ Complete | 25 |
| H.264 Depacketization | ✅ Complete | 22 |
| AV1 Depacketization | ✅ Complete | 32 |
| NACK | ✅ Complete | 41 |
| PLI/FIR | ✅ Complete | 48 |
| RTX + SDP Negotiation | ✅ Complete | 85 |
| TURN (Core + Data Relay) | ✅ Complete | 50 |
| TWCC | ✅ Complete | - |
| Simulcast | ✅ Complete | - |
| Jitter Buffer | ✅ Complete | - |
| getStats() | ✅ Complete | 9 |
| **Total** | **1650 tests passing** | **0 analyzer issues** |

### Browser Interop Status
- ✅ **Chrome**: DataChannel + Media working
- ✅ **Firefox**: DataChannel + Media working
- ✅ **Safari (WebKit)**: DataChannel + Media working

Automated Playwright test suite in `interop/automated/`

See **ROADMAP.md** for detailed implementation history and future work.

---

## Development Commands

### Setup
```bash
# Install dependencies
dart pub get
```

### Testing
```bash
# Run all tests
dart test

# Run a specific test file
dart test test/webrtc_dart_test.dart
```

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
```bash
# Manual browser test
dart run interop/browser/server.dart
# Open http://localhost:8080 in Chrome

# Automated Playwright tests
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

## Implementation Roadmap (15 Phases)

### Phase 1-4: Core Implementation ✅ COMPLETE
1. Scope & MVP Definition
2. Architecture & Module Layout
3. Binary & Crypto Foundations
4. STUN & TURN Layer
5. ICE Agent
6. DTLS Handshake & Record Layer
7. SRTP / SRTCP
8. RTP & RTCP Stack
9. SCTP & Data Channels
10. SDP & Signalling API

### Phase 5: Beyond werift (Future)
11. Media Integration - Pluggable audio/video sources, encoders/decoders
12. Observability, Logging & Debugging Tools
13. Interop & Compliance Test Matrix
14. Performance, Benchmarks & Tuning
15. Packaging, Docs & Examples

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
- Update `CHANGELOG.md` for each version change under appropriate sections: Added, Changed, Fixed, Removed
- Tag the release in Git:
  ```bash
  git tag -a vX.Y.Z -m "Release version X.Y.Z"
  git push origin vX.Y.Z
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
- Roadmap: See `ROADMAP.md`
