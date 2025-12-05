# WebRTC Signaling Examples

These examples demonstrate WebRTC connections using WebSocket signaling.

## Files

- `signaling_server.dart` - Simple WebSocket signaling server
- `offer.dart` - Dart WebRTC peer that creates offers
- `answer.dart` - Dart WebRTC peer that answers offers
- `answer.html` - Browser-based answerer (works with Dart offer)

## Usage

### Dart-to-Dart

1. Start the signaling server:
   ```bash
   dart run examples/signaling/signaling_server.dart
   ```

2. In another terminal, start the offer:
   ```bash
   dart run examples/signaling/offer.dart
   ```

3. In another terminal, start the answer:
   ```bash
   dart run examples/signaling/answer.dart
   ```

### Dart-to-Browser

1. Start the signaling server:
   ```bash
   dart run examples/signaling/signaling_server.dart
   ```

2. Start the Dart offer:
   ```bash
   dart run examples/signaling/offer.dart
   ```

3. Open `examples/signaling/answer.html` in a browser and click "Connect"

## How It Works

1. Both peers connect to the signaling server
2. The offer peer:
   - Creates a PeerConnection
   - Creates a DataChannel
   - Generates an SDP offer
   - Sends the offer (with ICE candidates) via signaling
   - Receives the answer via signaling
   - Establishes the connection

3. The answer peer:
   - Creates a PeerConnection
   - Receives the offer via signaling
   - Generates an SDP answer
   - Sends the answer (with ICE candidates) via signaling
   - Receives the incoming DataChannel
   - Establishes the connection

4. Once connected, the peers exchange ping/pong messages

## Custom Signaling Server URL

Both offer and answer accept a signaling server URL as an argument:

```bash
dart run examples/signaling/offer.dart ws://my-server:9999
dart run examples/signaling/answer.dart ws://my-server:9999
```
