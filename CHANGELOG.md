# Changelog

All notable changes to this project will be documented in this file.

## 0.25.3

### Fixed

- **SDP (Session Description Protocol) MID allocation** - Unified MID (Media Identification) allocation to prevent duplicate `a=mid` values in offers. Transceivers and data channels now share a single counter.

- **SDP m-line order preserved** - Re-offers (e.g., for ICE restart) now preserve the established m-line order per RFC 3264, fixing "m-line order doesn't match" errors from browsers.

- **Data channel MID caching** - Data channel MID is now cached and reused across offers, preventing MID changes during ICE (Interactive Connectivity Establishment) restart.

- **ICE restart detection** - Remote ICE restart is now only detected on incoming offers, not answers. Previously, receiving a restart answer incorrectly triggered a second restart, causing state to reset.

### Added

- **Configurable timing options** - `RtcConfiguration` now accepts optional timing parameters:
  - `certificate` - Pre-generated certificate to reuse (saves 50-200ms)
  - `icePacingInterval` - Interval between ICE checks (default 5ms)
  - `stunTimeout` - STUN request timeout (default 1500ms)
  - `dtlsHandshakeTimeout` - DTLS (Datagram Transport Layer Security) handshake timeout (default 30s)
  - `dtlsFlightTimeout` - DTLS flight retransmission timeout (default 500ms)

### Performance

- **Reduced default timeouts** - ICE pacing reduced from 20ms to 5ms, STUN timeout from 3s to 1.5s, DTLS flight timeout from 1000ms to 500ms for faster connection establishment.

### Improved

- **README acronym clarity** - All technical acronyms now include expanded names on first use (e.g., "SRTP (Secure Real-time Transport Protocol)").

## 0.25.2

### Fixed

- **ICE credential sharing for bundlePolicy:disable** - All media transports now share the same ice-ufrag/ice-pwd credentials, matching werift behavior. Required for Ring camera compatibility.

- **XOR-MAPPED-ADDRESS encoding (RFC 5389)** - Fixed XOR pad to use 6-byte prefix `[0x21, 0x12, 0x21, 0x12, 0xa4, 0x42]` for correct port and IPv4 address XOR alignment, matching werift implementation.

- **Socket tracking for STUN responses** - STUN binding responses are now sent from the same socket that received the request, critical for NAT traversal. Previously could select wrong socket (e.g., 192.168.205.1 instead of 192.168.1.200).

- **MID numbering starts at 0** - Transceiver MIDs now start at 0 instead of 1, matching werift and browser behavior.

### Improved

- **SDP generation closer to werift** - Added `msid`, `ice-options: trickle`, `extmap-allow-mixed`, and `msid-semantic` attributes for better compatibility.

- **ICE socket error handling** - Added `onError` handler for async socket errors; consolidated error handling in `_trySendDatagram` helper.

- **Test reliability under parallel execution** - Event-driven waiting, trickle ICE, increased timeouts, and retry logic for resource-intensive integration tests.

## 0.25.1

### Fixed

- **DTLS server handles retransmitted ClientHello** - When HelloVerifyRequest is lost due to packet loss, client retransmits its original ClientHello (no cookie). Server now correctly re-sends HelloVerifyRequest instead of throwing "Unexpected first ClientHello" error. Per RFC 6347, matches werift behavior.

### Tests

- Added regression test for DTLS retransmission scenario
- Added `SelectiveDropTransport` and `ReplayFirstPacketTransport` test utilities

## 0.25.0

### Added

- **RTCP Extended Reports (XR) - RFC 3611** - Full implementation of RTCP XR (PT=207):
  - `RtcpExtendedReport` - Main XR packet wrapper
  - `ReceiverReferenceTimeBlock` (BT=4) - Enables RTT for non-senders
  - `DlrrBlock` (BT=5) - Delay Since Last Receiver Report for RTT calculation
  - `StatisticsSummaryBlock` (BT=6) - Aggregate QoS metrics
  - 33 new tests for XR parsing/serialization
  - 3 new XR performance tests

### Performance

- **DataChannel timing matches werift** - Changed SCTP `sendData()` to use fire-and-forget `_transmit()`, eliminating blocking in `DataChannel.send()` and `open()`

### Fixed

