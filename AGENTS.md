# AGENTS.md

## Project Overview
This is a pure dart port of the [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) Typescript code base. The repository is cloned locally into ./webrift-webrtc

It is design to mimic the directory structure, filenames and classnames where possible while using dart style.

All methods should aim to match the inputs and output of the Typescript code base and small scripts will be create to source the outputs for given inputs and added to the unit test of dart to run without relying on the typescript.

For crypto we will aim to mimic the Typescript approach where directly implemented and where it relies on the crypto library we will prefer to use the dart package:cryptography.

For binary and byte level operations we will use Uint8List and ByteData.view and aim to implement helpers similar to Node Buffer / DataView wrappers for ergonomic parsing. These will be compared to Typescript and unit tests with the common cases.

We will port all the existing README.md and other .md files from the werift-webrtc code base.

We will maintain a TODO.md with the structure shown in the next section titled TODO.

---

## Current Progress (November 2025)

### Status: Phase 1 COMPLETE + Browser Interop WORKING

| Component | Status | Tests |
|-----------|--------|-------|
| Core Protocols (STUN/ICE/DTLS/SRTP/SCTP/RTP) | ✅ Complete | 500+ |
| DataChannel | ✅ Complete | Full DCEP |
| VP8 Depacketization | ✅ Complete | 22 |
| VP9 Depacketization | ✅ Complete | 25 |
| H.264 Depacketization | ✅ Complete | 22 |
| AV1 Depacketization | ✅ Complete | 32 |
| NACK | ✅ Complete | 41 |
| PLI/FIR | ✅ Complete | 48 |
| RTX + SDP Negotiation | ✅ Complete | 85 |
| TURN (Core + Data Relay) | ✅ Complete | 50 |
| getStats() MVP | ✅ Complete | 9 |
| **Total** | **Phase 1 Complete** | **891 tests** |

### Interop Status
- ✅ **Dart ↔ Chrome Browser**: DataChannel working (DTLS + SCTP)
- ✅ **Dart ↔ TypeScript (werift)**: DataChannel working
- 🔜 **Firefox/Safari**: Not yet tested

### Next Priorities (Phase 2)
1. TWCC (Transport-Wide Congestion Control)
2. Simulcast Support
3. Jitter Buffer
4. Browser Interop Testing (Firefox, Safari)

See **ROADMAP.md** for detailed implementation status and roadmap. 

---
## TODO

1. Scope & MVP Definition
- What subset first? (e.g. datachannels-only, no media; or 1 audio track only)
- Target platforms for MVP (e.g. server + Android only).
- Interop target(s): Chrome, Pion, libdatachannel, etc.

Validation:
- One end in Dart, one in Chrome, send/receive a simple “hello” over datachannel or audio.



2. Architecture & Module Layout
- Package structure (e.g. core/, ice/, dtls/, srtp/, rtp/, sctp/, sdp/).
- Clear interfaces:
- Transport (UDP abstraction)
- IceTransport, DtlsTransport, RtpTransport, SctpTransport
- Decide: single-threaded async vs isolates for heavy work.

Validation:
- No circular deps, layers are clean (ICE not knowing about RTP, etc.).



3. Binary & Crypto Foundations
- Binary helpers: read/write big-endian ints, bitfields, buffer slicing.
- Common packet base classes (PacketReader, PacketWriter).
- Crypto primitives: hook up AES, HMAC, random, etc. using Dart crypto packages.

Validation:
- Golden tests: encode/decode known test vectors (hashes, AES, etc.).
- Packet round-trips (serialize → parse → equals).



4. STUN & TURN Layer
- STUN message encode/decode.
- Attributes, integrity checks (MESSAGE-INTEGRITY, FINGERPRINT).
- Basic STUN client: binding request/response.
- TURN allocation / permission basics if in scope.

Validation:
- Interop with a public STUN server.
- Confirm XOR-MAPPED-ADDRESS, transaction IDs, etc. using Wireshark.



5. ICE Agent
- Candidate model (host, srflx, relay, prflx).
- Checklists, connectivity checks, nomination.
- Trickle ICE support.
- Tiebreakers, roles (controlling/controlled).

Validation:
- Connect two Dart peers on LAN.
- Connect Dart ↔ browser via standard STUN.
- Validate state transitions (new → checking → connected → completed/failed).



