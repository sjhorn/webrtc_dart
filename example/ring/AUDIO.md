# Adding Audio to Ring Example (Dart)

This document describes what is needed to receive audio from a Ring camera in addition to video.

## Implementation Status

### COMPLETE (2025-12-13)

All audio and video functionality is now working end-to-end:

- **Ring audio stream activation** - `liveCall.activateCameraSpeaker()` successfully enables audio
- **Audio RTP reception** - Audio RTP packets received from Ring (~125 packets/sec, 8kHz PCMU)
- **Codec negotiation** - PCMU codec at 8kHz with static payload type 0
- **Browser forwarding** - Both video AND audio play in browser
- **Multi-track handling** - Combined MediaStream approach for audio + video
- **Video autoplay** - Muted video autoplays, click button to enable audio
- **Keyframe on connect** - PLI sent to Ring when browser connects for immediate video
- **Encrypted PLI** - SRTCP encryption for PLI packets (required by Ring)

### Testing

```bash
# Automated Playwright test
./run_browser_test.sh chrome

# Manual browser test
./start_server.sh
# Open http://localhost:8080 in browser

# Enable verbose logging
RING_DEBUG=1 ./start_server.sh
```

---

## Changes Made

### 1. recv_via_webrtc.dart

```dart
// Create both video and audio tracks
final videoTrack = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
final audioTrack = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.audio);

// Subscribe to audio RTP
_ringPc!.onAudioRtp.listen((rtp) {
  for (final client in _state.browserClients.values) {
    if (client.connected) {
      client.audioTrack.writeRtp(rtp);
    }
  }
});

// Activate camera speaker to receive audio from Ring
_ringSession = await camera.startLiveCall(
  ring.StreamingConnectionOptions(createPeerConnection: () => _ringPc!),
);
_ringSession!.activateCameraSpeaker();

// Add audio codec and transceiver for browser
final pc = RtcPeerConnection(
  RtcConfiguration(
    codecs: RtcCodecs(
      audio: [createPcmuCodec()],  // PCMU at 8kHz, PT=0
      video: [createH264Codec(payloadType: 96)],
    ),
  ),
);

// Add audio first, then video (order matters for BUNDLE)
client.audioTransceiver = pc.addTransceiverWithTrack(
  audioTrack,
  direction: RtpTransceiverDirection.sendonly,
);
client.videoTransceiver = pc.addTransceiverWithTrack(
  videoTrack,
  direction: RtpTransceiverDirection.sendonly,
);
```

### 2. peer.dart

The `CustomPeerConnection` has:
- `onAudioRtp` and `onAudioRtcp` streams
- PCMU codec configuration
- Audio transceiver with `sendrecv` direction
- `returnAudioTrack` for two-way audio (sending to Ring)
- `requestKeyFrame()` method to send PLI to Ring
- Periodic PLI timer (every 2 seconds)

```dart
// Request keyframe from Ring via PLI
void requestKeyFrame() {
  if (_videoMediaSsrc != null && _videoTransceiver != null) {
    _videoTransceiver!.receiver.rtpSession.sendPli(_videoMediaSsrc!);
  }
}
```

### 3. lib/src/peer_connection.dart

Fixed SRTP session assignment for `bundlePolicy: disable`:

```dart
// Before (broken): matched by transceiver.transport which was never set
if (transceiver.transport?.id == transport.id)

// After (fixed): match by MID since transport.id == mid for bundlePolicy:disable
if (transceiver.mid == transport.id)
```

This was critical for PLI encryption - without SRTP session, PLI was sent unencrypted and Ring ignored it.

---

## Key Learnings

### 1. activateCameraSpeaker() is Required

Ring cameras stream in "stealth mode" by default (video only). To receive audio:

```dart
final liveCall = await camera.startLiveCall(...);
liveCall.activateCameraSpeaker();  // Sends camera_options with stealth_mode: false
```

### 2. Audio Codec is PCMU

Ring cameras use PCMU (G.711 mu-law) at 8kHz, mono. This is standard telephony audio.

SDP from Ring shows:
```
m=audio 9 UDP/TLS/RTP/SAVPF 0
a=rtpmap:0 PCMU/8000
```

### 3. PCMU Requires Static Payload Type 0

**Critical**: PCMU codec MUST use payload type 0 (RFC 3551). Without this, browsers reject the audio.

### 4. Browser Autoplay Policy

Browsers block audio playback without user interaction. Solutions:
- Add a button that calls `video.play()`
- Use `muted` initially, then unmute after user click

### 5. Combined MediaStream for Multiple Tracks

When receiving multiple tracks (audio + video), combine them into one MediaStream:

```javascript
// CORRECT - combine all tracks into one MediaStream
const combinedStream = new MediaStream();
pc.ontrack = (e) => {
  combinedStream.addTrack(e.track);
  video.srcObject = combinedStream;
};
```

### 6. Keyframe Request via PLI

H.264 video requires a keyframe (I-frame) to start decoding. Request one when browser connects:

```dart
// When browser connects
if (state == PeerConnectionState.connected) {
  _ringPc!.requestKeyFrame();
}
```

### 7. PLI Must Be Encrypted (SRTCP)

**Critical fix**: Ring requires all RTCP packets (including PLI) to be encrypted with SRTCP.
The SRTP session must be assigned to the RtpSession before calling `sendPli()`.

### 8. sdpMLineIndex for bundlePolicy: disable

With `bundlePolicy: disable`, Ring uses separate transports per media line. ICE candidates MUST include the correct `sdpMLineIndex`:

```dart
// WRONG - component is always 1
sdpMLineIndex: candidate.component

// CORRECT - use the m-line index
sdpMLineIndex: candidate.sdpMLineIndex ?? 0
```

---

## Architecture Notes

With `bundlePolicy: disable`, Ring uses **separate ICE/DTLS transports**:
- **mid=1**: Audio transport (PCMU 8kHz, direction=sendrecv)
- **mid=2**: Video transport (H.264, direction=sendonly)

Both transports need to:
1. Complete ICE connectivity checks independently
2. Complete DTLS handshake independently
3. Derive separate SRTP keys for encryption/decryption

---

## Remaining Work

### Two-Way Audio (Future)

The infrastructure exists (`returnAudioTrack`, `sendrecv` direction) but requires:
1. Capture browser microphone via `getUserMedia()`
2. Transcode browser Opus to PCMU for Ring
3. Send audio RTP back through WebSocket

---

## References

- [ring-client-api GitHub](https://github.com/dgreif/ring)
- [StreamingSession.activateCameraSpeaker()](https://github.com/dgreif/ring/blob/main/packages/ring-client-api/streaming/streaming-session.ts)
- TypeScript werift example: `werift-webrtc/examples/ring/`
