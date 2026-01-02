# WebRTC API Compatibility Assessment

## Overview

Assessment of webrtc_dart APIs compared to W3C WebRTC standard (MDN documentation) with effort estimates for achieving full compatibility while maintaining backward compatibility.

---

## Implementation Strategy (Revised)

**Approach:**
1. **Rename source to W3C standard names** - Classes use `RTC` prefix (RTCPeerConnection, RTCDataChannel, etc.)
2. **TypeDefs for backward compatibility** - Old names point to new: `typedef RtcPeerConnection = RTCPeerConnection;`
3. **Listener layer for JS-style events** - Add setter-based callbacks alongside Dart Streams

---

## Executive Summary

| Category | Current State | Effort to Fix |
|----------|--------------|---------------|
| **Core APIs** | ~90% compatible | Low |
| **Naming Conventions** | Rename source to W3C | Medium |
| **Event Model** | Add listener layer (keep Streams) | Medium |
| **Missing Interfaces** | RTCDTMFSender, some properties | Medium |
| **Backward Compatibility** | TypeDefs for old names | Low overhead |

**Overall Estimate:** 4-6 days for full W3C naming + listener layer with backward compat.

---

## Detailed Comparison

### 1. RTCPeerConnection

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCPeerConnection` | `RtcPeerConnection` | Naming | Add alias |
| `createOffer()` | `createOffer()` | Match | - |
| `createAnswer()` | `createAnswer()` | Match | - |
| `setLocalDescription()` | `setLocalDescription()` | Match | - |
| `setRemoteDescription()` | `setRemoteDescription()` | Match | - |
| `addIceCandidate()` | `addIceCandidate()` | Match | - |
| `addTrack()` | `addTrack()` | Match | - |
| `removeTrack()` | `removeTrack()` | Match | - |
| `createDataChannel()` | `createDataChannel()` | Match | - |
| `getStats()` | `getStats()` | Match | - |
| `getSenders()` | `getSenders()` | Match | - |
| `getReceivers()` | `getReceivers()` | Match | - |
| `getTransceivers()` | `getTransceivers()` | Match | - |
| `restartIce()` | `restartIce()` | Match | - |
| `close()` | `close()` | Match | - |
| `connectionState` | `connectionState` | Match | - |
| `iceConnectionState` | `iceConnectionState` | Match | - |
| `iceGatheringState` | `iceGatheringState` | Match | - |
| `signalingState` | `signalingState` | Match | - |
| `localDescription` | `localDescription` | Match | - |
| `remoteDescription` | `remoteDescription` | Match | - |
| `onicecandidate` | `onIceCandidate` (Stream) | Event model | Acceptable |
| `ontrack` | `onTrack` (Stream) | Event model | Acceptable |
| `ondatachannel` | `onDataChannel` (Stream) | Event model | Acceptable |
| `onnegotiationneeded` | `onNegotiationNeeded` (Stream) | Event model | Acceptable |
| `onconnectionstatechange` | `onConnectionStateChange` (Stream) | Event model | Acceptable |
| `onicegatheringstatechange` | `onIceGatheringStateChange` (Stream) | Event model | Acceptable |
| `oniceconnectionstatechange` | `onIceConnectionStateChange` (Stream) | Event model | Acceptable |
| `onsignalingstatechange` | Missing | Add | 1 hour |
| `onicecandidateerror` | Missing | Add | 2 hours |
| `sctp` | Not exposed | Optional | Low priority |
| `peerIdentity` | Not implemented | Optional | Low priority |

**PeerConnection Score: 28/32 properties (87.5%)**

---

### 2. RTCDataChannel

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCDataChannel` | `DataChannel` | Naming | Add alias |
| `label` | `label` | Match | - |
| `ordered` | `ordered` | Match | - |
| `maxPacketLifeTime` | `maxPacketLifeTime` | Match | - |
| `maxRetransmits` | `maxRetransmits` | Match | - |
| `protocol` | `protocol` | Match | - |
| `negotiated` | Missing | Add | 2 hours |
| `id` | `streamId` | Naming | Add alias |
| `readyState` | `state` | Naming | Add alias |
| `bufferedAmount` | `bufferedAmount` | Match | - |
| `bufferedAmountLowThreshold` | `bufferedAmountLowThreshold` | Match | - |
| `binaryType` | Missing | Not needed | Dart handles types |
| `send()` | `send()` | Match | - |
| `close()` | `close()` | Match | - |
| `onopen` | `onStateChange` (filter) | Event model | Acceptable |
| `onclose` | `onStateChange` (filter) | Event model | Acceptable |
| `onclosing` | `onStateChange` (filter) | Event model | Acceptable |
| `onmessage` | `onMessage` | Match | - |
| `onerror` | `onError` | Match | - |
| `onbufferedamountlow` | `onBufferedAmountLow` | Match | - |

