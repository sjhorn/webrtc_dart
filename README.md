# webrtc_dart

A pure Dart implementation of WebRTC protocols, ported from [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc).

## Project Status

This is an in-progress port of WebRTC to Dart. Current implementation status:

### ✅ Completed Components

#### Phase 1-2: Foundations & Network Layer
- **STUN** - RFC 5389 implementation
  - Message encoding/decoding
  - Attribute handling (XOR-MAPPED-ADDRESS, etc.)
  - Authentication with MESSAGE-INTEGRITY
- **ICE** - RFC 5245 implementation
  - Candidate gathering (host, server-reflexive)
  - Connectivity checks with STUN binding
  - Candidate pair management and nomination
  - ICE agent state machine
  - Bidirectional data transport over nominated pairs

#### Phase 3: Security Layer
- **DTLS** - RFC 6347 implementation
  - Full DTLS 1.2 handshake (client & server)
  - Certificate generation and verification
  - Cipher suites (AES-128-GCM, AES-256-GCM)
  - Session resumption
  - Fragmentation and retransmission
- **SRTP/SRTCP** - RFC 3711 implementation
  - AES-GCM encryption for RTP/RTCP
  - Replay protection
  - Key derivation
  - ROC (Rollover Counter) tracking

#### Phase 4: Media & Data
- **RTP/RTCP** - RFC 3550 implementation
  - RTP packet handling
  - RTCP Sender/Receiver Reports (SR/RR)
  - Statistics tracking (jitter, packet loss)
  - SSRC management
- **SCTP** - RFC 4960 implementation
  - Packet structure with CRC32c
  - All chunk types (DATA, INIT, SACK, etc.)
  - Association state machine
  - Stream management
- **DataChannel** - RFC 8831/8832 implementation
  - DCEP (Data Channel Establishment Protocol)
  - Channel types (reliable/unreliable, ordered/unordered)
  - String and binary message support
- **Opus Codec** - RFC 7587
  - RTP payload format
  - Codec parameters
  - OpusHead generation

#### Phase 5: Signaling & API
- **SDP** - RFC 4566/8866 implementation
  - Full SDP parsing
  - SDP generation
  - Media descriptions
  - Attribute handling
- **PeerConnection API**
  - W3C WebRTC-compatible API
  - Offer/answer exchange
  - ICE candidate handling
  - State machine management
  - Event streams

#### Phase 6: Integration Layer
- **Transport Integration** - Full protocol stack connectivity
  - ICE → DTLS → SCTP data flow
  - Automatic DTLS handshake on ICE connection
  - SCTP association over encrypted DTLS channel
  - End-to-end integration testing

### 📋 Not Yet Implemented

- TURN support (STUN only currently)
- Video codecs (H.264, VP8, VP9)
- Media track management
- Statistics API (getStats)
- Browser interoperability

## Test Coverage

**536 tests passing** covering all implemented components:

- STUN: 35 tests
- ICE: 49 tests (including local connection tests)
- DTLS: 89 tests (including integration tests)
- SRTP: 23 tests
- RTP/RTCP: 54 tests
- SCTP: 22 tests
- DataChannel: 10 tests
- SDP: 10 tests
- PeerConnection: 22 tests
- Codecs: 23 tests
- Component Integration: 9 tests
- **Full Stack Integration: 2 tests** (ICE + DTLS + SCTP + DataChannel E2E)

## Examples

### Local DataChannel

Demonstrates offer/answer exchange between two local peer connections:

```bash
dart run examples/datachannel_local.dart
```

## Architecture

The implementation follows a layered protocol stack:

```
┌─────────────────────────────────────┐
│      PeerConnection API             │  W3C WebRTC API
├─────────────────────────────────────┤
│  DataChannel  │  Media Tracks       │  Application Layer
├───────────────┴─────────────────────┤
│  SCTP         │  RTP/RTCP + SRTP    │  Transport Layer
├───────────────┴─────────────────────┤
│           DTLS (Security)           │  Security Layer
├─────────────────────────────────────┤
│          ICE (Connectivity)         │  Network Layer
├─────────────────────────────────────┤
│          STUN (Discovery)           │  Discovery Layer
└─────────────────────────────────────┘
```

## Development

### Running Tests

```bash
# Run all tests
dart test

# Run specific test suite
dart test test/ice/
dart test test/dtls/
dart test test/peer_connection_test.dart

# Run with coverage
dart test --coverage=coverage
```

### Code Structure

```
lib/src/
├── stun/          # STUN protocol
├── ice/           # ICE agent and candidates
├── dtls/          # DTLS handshake and encryption
├── srtp/          # SRTP/SRTCP encryption
├── rtp/           # RTP/RTCP media transport
├── sctp/          # SCTP reliable transport
├── datachannel/   # DataChannel API
├── codec/         # Codec implementations
├── sdp/           # SDP parsing and generation
└── peer_connection.dart  # Main PeerConnection API
```

## Comparison with werift-webrtc

This implementation closely follows the TypeScript werift-webrtc architecture:

| Feature | werift-webrtc | webrtc_dart | Status |
|---------|---------------|-------------|--------|
| ICE | ✅ | ✅ | Complete |
| DTLS | ✅ | ✅ | Complete |
| SRTP | ✅ | ✅ | Complete |
| SCTP | ✅ | ✅ | Complete |
| DataChannel | ✅ | ✅ | Complete |
| RTP/RTCP | ✅ | ✅ | Complete |
| Opus | ✅ | ✅ | Complete |
| SDP | ✅ | ✅ | Complete |
| PeerConnection | ✅ | ✅ | Complete |
| Integration | ✅ | 🚧 | In Progress |
| Video Codecs | ✅ | ❌ | Not Started |

## MVP Goal

The Minimum Viable Product goal is to:

1. ✅ Establish connection between Dart peer and TypeScript werift-webrtc peer
2. ✅ Exchange "hello world" message over datachannel (see test/integration/datachannel_e2e_test.dart)
3. 🚧 Transmit/receive basic audio stream (Opus)

## License

MIT

## Acknowledgments

This project is a Dart port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) by Yuki Shindo.
