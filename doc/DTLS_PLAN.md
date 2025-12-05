# DTLS Implementation Plan

## Overview

Port the werift-webrtc DTLS implementation from TypeScript to Dart. The TypeScript implementation has ~4,162 lines of code across 58 files.

## TypeScript Structure Analysis

```
dtls/src/
├── cipher/                    # Cryptographic primitives
│   ├── const.ts              # Cipher suite constants
│   ├── create.ts             # Cipher suite creation
│   ├── ec.ts                 # Elliptic curve operations
│   ├── key-exchange.ts       # Key exchange algorithms
│   ├── namedCurve.ts         # Named curve definitions
│   ├── prf.ts                # Pseudo-random function (TLS PRF)
│   ├── utils.ts              # Crypto utilities
│   └── suites/               # Cipher suite implementations
│       ├── abstract.ts       # Base cipher suite
│       ├── aead.ts           # AEAD cipher suites (AES-GCM)
│       └── null.ts           # NULL cipher (testing)
├── context/                   # State management
│   ├── cipher.ts             # Cipher state
│   ├── dtls.ts               # DTLS state
│   ├── srtp.ts               # SRTP keying material
│   └── transport.ts          # Transport abstraction
├── flight/                    # Handshake flights (message groups)
│   ├── client/
│   │   ├── flight1.ts        # ClientHello
│   │   ├── flight3.ts        # ClientHello (after cookie)
│   │   └── flight5.ts        # ClientKeyExchange, ChangeCipherSpec, Finished
│   └── server/
│       ├── flight2.ts        # HelloVerifyRequest
│       ├── flight4.ts        # ServerHello, Certificate, ServerKeyExchange, etc.
│       └── flight6.ts        # ChangeCipherSpec, Finished
├── handshake/                 # Handshake messages
│   ├── binary.ts             # Binary serialization
│   ├── const.ts              # Constants
│   ├── random.ts             # Random value generation
│   ├── extensions/           # TLS extensions
│   │   ├── ellipticCurves.ts
│   │   ├── extendedMasterSecret.ts
│   │   ├── renegotiationIndication.ts
│   │   ├── signature.ts
│   │   └── useSrtp.ts
│   └── message/              # Handshake message types
│       ├── alert.ts
│       ├── certificate.ts
│       ├── changeCipherSpec.ts
│       ├── finished.ts
│       ├── client/
│       │   ├── certificateVerify.ts
│       │   ├── hello.ts
│       │   └── keyExchange.ts
│       └── server/
│           ├── certificateRequest.ts
│           ├── hello.ts
│           ├── helloDone.ts
│           ├── helloVerifyRequest.ts
│           └── keyExchange.ts
├── record/                    # DTLS record layer
│   ├── antiReplayWindow.ts   # Replay protection
│   ├── builder.ts            # Record building
│   ├── const.ts              # Record constants
│   ├── receive.ts            # Record parsing
│   └── message/
│       ├── fragment.ts       # Handshake fragmentation
│       ├── header.ts         # Record header
│       └── plaintext.ts      # Plaintext record
├── client.ts                  # DTLS client
├── server.ts                  # DTLS server
└── socket.ts                  # Main DTLS socket

```

## Implementation Phases

### Phase 1: Foundation (~400 lines)
**Goal**: Core types, constants, and utilities

**Files to port**:
1. `record/const.ts` → `lib/src/dtls/record/const.dart`
   - ContentType enum
   - ProtocolVersion
   - Record layer constants

2. `handshake/const.ts` → `lib/src/dtls/handshake/const.dart`
   - HandshakeType enum
   - Compression methods
   - Alert descriptions

3. `cipher/const.ts` → `lib/src/dtls/cipher/const.dart`
   - Cipher suite IDs
   - Named curves
   - Signature algorithms

4. `util/binary.ts` → Use existing `lib/src/common/binary.dart`
   - Already have most utilities
   - Add any missing helpers

**Validation**: Constants and enums compile, match TypeScript values

---

### Phase 2: Record Layer (~600 lines)
**Goal**: DTLS record encoding/decoding with encryption

**Files to port**:
1. `record/message/header.ts` → `lib/src/dtls/record/header.dart`
   - Record header parsing/serialization
   - 13-byte header structure

2. `record/message/plaintext.ts` → `lib/src/dtls/record/plaintext.dart`
   - Plaintext record structure
   - ContentType + version + epoch + sequence + length + fragment

3. `record/message/fragment.ts` → `lib/src/dtls/record/fragment.dart`
   - Handshake fragmentation
   - Message reassembly

4. `record/builder.ts` → `lib/src/dtls/record/builder.dart`
   - createPlaintext()
   - Record encryption wrapper

5. `record/receive.ts` → `lib/src/dtls/record/receive.dart`
   - parsePacket()
   - parsePlainText()
   - Record decryption

6. `record/antiReplayWindow.ts` → `lib/src/dtls/record/anti_replay_window.dart`
   - Sliding window for replay protection
   - Bitmap tracking

