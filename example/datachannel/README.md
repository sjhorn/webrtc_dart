# DataChannel Examples

These examples demonstrate WebRTC DataChannel connections using WebSocket signaling.

## Files

- `signaling_server.dart` - Simple WebSocket signaling server
- `offer.dart` - Dart WebRTC peer that creates offers
- `answer.dart` - Dart WebRTC peer that answers offers
- `answer.html` - Browser-based answerer (works with Dart offer)
- `local.dart` - Local DataChannel test (two peers, same process)
- `string.dart` - String message DataChannel example
- `manual.dart` - Manual offer/answer exchange example
- `quickstart.dart` - Simple quickstart DataChannel example

## Usage

### Dart-to-Dart

1. Start the signaling server:
   ```bash
   dart run example/datachannel/signaling_server.dart
   ```

2. In another terminal, start the offer:
   ```bash
   dart run example/datachannel/offer.dart
   ```

3. In another terminal, start the answer:
   ```bash
   dart run example/datachannel/answer.dart
   ```

### Dart-to-Browser

1. Start the signaling server:
   ```bash
   dart run example/datachannel/signaling_server.dart
   ```

2. Start the Dart offer:
   ```bash
   dart run example/datachannel/offer.dart
   ```

3. Open `example/datachannel/answer.html` in a browser and click "Connect"

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
dart run example/datachannel/offer.dart ws://my-server:9999
dart run example/datachannel/answer.dart ws://my-server:9999
```