6. DTLS Handshake & Record Layer
- DTLS 1.2 handshake state machine.
- Record layer: fragment, reassembly, retransmit.
- Key extraction for SRTP (exporter).

Validation:
- DTLS handshake against:
- Browser
- OpenSSL/mbedTLS DTLS server, if you set one up
- Dump traffic in Wireshark, verify cipher suite, handshake completion.



7. SRTP / SRTCP
- Implement SRTP per RFC 3711 (AES-CTR / AES-CM + HMAC-SHA1).
- Replay protection, rollover counters, key derivation.
- SRTCP control packets.

Validation:
- Known test vectors (if available).
- Interop: send/receive a simple RTP stream to/from a known SRTP implementation.



8. RTP & RTCP Stack
- RTP header parsing/serialization.
- Sequence number, timestamp, SSRC handling.
- Basic RTCP: SR, RR, SDES, BYE.
- Simple jitter buffer / reordering if needed.

Validation:
- Round-trip encode/decode of RTP/RTCP test packets.
- Interop: receive media from Chrome/OBS/etc., decode headers correctly.
- Verify reporting fields (packet loss, jitter) make sense.



9. SCTP & Data Channels
- SCTP association over DTLS.
- Datachannel protocol (reliable/unreliable, ordered/unordered).
- Stream mapping, open/close messages, labels.

Validation:
- Open datachannel Dart ↔ browser, round-trip text/binary messages.
- Test all options: ordered/unordered, reliable/partial-reliable.



10. SDP & Signalling API
- SDP parsing / generation: offers, answers, ICE candidates.
- Support for at least:
- UDP/TLS/RTP/SAVPF lines
- ICE ufrag/pwd
- Fingerprints
- m= sections for data / media
- Public-facing Dart API: PeerConnection, addIceCandidate, setLocalDescription, etc.

Validation:
- Generate SDP, feed to Chrome’s RTCPeerConnection, ensure it accepts.
- Parse browser SDP and map correctly into your internal models.



11. Media Integration (Optional Phase 2)
- Pluggable audio/video sources (e.g. raw PCM, raw YUV).
- Encoders/decoders (Opus, VP8, etc.) – pure Dart or FFI.
- Clocking, pacing, sync (audio/video).

Validation:
- One-way audio: Dart → browser (or browser → Dart).
- Eventually bidirectional A/V with acceptable latency and jitter.



12. Observability, Logging & Debugging Tools
- Structured logging with levels and categories (ICE/DTLS/SRTP/RTP/SCTP).
- Packet hex dumps in debug mode.
- Optional stats API (similar to getStats()).

Validation:
- Can trace any interop failure down to a specific layer quickly.
- Logs give you enough context to file interop bugs or fix your own.



13. Interop & Compliance Test Matrix
- Matrix of:
- Dart ↔ Chrome
- Dart ↔ Firefox
- Dart ↔ Pion / libdatachannel / Janus
- Automated test scenes:
- Datachannel-only
- Audio-only
- Multi-candidate scenarios (host/NAT/TURN)

Validation:
- Pass/fail table for combinations (browser versions, configs, network conditions).
- CI tests with headless peers where possible.



14. Performance, Benchmarks & Tuning
- Benchmarks for:
- Packets per second
- CPU usage per stream / bitrate
- Latency through each layer
- Tuning:
- Buffer reuse
- Avoiding excessive allocations
- Isolate-based offloading for hot paths (crypto, RTP)

Validation:
- Target numbers: e.g. “N streams at X bitrate on mid-tier Android stays under Y% CPU”.



15. Packaging, Docs & Examples
- Public API surface cleaned and documented.
- Example apps:
- CLI echo peer (datachannel).
- Minimal Flutter app: connect to browser, send text.
- Optional: simple audio demo.

Validation:
- A new user can get a working Dart ↔ browser demo by following README steps only.


---

## Setup Commands
```bash
# Activate Dart SDK
dart --version

# Fetch dependencies
dart pub get

# Run the example (if applicable)
dart run example/main.dart

# Run tests
dart test

# (Optional) Format code
dart format .

# (Optional) Analyze code for issues
dart analyze
```

---

## Build & Publish
```bash
# Build the package (if relevant, e.g., for Flutter or platform-specific)
dart compile <executable> --output=...

# Publish to pub.dev (this is a Flutter package)
flutter pub publish --dry-run
echo "y" | flutter pub publish
```