- **DTLS race condition** - Await initialization in `setRemoteDescription` to prevent DTLS handshake race
- **RTCP lenient handling** - Skip unknown RTCP packet types gracefully (matches werift behavior)
- **Test stability** - Tagged flaky concurrent tests as `slow` for isolated execution

### Tests

- 2661 tests passing (including 41 performance tests)

## 0.24.0

### Performance

- **ICE candidate parsing 2.8x faster** - Replaced `split()` with `indexOf()` + `substring()`:
  - Host candidate: 1.8M → 5.0M ops/sec
  - Round-trip: 1.4M → 2.8M ops/sec
  - Gap vs werift reduced from 7x to 2.6x

- **Codec parameter parsing optimized** - `RTCRtpCodecParameters.name` and `.contentType` now use `indexOf()` instead of `split('/')` to avoid List allocation

### Added

- **Performance regression test suite** - 38 new tests in `test/performance/`:
  - SRTP encrypt/decrypt throughput
  - RTP/RTCP parse/serialize
  - SDP parse/serialize
  - STUN message handling
  - SCTP queue operations
  - DTLS anti-replay window
  - VP8/H.264 depacketization
  - ICE candidate parse/serialize

- **Benchmark infrastructure** - Compare webrtc_dart vs werift:
  - `./benchmark/run_perf_tests.sh` - Run Dart performance tests
  - `./benchmark/run_werift_benchmarks.sh` - Run werift comparison
  - `./benchmark/compare.sh` - Side-by-side comparison
  - Micro-benchmarks in `benchmark/micro/`

### Tests

- 2625 tests passing (including 38 performance tests)

## 0.23.1

### Changed

- **Documentation clarity** - Clarified server-side WebRTC positioning:
  - README: Explicitly positioned as server-side library (like Pion, aiortc, werift)
  - Added comparison table: browser WebRTC vs server-side capabilities
  - Removed misleading "W3C API compatibility" claims
  - Clarified that media capture and codec encoding/decoding require external tools

### Tests

- 2587 tests passing

## 0.23.0

### Breaking Changes (with backward compatibility)

- **W3C WebRTC API naming** - All core classes renamed to match W3C standard:
  - `RtcPeerConnection` -> `RTCPeerConnection`
  - `DataChannel` -> `RTCDataChannel`
  - `RtpTransceiver` -> `RTCRtpTransceiver`
  - `RtpSender` -> `RTCRtpSender`
  - `RtpReceiver` -> `RTCRtpReceiver`
  - `Candidate` -> `RTCIceCandidate`
  - `SessionDescription` -> `RTCSessionDescription`

- **Backward compatibility preserved** - Old names available via deprecated typedefs. Existing code continues to work with deprecation warnings.

### Added

- **RTCDTMFSender** - Full DTMF (Dual-Tone Multi-Frequency) support:
  - `insertDTMF()` method with configurable duration and gap
  - `toneBuffer` property for queued tones
  - `ontonechange` event callback
  - `canInsertDTMF` property
  - Supports tones: 0-9, A-D, *, #
  - RTP telephone-event payload (RFC 4733)

- **W3C property aliases** - Standard naming alongside Dart conventions:
  - `RTCDataChannel.id` (alias for `streamId`)
  - `RTCDataChannel.readyState` (alias for `state`)
  - `RTCIceCandidate.address` (alias for `host`)
  - `RTCIceCandidate.protocol` (alias for `transport`)
  - `RTCIceCandidate.usernameFragment` (alias for `ufrag`)
  - `MediaStreamTrack.readyState` (alias for `state`)

- **Missing W3C methods**:
  - `RTCRtpSender.replaceTrack()` - Replace track without renegotiation
  - `RTCRtpSender.getStats()` - Per-sender statistics
  - `RTCRtpReceiver.getParameters()` - Receiver RTP parameters
  - `RTCRtpReceiver.getStats()` - Per-receiver statistics
  - `RTCRtpTransceiver.currentDirection` - Actual negotiated direction
  - `RTCIceCandidate.toJSON()` - JSON serialization
  - `RTCSessionDescription.toJSON()` - JSON serialization

- **MediaStreamTrack constraints API**:
  - `getSettings()` - Current track settings
  - `getCapabilities()` - Device capabilities
  - `getConstraints()` - Applied constraints
  - `applyConstraints()` - Apply new constraints

- **Transport properties**:
  - `RTCRtpSender.transport` - DTLS transport reference
  - `RTCRtpReceiver.transport` - DTLS transport reference

