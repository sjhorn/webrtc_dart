# Interop Testing: Dart ↔ TypeScript

This directory contains interop tests between webrtc_dart (Dart) and werift-webrtc (TypeScript).

## Goal

Validate that the Dart implementation can successfully establish WebRTC connections and exchange data with the original TypeScript implementation.

## Test Setup

### File-Based Signaling

The tests use a simple file-based signaling mechanism:
1. Dart peer creates an offer and writes it to `signals/offer.json`
2. TypeScript peer reads the offer, creates an answer, and writes it to `signals/answer.json`
3. Dart peer reads the answer and completes the connection
4. Both peers exchange datachannel messages

### Files

- `dart_offerer.dart` - Dart peer that creates the offer
- `ts_answerer.ts` - TypeScript peer that creates the answer
- `signals/` - Directory for SDP exchange files (auto-created)

## Running the Test

### Prerequisites

1. **TypeScript werift-webrtc dependencies:**
   ```bash
   cd werift-webrtc
   npm install
   npm run build
   ```

2. **Dart dependencies:**
   ```bash
   dart pub get
   ```

### Step 1: Start TypeScript Answerer

In terminal 1:
```bash
npx ts-node interop/ts_answerer.ts
```

This will wait for an offer file.

### Step 2: Run Dart Offerer

In terminal 2:
```bash
dart run interop/dart_offerer.dart
```

This will:
1. Create a PeerConnection and DataChannel
2. Generate an offer and write it to `signals/offer.json`
3. Wait for `signals/answer.json`
4. Set the remote description
5. Exchange datachannel messages with the TypeScript peer

## Expected Output

### TypeScript Answerer Terminal:
```
[TS Answerer] Starting...
[TS Answerer] Waiting for offer at: .../signals/offer.json
[TS Answerer] Received offer
[TS Answerer] Remote description set
[TS Answerer] Local description set
[TS Answerer] Answer written to: .../signals/answer.json
[TS Answerer] Ready to receive messages...
[TS Answerer] DataChannel opened: chat
[TS Answerer] DataChannel state: open
[TS Answerer] Sending initial message
[TS Answerer] Received message: Hello from Dart!
[TS Answerer] Sending response: Echo: Hello from Dart!
...
```

### Dart Offerer Terminal:
```
[Dart Offerer] Starting...
[Dart Offerer] PeerConnection created
[Dart Offerer] DataChannel created: chat
[Dart Offerer] Creating offer...
[Dart Offerer] Offer written to: interop/signals/offer.json
[Dart Offerer] Waiting for answer...
[Dart Offerer] Received answer
[Dart Offerer] Remote description set
[Dart Offerer] Connection should establish now...
[Dart Offerer] ICE connection state: IceConnectionState.connected
[Dart Offerer] DataChannel state: DataChannelState.open
[Dart Offerer] Received message #1: Hello from TypeScript!
[Dart Offerer] Sending: Message #1 from Dart
[Dart Offerer] Received message #2: Echo: Message #1 from Dart
...
[SUCCESS] Dart ↔ TypeScript interop working!
```

## Success Criteria

The test is successful if:
- ✅ SDP offer/answer exchange completes
- ✅ ICE connection reaches "connected" or "completed" state
- ✅ DataChannel opens successfully
- ✅ Messages are exchanged bidirectionally
- ✅ No errors or exceptions occur

## Troubleshooting

### Offer file not found
- Make sure you start the TypeScript answerer first
- Check that the `signals/` directory exists

### Connection timeout
- Check that both peers are running
- Verify SDP files are being created in `signals/`
- Check for firewall issues (though local connections should work)

### DataChannel not opening
- Check ICE connection state - it should reach "connected"
- Verify DTLS handshake completed
- Check console logs for errors

## Next Steps

After validating file-based signaling:
1. Add HTTP/WebSocket signaling server
2. Test with browser peers (Chrome, Firefox)
3. Add audio track interop tests
4. Test with other WebRTC implementations (Pion, libdatachannel)