> **Note**: Ensure version updates in `pubspec.yaml`, update `CHANGELOG.md`, and tag the release in Git.
> For Flutter packages, use `flutter pub publish` instead of `dart pub publish`.

---

## Code Style & Conventions
- Follow the official Dart style guide: https://dart.dev/guides/language/effective-dart/style  
- Use **two spaces** for indentation (Dart default)  
- Prefer `final` and `const` where possible  
- Public API should be documented with Dartdoc comments: `///`  
- Private members start with an underscore `_`  
- Avoid using `dynamic` unless absolutely necessary  
- Use null-safety (`--null-safety` enforced)  
- Organize imports:
  1. Dart SDK imports  
  2. Third-party package imports  
  3. Local package imports  
  Each group separated by a blank line.  
- Line length: aim for ≤ 80-100 characters for readability, but up to 120 acceptable for long doc comments or URLs.

---

## Testing Instructions
- All new features must include one or more tests in `test/`  
- Use descriptive test names and clearly arrange `arrange` / `act` / `assert` pattern  
- For widget or UI tests (if this is a Flutter package), ensure you use `flutter_test` and mock external dependencies  
- Before merging a pull request (PR), ensure:
  ```bash
  dart format --set-exit-if-changed .
  dart analyze
  dart test
  ```
- If you add new dependencies, update `pubspec.yaml` and run `dart pub get` in CI.

---

## Pull Request (PR) Guidelines
- Title format: `<component>: <short description>` or `bugfix(<component>): <short description>`  
- PR description should contain:
  - Summary of change  
  - Motivation / context  
  - How to test the change  
- Link to any relevant issue(s) or discussion(s)  
- When ready, mark the PR as ready for review and assign relevant reviewers  
- After approval, merge via “Squash & merge” (unless otherwise directed)  
- Post-merge: create a new release tag (`vX.Y.Z`) and update `CHANGELOG.md`

---

## Versioning & CHANGELOG
- Use [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`  
- Update `CHANGELOG.md` for each version change under appropriate sections: Added, Changed, Fixed, Removed  
- Tag the release in Git:  
  ```bash
  git tag -a vX.Y.Z -m "Release version X.Y.Z"
  git push origin vX.Y.Z
  ```

---

## Security & Compliance
- Avoid committing secrets (API keys, credentials) in the repository  
- Use `gitignore` for local settings, build artefacts, and analysis caches  
- Renew any keys/certificates when they expire  
- For dependencies: review license compliance and check for vulnerabilities (e.g., `dart pub outdated --severity=high`)  
- If your package interacts with platform channels (Flutter) or native code, validate memory safety and concurrency issues

---

## Agent & Automation Tips
- Place this `AGENTS.md` at the root—agents will pick it up automatically.
- Agents should avoid modifying files outside of the package directories without explicit instruction.
- Ensure agents run the setup commands first, and then apply changes (formatting, tests, code) so they respect project conventions.
- If the package becomes part of a mono-repo, consider adding nested `AGENTS.md` in sub-packages for more granular guidance.

### Platform Permissions

#### macOS Network Entitlements
When creating new Flutter examples that require network access (API calls, WebRTC, etc.):
- **ALWAYS** add network entitlements to both Debug and Release configurations
- Files to update:
  - `macos/Runner/DebugProfile.entitlements` — Add `com.apple.security.network.client` (and `com.apple.security.network.server` if needed)
  - `macos/Runner/Release.entitlements` — Add `com.apple.security.network.client`
- Example DebugProfile.entitlements:
  ```xml
  <key>com.apple.security.network.server</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  ```
- Example Release.entitlements:
  ```xml
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  ```

---

## FAQ
**Q: Are there required fields in `AGENTS.md`?**  
A: No. It’s just Markdown. Use any headings and content that help agents and contributors.  [oai_citation:0‡agents.md](https://agents.md/)  

**Q: What if instructions conflict?**  
A: The closest `AGENTS.md` (in the directory tree) takes precedence. Also human instruction overrides automated instructions.  [oai_citation:1‡agents.md](https://agents.md/)  

**Q: Can we update `AGENTS.md` later?**  
A: Yes — treat it as living documentation.  [oai_citation:2‡agents.md](https://agents.md/)  

---

  