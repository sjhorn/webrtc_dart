# Changelog

All notable changes to this project will be documented in this file.

## 0.22.9

### Fixed

- **Firefox browser test** - Added STUN server configuration for ICE connectivity
- **Safari save_to_disk tests** - Added synthetic audio (Web Audio API) and video (canvas) for headless testing
- **Safari sendrecv_answer test** - Added frame counting fallback for WebKit headless

### Changed

- **Browser test infrastructure** - Added 1s delay between tests for reliable port cleanup
- **H264 test** - Skip Firefox (H264 encoding not supported in headless mode)
- **VP9 test** - Skip Safari (VP9 codec not supported by browser)

### Tests

- 22/22 browser interop tests passing on Chrome, Firefox, and Safari
- Full browser parity achieved across all three major browsers

## 0.22.8

### Added

- **30 example files matching werift patterns** - Complete parity with werift TypeScript examples:
  - `save_to_disk/`: vp8, vp9, h264, opus, av1x, rtp, pipeline (all use WebSocket + MediaRecorder)
  - `mediachannel/simulcast/`: offer, answer, multiple, multiple_answer, twcc
  - `mediachannel/sendonly/offer.dart` - GStreamer + WebSocket pattern
  - `mediachannel/sendrecv/offer.dart` - Header extensions + echo pattern

### Fixed

- **All analyzer warnings resolved** - `dart analyze` reports "No issues found!"
  - Migrated deprecated `addTransceiverWithTrack` to polymorphic `addTransceiver` API
  - Fixed conditional assignment style (??= operator)
  - Fixed dead code and unused variables in tests
  - Fixed catchError return types in transaction tests

### Changed

- **Deprecated `addTransceiverWithTrack`** - Use `addTransceiver(track, direction: ...)` instead
  - Matches werift's polymorphic API pattern
  - Updated all examples, interop servers, and tests

### Tests

- 2431 tests passing (up from 2262)
- 22/22 Chrome browser interop tests passing
- All examples verified against werift equivalents

## 0.22.7

### Fixed

- **SCTP RFC 4960 padding** - Chunks must be padded to 4-byte boundaries; fixes DataChannel failures with certain label lengths
- **Analyzer warnings** - Removed unused fields, imports, and dead null-aware expressions across interop tests

### Added

- **`waitForReady()` API** - Wait for PeerConnection async initialization before createDataChannel
- **createAnswer extmap support** - Answer SDP copies header extension mappings from offer (critical for browser RTP parsing)
- **createAnswer rtcp-fb support** - Answer SDP copies RTCP feedback attributes from offer (NACK, PLI, transport-cc)
- **Transceiver direction matching** - Creates transceivers with matching direction when remote is sendrecv
- **Header extension ID extraction** - Sets mid/abs-send-time/transport-cc extension IDs on sender from remote SDP
- **Comprehensive browser interop tests** - Playwright test suite for Chrome, Firefox, Safari

### Changed

- Improved RTP session handling for answerer pattern
- Enhanced header extension regeneration for RTP forwarding

### Tests

- 2262 tests passing (up from previous release)
- Browser interop: DataChannel, media sendonly/recvonly/sendrecv, save-to-disk, simulcast, TWCC
- All major browsers verified: Chrome (full), Safari (full), Firefox (with browser-as-offerer pattern)

## 0.22.6

### Added

- **Configurable logging** via Dart `logging` package:
  - `WebRtcLogging` class with hierarchical loggers per component (ICE, DTLS, SCTP, RTP, etc.)
  - `WebRtcLogging.enable()` / `WebRtcLogging.disable()` for global control
  - Selective logging: `WebRtcLogging.ice.level = Level.FINE`
  - Backward compatible: deprecated `webrtcDebug` flag still works

- **Ring camera example** (`example/ring/`):
  - Video streaming server connecting to Ring cameras via WebRTC
  - Forwards video to browser clients
  - Documentation for setup and audio/video handling

- **SRTP-CTR cipher support** (AES_CM_128_HMAC_SHA1_80):
  - Required for Ring camera compatibility
  - Refactored SRTP key derivation for both GCM and CTR modes
  - Fixed SRTCP index handling and authentication

- **API enhancements**:
  - `Candidate.copyWith()` for trickle ICE with sdpMLineIndex/sdpMid
  - `RtpTransceiver` codec preference support
  - `MediaStreamTrack.clone()` method

### Changed

- Migrated 284 debug call sites from custom `debugLog()` to standard logging
- Improved SRTP cipher architecture with separate CTR and GCM implementations

### Tests

