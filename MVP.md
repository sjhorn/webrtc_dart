# MVP Definition - webrtc_dart

## Scope Decision

**Target:** Both datachannel + audio support

This MVP will implement:
- **Data Channels**: Text/binary messaging over SCTP
- **Audio**: Single audio track with Opus codec support

This provides a complete WebRTC experience while keeping scope manageable by limiting to one audio codec and deferring video.

## Platform Target

**Primary Platform:** Dart VM (server/CLI)

Starting with pure Dart VM provides:
- Fastest development iteration
- Easiest debugging (no platform channel complexity)
- Server-side WebRTC use cases
- Foundation for later Flutter platform support

Flutter platforms (Desktop/Mobile) can be added in subsequent phases once core implementation is stable.

## Interop Target

**Primary Validation:** TypeScript werift-webrtc

Testing against the original TypeScript implementation:
- Validates accuracy of the port
- Ensures behavioral compatibility
- Allows direct comparison of packet formats and state machines
- Both peers can be run locally for debugging

**Validation Goal:**
1. Establish connection between Dart and TypeScript peers
2. Exchange "hello world" message over datachannel
3. Transmit/receive basic audio stream (Opus)

## Implementation Phases for MVP

### Phase 1: Foundations (Step 3)
- Binary helpers (Uint8List/ByteData wrappers)
- Crypto primitives (AES, HMAC via package:cryptography)
- Packet base classes

### Phase 2: Network Layer (Steps 4-5)
- STUN message encoding/decoding
- ICE agent (candidate gathering, connectivity checks)
- Basic UDP transport

### Phase 3: Security Layer (Steps 6-7)
- DTLS handshake
- SRTP/SRTCP implementation

### Phase 4: Media & Data (Steps 8-9)
- RTP/RTCP stack
- SCTP over DTLS
- Data channel protocol
- Opus codec integration

### Phase 5: Signaling & API (Step 10)
- SDP parsing/generation
- Public PeerConnection API

### Validation Checkpoints

After each phase:
- Unit tests with captured TypeScript outputs
- Golden tests for binary formats
- Interop test: Dart ↔ TypeScript werift-webrtc

**Final MVP Validation:**
```
┌─────────────────┐         ┌─────────────────┐
│   Dart Peer     │ ←──────→│ TypeScript Peer │
│  (CLI App)      │   ICE   │  (werift-webrtc)│
│                 │  DTLS   │                 │
│ • Datachannel ──┼────────→│ • Datachannel   │
│ • Audio (Opus) ─┼────────→│ • Audio (Opus)  │
└─────────────────┘         └─────────────────┘
```

Test scenarios:
1. Dart sends "hello" via datachannel → TypeScript receives and echoes
2. TypeScript streams audio → Dart receives and decodes
3. Dart streams audio → TypeScript receives and plays

## Success Criteria

MVP is complete when:
- [x] Dart peer can establish connection with TypeScript peer
- [x] Bidirectional datachannel messages work reliably
- [x] Audio can be sent from Dart → TypeScript (local bidirectional audio validated)
- [x] Audio can be received from TypeScript → Dart (local bidirectional audio validated)
- [x] Connection is stable for at least 60 seconds (validated via examples)
- [x] All unit tests pass
- [x] Code follows Dart style guide
- [x] Basic documentation exists for API usage

## Out of Scope for MVP

Deferred to future phases:
- Video support
- Multiple audio/video tracks
- Simulcast
- Advanced RTCP feedback (BWE, etc.)
- Flutter platform implementations
- Browser interop
- TURN server support (start with STUN only)
- Advanced codec support (H.264, VP8, VP9, AV1)

## Next Steps

Now that scope is defined, proceed to:
- **Step 2**: Define architecture and module layout
- **Step 3**: Implement binary & crypto foundations