**DataChannel Score: 14/17 core properties (82%)**

---

### 3. RTCRtpTransceiver

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCRtpTransceiver` | `RtpTransceiver` | Naming | Add alias |
| `mid` | `mid` | Match | - |
| `sender` | `sender` | Match | - |
| `receiver` | `receiver` | Match | - |
| `direction` | `direction` | Match | - |
| `currentDirection` | Missing | Add | 1 hour |
| `stop()` | `stop()` | Match | - |
| `setCodecPreferences()` | Missing | Add | 4 hours |

**Transceiver Score: 5/7 properties (71%)**

---

### 4. RTCRtpSender

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCRtpSender` | `RtpSender` | Naming | Add alias |
| `track` | `track` | Match | - |
| `transport` | Not exposed | Add | 1 hour |
| `dtmf` | Missing (RTCDTMFSender) | Add | 8 hours |
| `getParameters()` | `getParameters()` | Match | - |
| `setParameters()` | `setParameters()` | Match | - |
| `replaceTrack()` | Missing | Add | 4 hours |
| `setStreams()` | Missing | Optional | Low priority |
| `getStats()` | Missing | Add | 2 hours |
| `transform` | Not applicable | - | Insertable Streams |

**Sender Score: 4/8 properties (50%)**

---

### 5. RTCRtpReceiver

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCRtpReceiver` | `RtpReceiver` | Naming | Add alias |
| `track` | `track` | Match | - |
| `transport` | Not exposed | Add | 1 hour |
| `getParameters()` | Missing | Add | 2 hours |
| `getContributingSources()` | Missing | Optional | Low priority |
| `getSynchronizationSources()` | Missing | Optional | Low priority |
| `getStats()` | Missing | Add | 2 hours |
| `transform` | Not applicable | - | Insertable Streams |

**Receiver Score: 2/6 properties (33%)**

---

### 6. RTCIceCandidate

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCIceCandidate` | `Candidate` | Naming | Add alias |
| `candidate` | `toSdp()` method | Accessor | Add property |
| `sdpMid` | `sdpMid` | Match | - |
| `sdpMLineIndex` | `sdpMLineIndex` | Match | - |
| `foundation` | `foundation` | Match | - |
| `component` | `component` | Match | - |
| `priority` | `priority` | Match | - |
| `address` | `host` | Naming | Add alias |
| `protocol` | `transport` | Naming | Add alias |
| `port` | `port` | Match | - |
| `type` | `type` | Match | - |
| `tcpType` | `tcpType` | Match | - |
| `relatedAddress` | `relatedAddress` | Match | - |
| `relatedPort` | `relatedPort` | Match | - |
| `usernameFragment` | `ufrag` | Naming | Add alias |
| `toJSON()` | Missing | Add | 1 hour |

**Candidate Score: 11/15 properties (73%)**

---

