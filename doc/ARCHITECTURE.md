# Architecture - webrtc_dart

## Overview

This document defines the architecture and module structure for the Dart port of werift-webrtc. The design follows the TypeScript original's layered approach while adapting to Dart idioms.

## Package Structure

Unlike the TypeScript monorepo with separate npm packages, the Dart port uses a single package with clear module separation:

```
lib/
├── webrtc_dart.dart              # Main public API exports
└── src/
    ├── common/                    # Common utilities (no dependencies on other modules)
    │   ├── binary.dart           # Binary helpers (Uint8List/ByteData wrappers)
    │   ├── event.dart            # Event system (Stream-based)
    │   ├── log.dart              # Structured logging
    │   ├── network.dart          # Network utilities (address handling)
    │   ├── transport.dart        # Transport interface
    │   └── utils.dart            # General utilities
    │
    ├── stun/                      # STUN/TURN protocol (depends: common)
    │   ├── message.dart          # STUN message encoding/decoding
    │   ├── attributes.dart       # STUN attributes
    │   ├── protocol.dart         # STUN protocol implementation
    │   └── turn.dart             # TURN extensions
    │
    ├── ice/                       # ICE transport (depends: common, stun)
    │   ├── candidate.dart        # ICE candidate model
    │   ├── ice_connection.dart   # Main ICE connection interface
    │   ├── ice_gatherer.dart     # Candidate gathering
    │   ├── ice_transport.dart    # ICE transport implementation
    │   └── utils.dart            # ICE utilities
    │
    ├── crypto/                    # Crypto primitives (depends: common)
    │   ├── certificate.dart      # X.509 certificate handling
    │   ├── cipher.dart           # Cipher suites
    │   └── keys.dart             # Key derivation
    │
    ├── dtls/                      # DTLS handshake (depends: common, crypto)
    │   ├── context.dart          # DTLS context
    │   ├── flight.dart           # Handshake flights
    │   ├── handshake.dart        # Handshake state machine
    │   ├── record.dart           # Record layer
    │   ├── dtls_transport.dart   # DTLS transport
    │   └── cipher/               # Cipher implementations
    │
    ├── srtp/                      # SRTP/SRTCP (depends: common, crypto)
    │   ├── srtp_session.dart     # SRTP session
    │   ├── srtcp_session.dart    # SRTCP session
    │   ├── context.dart          # SRTP context
    │   └── transform.dart        # Encryption/decryption
    │
    ├── rtp/                       # RTP/RTCP stack (depends: common, srtp)
    │   ├── rtp/
    │   │   ├── packet.dart       # RTP packet structure
    │   │   ├── header.dart       # RTP header
    │   │   └── builder.dart      # RTP packet builder
    │   ├── rtcp/
    │   │   ├── packet.dart       # RTCP packet structure
    │   │   ├── sr.dart           # Sender Report
    │   │   ├── rr.dart           # Receiver Report
    │   │   ├── sdes.dart         # Source Description
    │   │   └── feedback.dart     # RTCP feedback messages
    │   ├── codec/
    │   │   ├── opus.dart         # Opus codec (MVP)
    │   │   └── payload.dart      # Payload handling
    │   └── rtp_transport.dart    # RTP transport
    │
    ├── sctp/                      # SCTP over DTLS (depends: common, dtls)
    │   ├── chunk.dart            # SCTP chunks
    │   ├── param.dart            # SCTP parameters
    │   ├── sctp_connection.dart  # SCTP association
    │   └── sctp_transport.dart   # SCTP transport
    │
    ├── sdp/                       # SDP parsing/generation (depends: common)
    │   ├── parser.dart           # SDP parser
    │   ├── generator.dart        # SDP generator
    │   ├── media.dart            # Media description
    │   └── session.dart          # Session description
    │
    └── webrtc/                    # High-level WebRTC API (depends: all above)
        ├── peer_connection.dart   # RTCPeerConnection
        ├── data_channel.dart      # RTCDataChannel
        ├── rtp_transceiver.dart   # RTCRtpTransceiver
        ├── rtp_sender.dart        # RTCRtpSender
        ├── rtp_receiver.dart      # RTCRtpReceiver
        └── media/
            ├── media_stream.dart      # MediaStream
            └── media_stream_track.dart # MediaStreamTrack
```

