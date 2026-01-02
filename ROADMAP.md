# webrtc_dart Roadmap

## Current Status (v0.23.0)

webrtc_dart has achieved **100% feature parity** with werift-webrtc and **full W3C WebRTC API compatibility**.

### Achievements

| Category | Status |
|----------|--------|
| **W3C API Names** | RTCPeerConnection, RTCDataChannel, RTCIceCandidate, etc. |
| **Werift Parity** | 100% feature complete |
| **Browser Interop** | Chrome, Firefox, Safari all working |
| **Test Coverage** | 2587 tests passing |

### W3C WebRTC API Compatibility

All standard interfaces implemented with W3C naming:

| Interface | Status |
|-----------|--------|
| `RTCPeerConnection` | Full API |
| `RTCDataChannel` | Full API + `id`, `readyState` |
| `RTCRtpTransceiver` | Full API + `currentDirection` |
| `RTCRtpSender` | Full API + `dtmf`, `replaceTrack()` |
| `RTCRtpReceiver` | Full API + `getParameters()` |
| `RTCIceCandidate` | Full API + `toJSON()` |
| `RTCSessionDescription` | Full API + `toJSON()` |
| `RTCDTMFSender` | Full implementation |
| `MediaStreamTrack` | Full API + constraints |

### Protocol Support

| Protocol | Coverage |
|----------|----------|
| **ICE** | Full RFC 8445 + consent freshness (RFC 7675) + TCP + mDNS |
| **DTLS** | ECDHE-ECDSA/RSA with AES-GCM, AES-256, ChaCha20 |
| **SRTP** | AES-CM-128, AES-GCM with replay protection |
| **SCTP** | Partial reliability (RFC 3758), stream reconfig (RFC 6525) |
| **RTP/RTCP** | SR, RR, SDES, BYE, NACK, PLI, FIR, REMB, TWCC |

### Codec Support

| Type | Codecs |
|------|--------|
| Video | VP8, VP9 (SVC), H.264, AV1 |
| Audio | Opus, RED |

---

## Future Roadmap

### Short-term Priorities

- **Performance optimization** - Reduce CPU usage for high-throughput scenarios
- **Memory management** - Optimize buffer allocation patterns
- **Documentation** - Expand API documentation and tutorials

### Medium-term Goals

- **Insertable Streams** - RTCRtpScriptTransform for E2E encryption
- **ICE-LITE** - Lightweight ICE for server-side deployments
- **SVC extensions** - Enhanced VP9/AV1 spatial/temporal layer control

### Long-term Vision

- **Flutter integration** - First-class platform channel bindings
- **WebTransport** - HTTP/3 QUIC-based transport
- **WHIP/WHEP** - WebRTC-HTTP ingestion/egress protocols

---

## Backward Compatibility

v0.23.0 maintains full backward compatibility via deprecated typedefs:

```dart
// Old names still work (with deprecation warnings)
@Deprecated('Use RTCPeerConnection instead')
typedef RtcPeerConnection = RTCPeerConnection;

@Deprecated('Use RTCDataChannel instead')
typedef DataChannel = RTCDataChannel;
```

Users can migrate incrementally to W3C API names.

---

## Architecture

### Package Structure

```
lib/src/
  ice/          - ICE transport, candidate handling
  dtls/         - DTLS handshake and record layer
  srtp/         - SRTP/SRTCP encryption
  rtp/          - RTP/RTCP stack
  sctp/         - SCTP transport, data channels
  sdp/          - SDP parsing and generation
  media/        - Tracks, transceivers, DTMF
  codec/        - VP8, VP9, H.264, AV1, Opus
  stats/        - getStats() implementation
```

### Layered Design

```
RTCPeerConnection API
        |
   SDP Manager
        |
  RTP/RTCP Stack
        |
   SRTP/SRTCP
        |
      DTLS
        |
      ICE
        |
   UDP/TCP Sockets
```

---

## References

- [W3C WebRTC Specification](https://www.w3.org/TR/webrtc/)
- [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) - Original TypeScript implementation
- [MDN WebRTC API](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API)