### 7. RTCSessionDescription

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCSessionDescription` | `SessionDescription` | Naming | Add alias |
| `type` | `type` | Match | - |
| `sdp` | `sdp` | Match | - |
| `toJSON()` | Missing | Add | 30 min |

**SessionDescription Score: 2/3 properties (67%)**

---

### 8. MediaStreamTrack

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `MediaStreamTrack` | `MediaStreamTrack` | Match | - |
| `kind` | `kind` | Match | - |
| `id` | `id` | Match | - |
| `label` | `label` | Match | - |
| `enabled` | `enabled` | Match | - |
| `muted` | `muted` | Match | - |
| `readyState` | `state` | Naming | Add alias |
| `contentHint` | Missing | Optional | Low priority |
| `stop()` | `stop()` | Match | - |
| `clone()` | `clone()` | Match | - |
| `getSettings()` | Missing | Optional | 2 hours |
| `getCapabilities()` | Missing | Optional | 2 hours |
| `getConstraints()` | Missing | Optional | 2 hours |
| `applyConstraints()` | Missing | Optional | 4 hours |
| `onmute` | `onMute` | Match | - |
| `onunmute` | `onMute` (false) | Combined | Acceptable |
| `onended` | `onEnded` | Match | - |

**Track Score: 10/14 core properties (71%)**

---

### 9. RTCDTMFSender (Missing Interface)

| W3C Standard | webrtc_dart Current | Status | Fix Effort |
|--------------|---------------------|--------|------------|
| `RTCDTMFSender` | Not implemented | New | 8 hours |
| `insertDTMF()` | Missing | Add | Included |
| `toneBuffer` | Missing | Add | Included |
| `ontonechange` | Missing | Add | Included |

**DTMF Score: 0/3 properties (0%)**

---

## Effort Breakdown

### Phase 1: Rename Source to W3C Standard - 8 hours

**Rename class files and update all references:**

| Current Name | W3C Name | File to Rename |
|--------------|----------|----------------|
| `RtcPeerConnection` | `RTCPeerConnection` | `rtc_peer_connection.dart` |
| `DataChannel` | `RTCDataChannel` | `rtc_data_channel.dart` |
| `RtpTransceiver` | `RTCRtpTransceiver` | `rtc_rtp_transceiver.dart` |
| `RtpSender` | `RTCRtpSender` | `rtc_rtp_sender.dart` |
| `RtpReceiver` | `RTCRtpReceiver` | `rtc_rtp_receiver.dart` |
| `Candidate` | `RTCIceCandidate` | `rtc_ice_candidate.dart` |
| `SessionDescription` | `RTCSessionDescription` | `rtc_session_description.dart` |

**Add backward compat typedefs in webrtc_dart.dart:**
```dart
// Backward compatibility - deprecated aliases
@Deprecated('Use RTCPeerConnection instead')
typedef RtcPeerConnection = RTCPeerConnection;

@Deprecated('Use RTCDataChannel instead')
typedef DataChannel = RTCDataChannel;

@Deprecated('Use RTCRtpTransceiver instead')
typedef RtpTransceiver = RTCRtpTransceiver;

@Deprecated('Use RTCRtpSender instead')
typedef RtpSender = RTCRtpSender;

@Deprecated('Use RTCRtpReceiver instead')
typedef RtpReceiver = RTCRtpReceiver;

@Deprecated('Use RTCIceCandidate instead')
typedef Candidate = RTCIceCandidate;

@Deprecated('Use RTCSessionDescription instead')
typedef SessionDescription = RTCSessionDescription;
```

**Rename properties to W3C standard:**
- `Candidate.host` -> `RTCIceCandidate.address` (keep `host` as deprecated alias)
- `Candidate.transport` -> `RTCIceCandidate.protocol` (keep `transport` as deprecated alias)
- `Candidate.ufrag` -> `RTCIceCandidate.usernameFragment`
- `DataChannel.streamId` -> `RTCDataChannel.id`
- `DataChannel.state` -> `RTCDataChannel.readyState`
- `MediaStreamTrack.state` -> `MediaStreamTrack.readyState`

**Effort: 8 hours**

---

### Phase 1.5: Add Listener Layer for JS-Style Events - 6 hours

**Design Pattern:**

The W3C WebRTC API uses setter-based event handlers (`pc.onicecandidate = function(e) {...}`).
We'll add this pattern alongside existing Dart Streams for full compatibility.

```dart
class RTCPeerConnection {
  // Existing Dart Stream (keep as primary API)
  Stream<RTCIceCandidate> get onIceCandidate => _iceCandidateController.stream;

  // NEW: W3C-style listener (setter wraps Stream subscription)
  StreamSubscription? _onicecandidateSubscription;

  set onicecandidate(void Function(RTCIceCandidate)? callback) {
    _onicecandidateSubscription?.cancel();
    if (callback != null) {
      _onicecandidateSubscription = onIceCandidate.listen(callback);
    }
  }