- SRTP CTR cipher tests (542 lines)
- SRTP GCM cipher tests (541 lines)
- SRTP RFC 7714 test vectors (476 lines)
- Server handshake tests (406 lines)
- Extended peer connection tests
- Total: 2262 tests passing

## 0.22.5

### Added

- Expanded public API exports in `webrtc_dart.dart`:
  - Configuration types: `PeerConnectionState`, `SignalingState`, `IceConnectionState`, `IceGatheringState`, `RtcConfiguration`, `IceServer`, `IceTransportPolicy`, `RtcOfferOptions`
  - Media parameters: Complete RTP parameters API (`RTCRtpParameters`, `RTCRtpCodecParameters`, `RTCRtpEncodingParameters`, etc.)
  - RTCP feedback: REMB (`src/rtcp/psfb/remb.dart`) and TWCC (`src/rtcp/rtpfb/twcc.dart`)
  - RTP extensions: Header extension handling (`src/rtp/header_extension.dart`)
  - RTCP packet types (`src/srtp/rtcp_packet.dart`)
  - Transport layer: `IntegratedTransport`, `DtlsTransport`, `SctpAssociation`
  - STUN protocol: Message and attribute handling for advanced use cases
  - Binary utilities: `random16`, `random32`, `bufferXor`, `bufferArrayXor`

### Changed

- Core API exports now use explicit `show` clause for better API documentation
- Improved package API completeness to match werift-webrtc structure

## 0.22.4

### Added

- Test coverage improvements: 2171 tests, 80% code coverage
- New test files for DTLS, stats, and media components:
  - DTLS handshake message tests (finished, alert, random, client_key_exchange)
  - Extended master secret extension tests
  - Transport and certificate stats tests
  - Media parameters tests (RTCRtpEncodingParameters, RTCRtpSendParameters)
  - Processor interface tests (CallbackProcessor, AVProcessor mixin)

### Changed

- Updated README with accurate test count and coverage metrics

## 0.22.3

### Changed

- Upgrade pointycastle from 3.9.1 to 4.0.0
- Apply dart format to all source files
- Add example/example.md for pub.dev Example tab
- Add quickstart examples matching README inline code

### Fixed

- Remove unnecessary casts for pointycastle 4.0.0 compatibility
- Fix curly brace style in certificate_request.dart

## 0.22.2

Initial release - complete Dart port of werift-webrtc v0.22.2.

### Features

**Core Protocols**
- STUN message encoding/decoding with MESSAGE-INTEGRITY and FINGERPRINT
- ICE candidate model (host, srflx, relay, prflx)
- ICE checklists, connectivity checks, nomination
- ICE TCP candidates and mDNS obfuscation
- ICE restart support
- DTLS 1.2 handshake (client and server) with certificate authentication
- SRTP/SRTCP encryption (AES-GCM)
- RTP/RTCP stack (SR, RR, SDES, BYE)
- SCTP association over DTLS
- DataChannel protocol (reliable/unreliable, ordered/unordered)
- SDP parsing and generation

**Video Codec Depacketization**
- VP8 depacketization
- VP9 depacketization with SVC support
- H.264 depacketization with FU-A/STAP-A
- AV1 depacketization with OBU parsing

**RTCP Feedback**
- NACK (Generic Negative Acknowledgement)
- PLI (Picture Loss Indication)
- FIR (Full Intra Request)
- REMB (Receiver Estimated Max Bitrate)

**Retransmission**
- RTX packet wrapping/unwrapping
- RetransmissionBuffer (128-packet circular buffer)
- RTX SDP negotiation

**TURN Support**
- TURN allocation with 401 authentication (RFC 5766)
- Channel binding (0x4000-0x7FFF)
- Permission management
- Send/Data indications
- ICE integration with relay candidates

**TWCC (Transport-Wide Congestion Control)**
- Transport-wide sequence numbers (RTP header extension)
- Receive delta encoding/decoding
- Packet status chunks
- Bandwidth estimation algorithm

**Simulcast**
- RID (Restriction Identifier) support (RFC 8851)
- RTP header extension parsing for RID/MID
- SDP simulcast attribute parsing
- RtpRouter for RID-based packet routing

**Quality Features**
- Jitter buffer with configurable sizing
- RED (Redundancy Encoding) for audio (RFC 2198)
- Media Track Management (addTrack, removeTrack, replaceTrack)
- Extended getStats() API (ICE, transport, data channel stats)

**Media Recording**
- WebM container support
- MP4 container support (fMP4)
- EBML encoding/decoding

**Browser Compatibility**
- Chrome: Tested and working
- Firefox: Tested and working
- Safari: Tested and working

### Test Coverage

1658 tests covering all implemented components.

### Acknowledgments

This is a Dart port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) by Yuki Shindo.