**Validation**: Can parse and serialize DTLS records, encrypt/decrypt

---

### Phase 3: Cipher Suites (~800 lines)
**Goal**: Cryptographic operations for DTLS

**Files to port**:
1. `cipher/suites/abstract.ts` → `lib/src/dtls/cipher/suites/abstract.dart`
   - Base CipherSuite class
   - encrypt(), decrypt(), verifyData()

2. `cipher/suites/aead.ts` → `lib/src/dtls/cipher/suites/aead.dart`
   - AES-GCM cipher suite (TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
   - Nonce construction
   - Additional authenticated data

3. `cipher/suites/null.ts` → `lib/src/dtls/cipher/suites/null.dart`
   - NULL cipher for testing

4. `cipher/prf.ts` → `lib/src/dtls/cipher/prf.dart`
   - TLS PRF (Pseudo-Random Function)
   - exportKeyingMaterial() for SRTP keys
   - Master secret derivation

5. `cipher/ec.ts` → `lib/src/dtls/cipher/ec.dart`
   - ECDH key agreement
   - Point serialization

6. `cipher/key-exchange.ts` → `lib/src/dtls/cipher/key_exchange.dart`
   - preMasterSecret generation
   - Key derivation

7. `cipher/namedCurve.ts` → `lib/src/dtls/cipher/named_curve.dart`
   - Curve25519, P-256, P-384 support

8. `cipher/utils.ts` → `lib/src/dtls/cipher/utils.dart`
   - Crypto helper functions

**Validation**: Can generate keys, encrypt/decrypt with AES-GCM

---

### Phase 4: Handshake Messages (~1200 lines)
**Goal**: Parse and serialize all handshake message types

**Files to port**:
1. `handshake/random.ts` → `lib/src/dtls/handshake/random.dart`
   - 32-byte random generation

2. `handshake/message/client/hello.ts` → `lib/src/dtls/handshake/message/client/hello.dart`
   - ClientHello message
   - Session ID, random, cipher suites, extensions

3. `handshake/message/server/hello.ts` → `lib/src/dtls/handshake/message/server/hello.dart`
   - ServerHello message

4. `handshake/message/server/helloVerifyRequest.ts` → `lib/src/dtls/handshake/message/server/hello_verify_request.dart`
   - Cookie exchange for DoS protection

5. `handshake/message/certificate.ts` → `lib/src/dtls/handshake/message/certificate.dart`
   - X.509 certificate message
   - Certificate chain parsing

6. `handshake/message/server/keyExchange.ts` → `lib/src/dtls/handshake/message/server/key_exchange.dart`
   - ECDHE key exchange parameters

7. `handshake/message/client/keyExchange.ts` → `lib/src/dtls/handshake/message/client/key_exchange.dart`
   - Client's ECDHE public key

8. `handshake/message/server/certificateRequest.ts` → (optional)
   - Client certificate request

9. `handshake/message/client/certificateVerify.ts` → (optional)
   - Client certificate verification

10. `handshake/message/server/helloDone.ts` → `lib/src/dtls/handshake/message/server/hello_done.dart`
    - ServerHelloDone marker

11. `handshake/message/changeCipherSpec.ts` → `lib/src/dtls/handshake/message/change_cipher_spec.dart`
    - ChangeCipherSpec message

12. `handshake/message/finished.ts` → `lib/src/dtls/handshake/message/finished.dart`
    - Finished message with verify_data

13. `handshake/message/alert.ts` → `lib/src/dtls/handshake/message/alert.dart`
    - Alert messages (errors, warnings)

**Extensions**:
1. `handshake/extensions/ellipticCurves.ts` → `lib/src/dtls/handshake/extensions/elliptic_curves.dart`
2. `handshake/extensions/signature.ts` → `lib/src/dtls/handshake/extensions/signature.dart`
3. `handshake/extensions/useSrtp.ts` → `lib/src/dtls/handshake/extensions/use_srtp.dart`
4. `handshake/extensions/extendedMasterSecret.ts` → `lib/src/dtls/handshake/extensions/extended_master_secret.dart`
5. `handshake/extensions/renegotiationIndication.ts` → (optional)

**Validation**: Can parse handshake messages from packet captures

---

### Phase 5: Context Management (~400 lines)
**Goal**: State tracking during handshake

**Files to port**:
1. `context/dtls.ts` → `lib/src/dtls/context/dtls.dart`
   - DtlsContext: epoch, sequence numbers, version
   - Handshake message buffers

2. `context/cipher.ts` → `lib/src/dtls/context/cipher.dart`
   - CipherContext: keys, certificates, signature algorithm
   - localPrivateKey, localCertificate, remoteCertificate

3. `context/srtp.ts` → `lib/src/dtls/context/srtp.dart`
   - SrtpContext: profile, keying material

4. `context/transport.ts` → `lib/src/dtls/context/transport.dart`
   - Transport abstraction over UDP

**Validation**: Context state tracked correctly during handshake

---

### Phase 6: Handshake Flights (~800 lines)
**Goal**: Implement message flows for client/server handshake

**Files to port**:
1. `flight/flight.ts` → `lib/src/dtls/flight/flight.dart`
   - Base Flight class
   - Retransmission logic

2. `flight/client/flight1.ts` → `lib/src/dtls/flight/client/flight1.dart`
   - Initial ClientHello

3. `flight/client/flight3.ts` → `lib/src/dtls/flight/client/flight3.dart`
   - ClientHello with cookie

4. `flight/client/flight5.ts` → `lib/src/dtls/flight/client/flight5.dart`
   - ClientKeyExchange, ChangeCipherSpec, Finished

5. `flight/server/flight2.ts` → `lib/src/dtls/flight/server/flight2.dart`
   - HelloVerifyRequest

6. `flight/server/flight4.ts` → `lib/src/dtls/flight/server/flight4.dart`
   - ServerHello, Certificate, ServerKeyExchange, ServerHelloDone

7. `flight/server/flight6.ts` → `lib/src/dtls/flight/server/flight6.dart`
   - ChangeCipherSpec, Finished

**Validation**: Flight state machine works correctly

---

### Phase 7: Client & Server (~400 lines)
**Goal**: High-level API for DTLS connections

**Files to port**:
1. `socket.ts` → `lib/src/dtls/socket.dart`
   - DtlsSocket base class
   - Event handling
   - Message routing

2. `client.ts` → `lib/src/dtls/client.dart`
   - DtlsClient
   - initiate handshake

3. `server.ts` → `lib/src/dtls/server.dart`
   - DtlsServer
   - respond to handshake

**Validation**: Can complete full handshake client ↔ server

---

### Phase 8: Integration & Testing (~300 lines tests)
**Goal**: Comprehensive tests and integration with ICE layer

**Tasks**:
1. Unit tests for each module
2. Integration tests (client ↔ server handshake)
3. Interop tests with TypeScript implementation
4. Connect DTLS to ICE transport
5. Update DtlsTransport interface to use real implementation

**Validation**:
- Dart DTLS client ↔ Dart DTLS server
- Dart DTLS client ↔ TypeScript DTLS server
- Dart DTLS server ↔ TypeScript DTLS client

---

## Implementation Strategy

### Dependency on Dart Packages

**Required packages**:
- `pointycastle` or `cryptography` for:
  - ECDH (Curve25519, P-256)
  - AES-GCM encryption
  - SHA-256 hashing
  - HMAC

**Certificate handling**:
- `asn1lib` for X.509 parsing
- Or generate self-signed certs with `x509` package

### Incremental Approach

1. **Start with Phase 1-2**: Get record layer working
2. **Phase 3**: Implement one cipher suite (AES-GCM) fully
3. **Phase 4-5**: Build up handshake messages and context
4. **Phase 6**: Implement client-only flights first
5. **Phase 7**: Complete with server flights
6. **Phase 8**: Test and iterate

### Testing Strategy

- **Golden tests**: Use packet captures from TypeScript implementation
- **Unit tests**: Each message type, cipher operation
- **Integration tests**: Full handshake flows
- **Interop tests**: Cross-verify with TypeScript

### Code Organization

Follow Dart conventions while maintaining TypeScript structure:
- `lib/src/dtls/` matches TypeScript `src/` structure
- Use Dart naming: `ClassName`, `methodName`, `variable_name`
- Leverage Dart's type system (sealed classes, enums with values)

---

## Effort Estimate

**Total**: ~4,500 lines of Dart code + ~1,000 lines of tests

**Timeline** (if working sequentially):
- Phase 1: 1-2 days
- Phase 2: 2-3 days
- Phase 3: 3-4 days
- Phase 4: 4-5 days
- Phase 5: 1-2 days
- Phase 6: 3-4 days
- Phase 7: 1-2 days
- Phase 8: 2-3 days

**Total: ~20-27 days** of focused implementation

---

## Alternative: Simplified DTLS

If full implementation is too time-consuming, consider:

1. **Single cipher suite**: Only TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
2. **No renegotiation**: Simplified state machine
3. **Client-only**: Skip server implementation initially
4. **No client certificates**: Skip certificate request/verify
5. **Fixed curve**: Only support Curve25519

This could reduce scope by ~40-50%, getting to ~2,500 lines total.

---

## Recommendation

Given the substantial effort required:

**Option A**: Full port (~4,500 lines, 3-4 weeks)
- Complete parity with TypeScript
- All cipher suites and features
- Production-ready

**Option B**: Minimal viable DTLS (~2,500 lines, 2 weeks)
- Single cipher suite
- Client-side only
- Enough for WebRTC data channels

**Option C**: Interface + FFI (~500 lines, 3-5 days)
- Dart interface (already done)
- FFI bindings to OpenSSL/BoringSSL
- Fastest path to working WebRTC

For this project's goals (porting werift-webrtc), **Option A or B** aligns best with the stated goal of matching the TypeScript implementation.

Let's proceed with **Option B (Minimal Viable DTLS)** as a starting point, which can be expanded later if needed.