  void Function(RTCIceCandidate)? get onicecandidate => null; // Write-only per spec
}
```

**Events to add listener setters for:**

**RTCPeerConnection:**
- `onicecandidate` - wraps `onIceCandidate`
- `ontrack` - wraps `onTrack`
- `ondatachannel` - wraps `onDataChannel`
- `onnegotiationneeded` - wraps `onNegotiationNeeded`
- `onconnectionstatechange` - wraps `onConnectionStateChange`
- `onicegatheringstatechange` - wraps `onIceGatheringStateChange`
- `oniceconnectionstatechange` - wraps `onIceConnectionStateChange`
- `onsignalingstatechange` - NEW (also add Stream)
- `onicecandidateerror` - NEW (also add Stream)

**RTCDataChannel:**
- `onopen` - wraps `onStateChange` (filters for open)
- `onclose` - wraps `onStateChange` (filters for closed)
- `onclosing` - wraps `onStateChange` (filters for closing)
- `onmessage` - wraps `onMessage`
- `onerror` - wraps `onError`
- `onbufferedamountlow` - wraps `onBufferedAmountLow`

**MediaStreamTrack:**
- `onmute` - wraps `onMute`
- `onunmute` - wraps `onMute` (filter for false)
- `onended` - wraps `onEnded`

**Implementation approach:**
1. Create mixin `RTCEventListeners` with listener infrastructure
2. Apply to RTCPeerConnection, RTCDataChannel, MediaStreamTrack
3. Ensure cleanup in `close()` methods

**Effort: 6 hours**

---

### Phase 2: Missing Core Properties - 8 hours

| Item | Effort |
|------|--------|
| `RtcPeerConnection.onSignalingStateChange` | 1 hour |
| `RtcPeerConnection.onIceCandidateError` | 2 hours |
| `RtpTransceiver.currentDirection` | 1 hour |
| `DataChannel.negotiated` | 2 hours |
| `Candidate.toJSON()` | 1 hour |
| `SessionDescription.toJSON()` | 30 min |

**Effort: 8 hours**

---

### Phase 3: Missing Methods - 12 hours

| Item | Effort |
|------|--------|
| `RtpTransceiver.setCodecPreferences()` | 4 hours |
| `RtpSender.replaceTrack()` | 4 hours |
| `RtpSender.getStats()` | 2 hours |
| `RtpReceiver.getParameters()` | 2 hours |
| `RtpReceiver.getStats()` | 2 hours |

**Effort: 12 hours (some may overlap with existing code)**

---

### Phase 4: RTCDTMFSender (Optional) - 8 hours

Full implementation of DTMF tone generation:
- `RTCDTMFSender` class
- `insertDTMF()` method
- `toneBuffer` property
- `ontonechange` event
- RTP payload type 101 for telephone-event

**Effort: 8 hours (can be deferred)**

---

### Phase 5: Optional Enhancements - 12 hours

Lower priority items that complete the spec:
- `MediaStreamTrack.getSettings()`
- `MediaStreamTrack.getCapabilities()`
- `MediaStreamTrack.getConstraints()`
- `MediaStreamTrack.applyConstraints()`
- `RtpSender.transport` / `RtpReceiver.transport` exposure

**Effort: 12 hours (can be deferred)**

---

## Total Effort Estimate

| Phase | Description | Effort | Priority |
|-------|-------------|--------|----------|
| 1 | Rename Source to W3C Standard | 8 hours | High |
| 1.5 | Listener Layer for JS-Style Events | 6 hours | High |
| 2 | Missing Core Properties | 8 hours | High |
| 3 | Missing Methods | 12 hours | Medium |
| 4 | RTCDTMFSender | 8 hours | Low |
| 5 | Optional Enhancements | 12 hours | Low |

**Total for full W3C compatibility: ~54 hours (7 days)**
**Total for essential compatibility (Phase 1 + 1.5 + 2): ~22 hours (3 days)**

---

## Backward Compatibility Strategy

**Source renamed to W3C, old names via deprecated typedefs:**

```dart
// In webrtc_dart.dart

// NEW: Export W3C-named classes
export 'src/rtc_peer_connection.dart' show RTCPeerConnection;
export 'src/datachannel/rtc_data_channel.dart' show RTCDataChannel;
// ... etc

// DEPRECATED: Old names point to new
@Deprecated('Use RTCPeerConnection instead')
typedef RtcPeerConnection = RTCPeerConnection;

@Deprecated('Use RTCDataChannel instead')
typedef DataChannel = RTCDataChannel;
// ... etc
```

**Property aliases (deprecated old, use new):**

```dart
class RTCDataChannel {
  // W3C standard name (primary)
  int get id => _streamId;

  // Deprecated alias for backward compat
  @Deprecated('Use id instead')
  int get streamId => id;

  // W3C standard name (primary)
  RTCDataChannelState get readyState => _state;