## Layer Dependencies

Clear dependency hierarchy (no circular dependencies):

```
Level 0: common (no dependencies)
Level 1: stun, crypto, sdp (depend only on common)
Level 2: ice (depends on common, stun)
Level 3: dtls, srtp (depend on common, crypto)
Level 4: rtp, sctp (depend on common, srtp/dtls)
Level 5: webrtc (depends on all above)
```

**Validation**: Each level can only import from lower levels. This ensures:
- ICE doesn't know about RTP
- DTLS doesn't know about SCTP
- Clean separation of concerns
- Testability (can test each layer independently)

## Core Interfaces

### Transport Interface

All network transports implement a common interface:

```dart
/// Abstract transport for sending/receiving data over the network
abstract class Transport {
  /// Transport type (udp, tcp, etc.)
  String get type;

  /// Local address info
  InternetAddress get address;
  int get port;

  /// Whether transport is closed
  bool get closed;

  /// Stream of incoming data packets
  Stream<DatagramPacket> get onData;

  /// Send data to address
  Future<void> send(Uint8List data, InternetAddress address, int port);

  /// Close the transport
  Future<void> close();
}

class DatagramPacket {
  final Uint8List data;
  final InternetAddress address;
  final int port;

  DatagramPacket(this.data, this.address, this.port);
}
```

### Ice Connection Interface

```dart
/// ICE connection for establishing connectivity
abstract class IceConnection {
  bool get iceControlling;
  String get localUsername;
  String get localPassword;

  /// Stream of state changes
  Stream<IceState> get onStateChanged;

  /// Stream of discovered candidates
  Stream<Candidate> get onIceCandidate;

  /// Stream of incoming data
  Stream<Uint8List> get onData;

  /// Set remote ICE parameters
  void setRemoteParams({
    required bool iceLite,
    required String usernameFragment,
    required String password,
  });

  /// Gather local candidates
  Future<void> gatherCandidates();

  /// Start connectivity checks
  Future<void> connect();

  /// Add remote candidate
  Future<void> addRemoteCandidate(Candidate candidate);

  /// Send data over nominated pair
  Future<void> send(Uint8List data);

  /// Close connection
  Future<void> close();
}
```

### DTLS Transport Interface

```dart
/// DTLS transport for secure communication over UDP
abstract class DtlsTransport {
  /// DTLS state
  DtlsState get state;

  /// Local certificate fingerprint
  String get localFingerprint;

  /// Stream of state changes
  Stream<DtlsState> get onStateChanged;

  /// Stream of decrypted data
  Stream<Uint8List> get onData;

  /// Start DTLS handshake
  Future<void> start({required bool isClient});

  /// Send encrypted data
  Future<void> send(Uint8List data);

  /// Get SRTP keys after handshake
  SrtpKeys getSrtpKeys();

  /// Close transport
  Future<void> close();
}
```

### RTP Transport Interface

```dart
/// RTP transport for media streaming
abstract class RtpTransport {
  /// Stream of incoming RTP packets
  Stream<RtpPacket> get onRtpPacket;

  /// Stream of incoming RTCP packets
  Stream<RtcpPacket> get onRtcpPacket;

  /// Send RTP packet
  Future<void> sendRtp(RtpPacket packet);

  /// Send RTCP packet
  Future<void> sendRtcp(RtcpPacket packet);

  /// Close transport
  Future<void> close();
}
```

### SCTP Transport Interface

