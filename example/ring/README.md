# Ring Camera Streaming Example

Stream video from Ring doorbell cameras to a web browser using webrtc_dart.

This is a Dart port of [werift-webrtc/examples/ring](../../werift-webrtc/examples/ring/).

## Architecture

```
Ring Camera → webrtc_dart server → Browser
     ↓              ↓                  ↓
  RTP/SRTP    nonstandard track    video element
  (CTR mode)     writeRtp()        (H264 frames)
```

## Quick Start

### 1. Install Dependencies

```bash
cd example/ring
dart pub get
```

### 2. Configure Environment

Copy the example `.env` file and add your Ring refresh token:

```bash
# Get refresh token via ring_client_api CLI
dart run ring_client_api:ring_auth_cli
```

Edit `.env`:
```
RING_REFRESH_TOKEN=your_token_here
```

### 3. Run the Server

```bash
./run.sh
```

Or manually:
```bash
source .env
dart run recv-via-webrtc.dart
```

### 4. View in Browser

Open http://localhost:8080 in Chrome or Safari.

## Files

```
example/ring/
├── recv-via-webrtc.dart   # Main server (matches werift recv-via-webrtc.ts)
├── peer.dart              # CustomPeerConnection (matches werift peer.ts)
├── run.sh                 # Simple runner script
├── .env                   # Ring credentials (not committed)
├── pubspec.yaml           # Dependencies
└── README.md              # This file
```

## How It Works

1. **Ring Connection**: Server connects to Ring camera via `ring_client_api`
2. **Video Forwarding**: RTP packets from Ring are forwarded via `MediaStreamTrack.writeRtp()`
3. **Browser Streaming**: Server creates WebRTC offer, browser answers, video displays

### Key Components

**CustomPeerConnection** (`peer.dart`):
- Implements `ring.BasicPeerConnection` interface
- Uses `bundlePolicy: disable` (Ring requirement)
- SRTP cipher: `srtpAes128CmHmacSha1_80` (AES-CTR mode)
- Exposes `onVideoRtp` stream for packet forwarding

**Browser Connection**:
- Standard WebRTC with `bundlePolicy: maxBundle`
- SRTP cipher: `srtpAeadAes128Gcm` (AES-GCM mode)
- H264 video codec with full RTCP feedback

## Troubleshooting

### No video in browser
- Check browser console for errors
- Ensure Ring camera is online in Ring app
- Try Chrome (Firefox headless lacks H264 support)

### Refresh token expired
```bash
dart run ring_client_api:ring_auth_cli
# Update .env with new token
```

### ICE connection failed
- Ring requires STUN servers for NAT traversal
- Server automatically uses AWS Kinesis and Google STUN servers

## Development Notes

### Bug Fix: GCM Extension Headers (December 2025)

The main bug that prevented video from displaying was that AES-GCM SRTP wasn't including RTP extension headers in AAD (Additional Authenticated Data). This caused GCM authentication to fail on the browser side.

**Fix**: `lib/src/srtp/srtp_cipher.dart` - `_serializeHeader()` now uses `packet.serializeHeader()` which correctly includes extension headers.

**Tests**: See `test/srtp/srtp_rfc7714_test.dart` for regression tests.

## References

- [ring_client_api](https://pub.dev/packages/ring_client_api) - Dart Ring integration
- [werift-webrtc Ring example](../../werift-webrtc/examples/ring/) - Original TypeScript
- [RFC 7714](https://tools.ietf.org/html/rfc7714) - AES-GCM for SRTP
