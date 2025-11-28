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

## Architecture

### Current State
This is an early-stage project. The codebase currently contains only boilerplate Dart package structure. The actual WebRTC implementation is being ported incrementally from the TypeScript source.

### Planned Module Structure
The port will follow a layered architecture matching the TypeScript original:

1. **Binary & Crypto Foundations** - Low-level packet parsing, binary helpers, cryptographic primitives
2. **STUN & TURN Layer** - STUN message encoding/decoding, TURN allocation
3. **ICE Agent** - Candidate gathering, connectivity checks, nomination
4. **DTLS Handshake** - DTLS 1.2 state machine, record layer, key extraction for SRTP
5. **SRTP/SRTCP** - Secure RTP implementation (AES-CTR/AES-CM + HMAC-SHA1), replay protection
6. **RTP & RTCP Stack** - RTP header parsing, SSRC handling, RTCP (SR, RR, SDES, BYE)
7. **SCTP & Data Channels** - SCTP over DTLS, datachannel protocol
8. **SDP & Signaling** - SDP parsing/generation, public API (`PeerConnection`, `addIceCandidate`, etc.)
9. **Media Integration** (Phase 2) - Audio/video sources, codec support

Refer to `AGENTS.md` for the complete implementation roadmap.

### Package Structure (to be created)
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
```

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

## macOS Network Entitlements

When creating Flutter examples requiring network access:
- Add network entitlements to both Debug and Release configurations:
  - `macos/Runner/DebugProfile.entitlements` - Add `com.apple.security.network.client` and `com.apple.security.network.server`
  - `macos/Runner/Release.entitlements` - Add `com.apple.security.network.client`

## Interop & Validation Strategy

The port's correctness is validated through:
- **Unit tests** with captured TypeScript outputs as expected values
- **Golden tests** for binary packet formats
- **Interop testing** between Dart implementation and:
  - Chrome/Firefox browsers
  - TypeScript werift-webrtc
  - Other implementations (Pion, libdatachannel)

Each layer should be validated independently before building on top of it.

## References

- TypeScript source: `./werift-webrtc`
- Original documentation and markdown files will be ported from `./werift-webrtc`
- TODO tracking: See `AGENTS.md` for the 15-phase implementation roadmap