```dart
/// SCTP transport for reliable data delivery
abstract class SctpTransport {
  /// SCTP state
  SctpState get state;

  /// Stream of state changes
  Stream<SctpState> get onStateChanged;

  /// Stream of incoming SCTP messages
  Stream<SctpMessage> get onMessage;

  /// Start SCTP association
  Future<void> start({required bool isClient});

  /// Send SCTP message
  Future<void> send(SctpMessage message);

  /// Close association
  Future<void> close();
}
```

## Concurrency Model

### Decision: Async/Await with Single Isolate

**Chosen approach**: Single-isolate async/await (no isolates for MVP)

**Rationale**:
1. **Simplicity**: Easier to debug, no message passing overhead
2. **Sufficient performance**: Crypto operations are fast enough in modern Dart
3. **TypeScript parity**: Matches single-threaded Node.js model
4. **Event loop efficiency**: Dart's async/await is highly optimized

**Future optimization**: If profiling shows crypto as bottleneck, can offload to isolates:
```dart
// Future optimization point
class CryptoIsolatePool {
  // Offload AES-GCM, HMAC-SHA256 to worker isolates
  Future<Uint8List> encrypt(Uint8List data, SrtpKeys keys);
  Future<Uint8List> decrypt(Uint8List data, SrtpKeys keys);
}
```

### Event System

Use Dart Streams for all async events:
- `Stream<T>` for multi-subscriber events (broadcast streams)
- `StreamController<T>` for event emission
- `async*` generators where appropriate

Example:
```dart
class IceConnectionImpl implements IceConnection {
  final _stateController = StreamController<IceState>.broadcast();

  @override
  Stream<IceState> get onStateChanged => _stateController.stream;

  void _setState(IceState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> close() async {
    await _stateController.close();
  }
}
```

## Testing Strategy

Each layer independently testable:

### Unit Tests
```
test/
├── common/
│   ├── binary_test.dart
│   └── event_test.dart
├── stun/
│   └── message_test.dart
├── ice/
│   └── candidate_test.dart
├── dtls/
│   └── handshake_test.dart
├── srtp/
│   └── session_test.dart
├── rtp/
│   └── packet_test.dart
├── sctp/
│   └── chunk_test.dart
└── webrtc/
    └── peer_connection_test.dart
```

### Integration Tests
```
test/integration/
├── ice_dtls_test.dart          # ICE + DTLS integration
├── dtls_srtp_test.dart         # DTLS + SRTP integration
├── rtp_codec_test.dart         # RTP + Codec integration
└── full_connection_test.dart   # Complete Dart ↔ TypeScript test
```

## Design Patterns

### Manager Pattern
Complex subsystems use dedicated manager classes:
- `SdpManager`: Handle SDP offer/answer
- `TransceiverManager`: Manage RTP transceivers
- `SctpTransportManager`: Manage data channels

### Immutable Value Objects
Data classes are immutable where possible:
```dart
class Candidate {
  final String foundation;
  final int component;
  final String protocol;
  final int priority;
  final String host;
  final int port;
  final String type;

  const Candidate({
    required this.foundation,
    required this.component,
    required this.protocol,
    required this.priority,
    required this.host,
    required this.port,
    required this.type,
  });
}
```

### Error Handling
Module-specific exceptions:
```dart
class IceException implements Exception {
  final String message;
  const IceException(this.message);
}

class DtlsException implements Exception {
  final String message;
  const DtlsException(this.message);
}
```

## State Management

Use enums for state machines:
```dart
enum IceState {
  new_,
  checking,
  connected,
  completed,
  failed,
  disconnected,
  closed,
}

enum DtlsState {
  new_,
  connecting,
  connected,
  closed,
  failed,
}
```

## Next Steps

With architecture defined:
1. **Step 3**: Implement binary & crypto foundations
2. Create base classes and interfaces in `lib/src/common/`
3. Set up package structure
4. Begin STUN implementation (Step 4)