  // Deprecated alias for backward compat
  @Deprecated('Use readyState instead')
  RTCDataChannelState get state => readyState;
}
```

---

## Dual Event Model

**Keep Dart Streams AND add JS-style listeners:**

```dart
class RTCPeerConnection {
  // === DART STYLE (keep, idiomatic for Dart) ===
  Stream<RTCIceCandidate> get onIceCandidate => _iceCandidateController.stream;

  // === W3C STYLE (add, familiar for JS developers) ===
  StreamSubscription? _onicecandidateSubscription;

  set onicecandidate(void Function(RTCIceCandidate)? callback) {
    _onicecandidateSubscription?.cancel();
    if (callback != null) {
      _onicecandidateSubscription = onIceCandidate.listen(callback);
    }
  }
}
```

**Benefits of dual approach:**
- Existing Dart users: Continue using Streams (no breaking changes)
- JS developers: Familiar `pc.onicecandidate = ...` pattern works
- Migration path: Users can adopt incrementally

---

## Recommendation

**Start with Phase 1 + 1.5 + 2** (22 hours total):
- Rename source to W3C standard names
- Add JS-style listener layer
- Add missing essential properties
- Full backward compat via deprecated typedefs
- Existing code continues to work (deprecation warnings only)

**Defer Phases 3-5** until user demand or specific use cases require them.

---

## Files to Modify

**Core renaming:**
- `lib/src/peer_connection.dart` -> `lib/src/rtc_peer_connection.dart`
- `lib/src/datachannel/data_channel.dart` -> `lib/src/datachannel/rtc_data_channel.dart`
- `lib/src/media/rtp_transceiver.dart` -> `lib/src/media/rtc_rtp_transceiver.dart`
- `lib/src/media/rtp_sender.dart` -> `lib/src/media/rtc_rtp_sender.dart`
- `lib/src/media/rtp_receiver.dart` -> `lib/src/media/rtc_rtp_receiver.dart`
- `lib/src/ice/candidate.dart` -> `lib/src/ice/rtc_ice_candidate.dart`
- `lib/src/sdp/sdp.dart` -> `lib/src/sdp/rtc_session_description.dart`

**Export file:**
- `lib/webrtc_dart.dart` - Update exports + add deprecated typedefs

**Tests:**
- Update all test imports (mostly find/replace)

**Examples:**
- Update all examples to use new names (can keep working with deprecated names initially)

---

## Testing & Commit Strategy

### Testing Approach

1. **After each class rename:**
   - Run `dart test` to verify all 2537+ unit tests pass
   - TypeDef backward compatibility ensures existing code continues to work

2. **After Phase 1 complete (all class renames):**
   - Run full unit test suite: `dart test`
   - Run Chrome interop tests: `cd interop/automated && ./run_all_tests.sh chrome`
   - Run `dart analyze` to check for issues

3. **After Phase 1.5 (listener layer):**
   - Add unit tests for listener-style event handlers
   - Verify both Stream and listener APIs work

### Commit Milestones

```
Commit 1: refactor(api): Rename RTCPeerConnection to W3C standard
  - Class: RtcPeerConnection -> RTCPeerConnection
  - File: peer_connection.dart -> rtc_peer_connection.dart
  - TypeDef: RtcPeerConnection = RTCPeerConnection (deprecated)
  - Tests: 2537 passing

Commit 2: refactor(api): Rename RTCDataChannel to W3C standard
  - Class: DataChannel -> RTCDataChannel
  - File: data_channel.dart -> rtc_data_channel.dart
  - TypeDef: DataChannel = RTCDataChannel (deprecated)

Commit 3: refactor(api): Rename RTCRtpTransceiver/Sender/Receiver
  - Classes: RtpTransceiver/RtpSender/RtpReceiver -> RTC* versions
  - TypeDefs for backward compat

Commit 4: refactor(api): Rename RTCIceCandidate and RTCSessionDescription
  - Classes: Candidate/SessionDescription -> RTC* versions
  - Property renames: host->address, transport->protocol, etc.

Commit 5: feat(api): Add JS-style listener layer (Phase 1.5)
  - onicecandidate, ontrack, ondatachannel setters
  - Wraps existing Streams

Commit 6: feat(api): Add missing W3C properties (Phase 2)
  - onSignalingStateChange, currentDirection, toJSON(), etc.
```

### Verification Checklist

- [ ] All 2537+ unit tests pass
- [ ] Chrome interop tests pass (22/22)
- [ ] `dart analyze` reports no issues
- [ ] Deprecated typedefs work (no breaking changes)
- [ ] README version updated
- [ ] CHANGELOG updated