### Changed

- All examples updated to use W3C API names
- All tests updated to use W3C API names (no deprecation warnings)
- Documentation updated for W3C API focus
- Merged W3C_COMPAT_PLAN.md and REFACTOR.md into ROADMAP.md

### Tests

- 2587 tests passing (up from 2537)
- Added DTMF unit tests (12 tests)
- Added browser interop tests for DTMF
- All browser interop tests passing (Chrome, Firefox, Safari)

### Clarification

webrtc_dart is a **server-side** WebRTC library. It provides W3C-compatible API
naming (RTCPeerConnection, etc.) for the WebRTC transport layer. As with other
server-side implementations (Pion, aiortc, werift), media capture (getUserMedia)
and codec encoding/decoding require external tools like FFmpeg or GStreamer.

## 0.22.14

### Fixed

- **RTP sender stream replay** - Fixed SSRC handling when replaying streams (matching werift's `replaceRTP` pattern):
  - Added `onSourceChanged` subscription to reset SSRC tracking on source change
  - Changed SSRC filtering to accept new SSRCs instead of dropping packets
  - Enables seamless replay of media streams without reconnection

### Tests

- 2537 tests passing

## 0.22.13

### Fixed

- **SCTP flow control improvements** - Multiple fixes for real-time streaming:
  - Non-blocking `sendData()`: Removed blocking that caused complete stalls when T3 timer was running
  - Congestion window check for new chunks: Added missing cwnd check in `_transmit()` to prevent flooding
  - First SACK handling: Fixed `_lastSackedTsn` to be nullable, accepting first SACK correctly
  - Increased initial cwnd from 4380 to 65536 bytes for better real-time performance

### Added

- **DataChannel bufferedAmount API** - Per W3C WebRTC spec:
  - `bufferedAmount`: Returns bytes queued but not yet ACKed (tracked at SCTP level per-stream)
  - `bufferedAmountLowThreshold`: Configurable threshold for flow control
  - `onBufferedAmountLow`: Event fires when buffer drains below threshold
  - Applications can wait for `bufferedAmount == 0` before disconnecting to ensure all data is delivered

### Tests

- 2537 tests passing

## 0.22.12

### Fixed

- **SCTP fragment reassembly** - Fixed critical bug where fragmented SCTP messages (>1024 bytes) were silently dropped. DataChannel messages larger than `userDataMaxLength` (1024 bytes) are now properly reassembled from multiple DATA chunks.
- **Forward TSN reassembly integration** - Added missing reassembly logic to `_handleForwardTsn`: advances stream sequence numbers, delivers pending messages, and prunes obsolete chunks from all inbound streams.

### Added

- **InboundStream class** - New `lib/src/sctp/inbound_stream.dart` implementing per-stream fragment reassembly matching werift's `InboundStream` pattern. Handles ordered/unordered delivery, out-of-order chunks, and TSN wraparound.

### Tests

- Added 8 fragment reassembly tests covering: unfragmented, 2/3-fragment, out-of-order, multiple messages, missing fragments, duplicates, large messages
- 2537 tests passing

## 0.22.11

### Fixed

- **DTLS close race condition** - Fixed "Cannot add to a closed controller" error when browser disconnects during async processing. Added double-check guard (`!isClosed && !errorController.isClosed`) before all `errorController.add()` calls in socket.dart, server.dart, and client.dart.

### Tests

- Added regression test: "close during async processing does not throw"
- 2434 tests passing

## 0.22.10

### Fixed

- **Return audio for bundlePolicy:disable** - Fixed three issues preventing return audio from reaching Ring cameras:
  - MID migration bug: `_mediaTransports` map wasn't updated when Ring's SDP answer migrates MIDs
  - Closure capture bug: `onSendRtp`/`onSendRtcp` callbacks captured mid at creation time instead of looking up dynamically
  - Codec payload type bug: Sender's `codec.payloadType` wasn't updated from SDP answer, causing PT mismatch
- **ICE connectivity for bundlePolicy:disable** - Improved candidate pair priority for separate audio/video transports

### Added

- **debugLabel for IceToDtlsAdapter** - Helps trace which transport receives DTLS packets during debugging
- **Public export for nonstandard MediaStreamTrack** - Enables custom track implementations

### Tests

- 2433 tests passing (up from 2431)
- All browser interop tests passing on Chrome, Firefox, Safari

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
