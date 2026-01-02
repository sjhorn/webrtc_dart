import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/sctp/inbound_stream.dart';
import 'package:webrtc_dart/src/sctp/packet.dart';

final _log = WebRtcLogging.sctp;

/// Cookie constants (matching werift: packages/sctp/src/sctp.ts)
const int _cookieLength = 24; // 4 bytes timestamp + 20 bytes HMAC-SHA1
const int _cookieLifetime = 60; // seconds

/// SCTP Association State
/// RFC 4960 Section 4
enum SctpAssociationState {
  closed,
  cookieWait,
  cookieEchoed,
  established,
  shutdownPending,
  shutdownSent,
  shutdownReceived,
  shutdownAckSent,
}

/// Wrapper for sent DATA chunks with retransmission metadata
/// Follows werift pattern for tracking chunk state
class _SentChunk {
  final SctpDataChunk chunk;

  /// Number of times this chunk has been sent
  int sentCount = 0;

  /// Time when chunk was last sent (seconds since epoch)
  double? sentTime;

  /// Number of times this chunk was missing in gap ack blocks
  int misses = 0;

  /// Whether this chunk needs to be retransmitted
  bool retransmit = false;

  /// Whether this chunk has been acknowledged (via gap blocks)
  bool acked = false;

  /// Whether this chunk has been abandoned (partial reliability)
  bool abandoned = false;

  /// Expiry time for timed partial reliability (seconds since epoch)
  /// If set, chunk is abandoned when current time > expiry
  double? expiry;

  /// Max retransmit count for rexmit partial reliability
  /// If set, chunk is abandoned when sentCount > maxRetransmits
  int? maxRetransmits;

  /// Size of user data for flight size tracking
  int get bookSize => chunk.userData.length;

  /// TSN from the chunk
  int get tsn => chunk.tsn;

  _SentChunk(this.chunk, {this.expiry, this.maxRetransmits});
}

/// SCTP Association
/// Manages the state and lifecycle of an SCTP association
class SctpAssociation {
  /// Local port
  final int localPort;

  /// Remote port
  final int remotePort;

  /// Local verification tag
  final int _localVerificationTag;

  /// Remote verification tag
  int? _remoteVerificationTag;

  /// Current state
  SctpAssociationState _state = SctpAssociationState.closed;

  /// Local initial TSN
  final int _localInitialTsn;

  /// Local TSN (next to be sent)
  int _localTsn;

  /// Remote TSN (cumulative ack point)
  int _remoteCumulativeTsn = 0;

  /// Last SACKed TSN (null until first SACK received)
  int? _lastSackedTsn;

  /// Advanced peer ack point for partial reliability (RFC 3758)
  int _advancedPeerAckTsn = 0;

  /// Pending FORWARD-TSN chunk to send
  SctpForwardTsnChunk? _forwardTsnChunk;

  /// Number of outbound streams
  final int outboundStreams;

  /// Number of inbound streams
  final int inboundStreams;

  /// Advertised receive window
  int advertisedRwnd;

  /// Outbound queue - chunks waiting to be sent
  List<_SentChunk> _outboundQueue = [];

  /// Sent queue - chunks sent but not yet ACKed
  List<_SentChunk> _sentQueue = [];

  /// Per-stream buffered amount (bytes queued but not yet ACKed)
  /// Used by DataChannel for flow control per W3C WebRTC spec
  final Map<int, int> _streamBufferedAmount = {};

  /// Callback when buffered amount changes for a stream
  /// Called with (streamId, newBufferedAmount)
  void Function(int streamId, int bufferedAmount)? onBufferedAmountChange;

  /// Receive buffer (by TSN)
  final Map<int, SctpDataChunk> _receiveBuffer = {};

  /// Outbound stream sequence numbers (per stream ID)
  final Map<int, int> _outboundStreamSeq = {};

  /// Set of misordered TSNs (gaps in received sequence)
  Set<int> _sackMisOrdered = {};

  /// List of duplicate TSNs received
  List<int> _sackDuplicates = [];

  /// Inbound streams for fragment reassembly (per stream ID)
  /// Reference: werift-webrtc inboundStreams field
  final Map<int, InboundStream> _inboundStreams = {};

  /// Last received TSN
  int? _lastReceivedTsn;

  /// Callback for sending packets
  final Future<void> Function(Uint8List packet) onSendPacket;

  /// Callback for receiving data
  final void Function(int streamId, Uint8List data, int ppid)? onReceiveData;

  /// Timer T1 - wait for INIT-ACK or COOKIE-ACK
  Timer? _t1Timer;
  SctpChunk? _t1Chunk;
  int? _t1VerificationTag; // Verification tag to use for retransmission
  int _t1Failures = 0;

  /// Timer T2 - wait for SHUTDOWN
  Timer? _t2Timer;
  SctpChunk? _t2Chunk;
  int _t2Failures = 0;

  /// Timer T3 - wait for DATA SACK (retransmission timer)
  Timer? _t3Timer;

  /// Timer for SACK
  Timer? _sackTimer;
  bool _sackNeeded = false;

  /// Retransmission timeout (RTO) in milliseconds
  int _rto = SctpConstants.rtoInitial;

  /// Smoothed RTT
  double? _srtt;

  /// RTT variance
  double? _rttvar;

  /// Congestion window
  int _cwnd = SctpConstants.initialCwnd;

  /// Slow start threshold
  int _ssthresh = SctpConstants.initialCwnd;

  /// Bytes in flight (sent but not ACKed)
  int _flightSize = 0;

  /// Partial bytes acknowledged (for congestion avoidance)
  int _partialBytesAcked = 0;

  /// Fast recovery exit TSN
  int? _fastRecoveryExit;

  /// Fast recovery transmit flag
  bool _fastRecoveryTransmit = false;

  /// State cookie (for server)
  Uint8List? _stateCookie;

  /// HMAC key for cookie generation/verification (matching werift)
  late final Uint8List _hmacKey;

  /// Random number generator
  final Random _random;

  /// State change stream
  final _stateController = StreamController<SctpAssociationState>.broadcast();

  // ============================================================================
  // Stream Reconfiguration (RFC 6525)
  // ============================================================================

  /// Queue of stream IDs pending reconfiguration
  List<int> reconfigQueue = [];

  /// Reconfig request sequence number (initialized to localTsn)
  late int _reconfigRequestSeq;

  /// Reconfig response sequence number (for tracking incoming requests)
  int _reconfigResponseSeq = 0;

  /// Current pending reconfig request (null if none in flight)
  OutgoingSsnResetRequestParam? _reconfigRequest;

  /// Timer for reconfig request retransmission
  Timer? _reconfigTimer;

  /// Callback when streams are reset (for closing data channels)
  void Function(List<int> streamIds)? onReconfigStreams;

  /// Callback when streams are added (RFC 6525 Add Streams)
  void Function(int newStreams)? onStreamsAdded;

  /// Current number of inbound streams (can increase via Add Streams)
  late int _currentInboundStreams;

  SctpAssociation({
    required this.localPort,
    required this.remotePort,
    required this.onSendPacket,
    this.onReceiveData,
    this.outboundStreams = SctpConstants.defaultOutboundStreams,
    this.inboundStreams = SctpConstants.defaultInboundStreams,
    this.advertisedRwnd = SctpConstants.defaultAdvertisedRwnd,
    Random? random,
  })  : _random = random ?? Random.secure(),
        _localVerificationTag = _generateVerificationTag(random),
        _localInitialTsn = _generateInitialTsn(random),
        // Initialize _localTsn to same value, will be set properly in the line after
        _localTsn = 0 {
    // _localTsn must start at _localInitialTsn
    _localTsn = _localInitialTsn;
    // Initialize current inbound streams to the negotiated count
    _currentInboundStreams = inboundStreams;
    // Reconfig request sequence starts at localTsn (per RFC 6525)
    _reconfigRequestSeq = _localInitialTsn;
    // Generate random HMAC key for cookie generation/verification (matching werift)
    _hmacKey = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      _hmacKey[i] = _random.nextInt(256);
    }
  }

  /// Get current state
  SctpAssociationState get state => _state;

  /// Stream of state changes
  Stream<SctpAssociationState> get onStateChange => _stateController.stream;

  /// Get local verification tag
  int get localVerificationTag => _localVerificationTag;

  /// Get remote verification tag
  int? get remoteVerificationTag => _remoteVerificationTag;

  /// Get current number of inbound streams (may increase via Add Streams)
  int get currentInboundStreams => _currentInboundStreams;

  /// Start association as client (send INIT)
  Future<void> connect() async {
    _log.fine(
        '[SCTP] connect: state=$_state, localTag=0x${_localVerificationTag.toRadixString(16)}, localTsn=$_localInitialTsn');
    if (_state != SctpAssociationState.closed) {
      throw StateError('Association already started');
    }

    _log.fine(' connect: sending INIT');
    final initChunk = SctpInitChunk(
      initiateTag: _localVerificationTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: _localInitialTsn,
    );
    await _sendChunk(initChunk, verificationTag: 0);
    _setState(SctpAssociationState.cookieWait);
    _t1Start(initChunk, verificationTag: 0);
  }

  /// Handle incoming SCTP packet
  Future<void> handlePacket(Uint8List data) async {
    _log.fine(' handlePacket: ${data.length} bytes, state=$_state');
    _log.fine(
        '[SCTP]   first 16 bytes: ${data.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    final packet = SctpPacket.parse(data);
    _log.fine(
        '[SCTP]   parsed: srcPort=${packet.sourcePort}, dstPort=${packet.destinationPort}, verTag=0x${packet.verificationTag.toRadixString(16)}, chunks=${packet.chunks.length}');

    // Verify verification tag (except for INIT and SHUTDOWN-COMPLETE)
    if (!_verifyVerificationTag(packet)) {
      // Silently discard
      _log.fine(
          '[SCTP]   verification tag mismatch - discarding (expected 0x${_localVerificationTag.toRadixString(16)}, got 0x${packet.verificationTag.toRadixString(16)})');
      return;
    }

    // Process each chunk
    for (final chunk in packet.chunks) {
      _log.fine('   processing chunk type=${chunk.type}');
      await _handleChunk(chunk);
    }
  }

  /// Send data on a stream
  ///
  /// Partial reliability (RFC 3758) options:
  /// - [expiry]: Absolute expiration time in seconds since epoch. Data is
  ///   abandoned if not acknowledged before this time.
  /// - [maxRetransmits]: Maximum number of retransmissions. Data is abandoned
  ///   if this count is exceeded.
  ///
  /// Note: Only one of [expiry] or [maxRetransmits] should be set.
  Future<void> sendData({
    required int streamId,
    required Uint8List data,
    required int ppid,
    bool unordered = false,
    double? expiry,
    int? maxRetransmits,
  }) async {
    if (_state != SctpAssociationState.established) {
      throw StateError('Association not established');
    }

    if (streamId >= outboundStreams) {
      throw ArgumentError('Invalid stream ID: $streamId');
    }

    // Get stream sequence number for ordered delivery
    final streamSeq = unordered ? 0 : (_outboundStreamSeq[streamId] ?? 0);

    // Fragment large data if needed
    final maxDataSize = SctpConstants.userDataMaxLength;
    final fragments = (data.length / maxDataSize).ceil();
    if (fragments == 0) {
      // Empty data - single chunk
      final chunk = SctpDataChunk(
        tsn: _getNextTsn(),
        streamId: streamId,
        streamSeq: streamSeq,
        ppid: ppid,
        userData: data,
        flags: (unordered ? SctpDataChunkFlags.unordered : 0) |
            SctpDataChunkFlags.beginningFragment |
            SctpDataChunkFlags.endFragment,
      );
      _outboundQueue.add(
          _SentChunk(chunk, expiry: expiry, maxRetransmits: maxRetransmits));
    } else {
      for (var i = 0; i < fragments; i++) {
        final start = i * maxDataSize;
        final end = min((i + 1) * maxDataSize, data.length);
        final fragment = data.sublist(start, end);

        var flags = unordered ? SctpDataChunkFlags.unordered : 0;
        if (i == 0) flags |= SctpDataChunkFlags.beginningFragment;
        if (i == fragments - 1) flags |= SctpDataChunkFlags.endFragment;

        final chunk = SctpDataChunk(
          tsn: _getNextTsn(),
          streamId: streamId,
          streamSeq: streamSeq,
          ppid: ppid,
          userData: fragment,
          flags: flags,
        );
        _outboundQueue.add(
            _SentChunk(chunk, expiry: expiry, maxRetransmits: maxRetransmits));
      }
    }

    // Increment sequence number for ordered messages
    if (!unordered) {
      _outboundStreamSeq[streamId] = (streamSeq + 1) & 0xFFFF;
    }

    // Update buffered amount for this stream
    _updateBufferedAmount(streamId, data.length);

    // Transmit if T3 is not running, otherwise queue for later
    // Non-blocking per W3C spec - applications use bufferedAmount for flow control
    _log.fine(
        '[SCTP] sendData: streamId=$streamId, ppid=$ppid, data=${data.length} bytes, t3=${_t3Timer != null}');
    if (_t3Timer == null) {
      _log.fine('[SCTP] sendData: calling _transmit()');
      await _transmit();
      _log.fine('[SCTP] sendData: _transmit() completed');
    } else {
      // Non-blocking: data queued, will be sent when T3 fires or SACK received
      // Applications should use bufferedAmount for flow control (W3C WebRTC spec)
      _log.fine('[SCTP] sendData: T3 running, data queued for later transmission');
    }
  }

  /// Close association gracefully
  Future<void> close() async {
    if (_state == SctpAssociationState.closed) {
      return;
    }

    if (_state == SctpAssociationState.established) {
      _setState(SctpAssociationState.shutdownPending);
      final shutdownChunk =
          SctpShutdownChunk(cumulativeTsnAck: _remoteCumulativeTsn);
      await _sendChunk(shutdownChunk);
      _setState(SctpAssociationState.shutdownSent);
      _t2Start(shutdownChunk);
    }
  }

  /// Abort association
  Future<void> abort({Uint8List? cause}) async {
    final abortChunk = SctpAbortChunk(causes: cause);
    await _sendChunk(abortChunk, verificationTag: _remoteVerificationTag ?? 0);
    _dispose();
  }

  /// Send a single chunk
  Future<void> _sendChunk(SctpChunk chunk, {int? verificationTag}) async {
    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: verificationTag ?? _remoteVerificationTag!,
      chunks: [chunk],
    );
    final data = packet.serialize();
    if (chunk.type == SctpChunkType.data) {
      _log.fine('[SCTP] _sendChunk DATA: ${data.length} bytes');
      _log.fine(
          '[SCTP] _sendChunk DATA hex: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    await onSendPacket(data);
  }

  /// Check if a chunk should be abandoned (RFC 3758 partial reliability)
  ///
  /// When a chunk is abandoned, all chunks in the same message are also
  /// marked as abandoned. Returns true if the chunk is (or becomes) abandoned.
  bool _maybeAbandon(_SentChunk chunk) {
    if (chunk.abandoned) return true;

    // Check if limits are exceeded
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final abandon = (chunk.maxRetransmits != null &&
            chunk.sentCount > chunk.maxRetransmits!) ||
        (chunk.expiry != null && chunk.expiry! < now);

    if (!abandon) return false;

    // Find this chunk's position in sentQueue
    final chunkIdx = _sentQueue.indexOf(chunk);
    if (chunkIdx < 0) return false;

    // Mark backward to beginning of message (FIRST_FRAG)
    for (var i = chunkIdx; i >= 0; i--) {
      final c = _sentQueue[i];
      c.abandoned = true;
      c.retransmit = false;
      if (c.chunk.beginningFragment) break;
    }

    // Mark forward to end of message (LAST_FRAG)
    for (var i = chunkIdx; i < _sentQueue.length; i++) {
      final c = _sentQueue[i];
      c.abandoned = true;
      c.retransmit = false;
      if (c.chunk.endFragment) break;
    }

    return true;
  }

  /// Update advanced peer ack point and generate FORWARD-TSN (RFC 3758)
  ///
  /// Dequeues abandoned chunks from the front of sentQueue and
  /// creates a FORWARD-TSN chunk to notify the peer.
  void _updateAdvancedPeerAckPoint() {
    if (_lastSackedTsn != null && uint32Gt(_lastSackedTsn!, _advancedPeerAckTsn)) {
      _advancedPeerAckTsn = _lastSackedTsn!;
    }

    var done = 0;
    final streams = <int, int>{}; // streamId -> streamSeq

    // Dequeue abandoned chunks from front of sentQueue
    // Optimized: process in-place first, then batch remove with removeRange
    var removeCount = 0;
    for (var i = 0; i < _sentQueue.length; i++) {
      final chunk = _sentQueue[i];
      if (!chunk.abandoned) break;

      _advancedPeerAckTsn = chunk.tsn;
      removeCount++;
      done++;

      // Decrement buffered amount for abandoned chunk
      _decrementBufferedAmount(chunk);

      // Track stream sequence numbers for ordered chunks
      if (!chunk.chunk.unordered) {
        streams[chunk.chunk.streamId] = chunk.chunk.streamSeq;
      }
    }
    if (removeCount > 0) {
      _sentQueue.removeRange(0, removeCount);
    }

    if (done > 0) {
      // Create FORWARD-TSN chunk
      _forwardTsnChunk = SctpForwardTsnChunk(
        newCumulativeTsn: _advancedPeerAckTsn,
        streams: streams.entries
            .map((e) => ForwardTsnStream(streamId: e.key, streamSeq: e.value))
            .toList(),
      );
    }
  }

  /// Transmit outbound data (RFC 4960 Section 6.1)
  Future<void> _transmit() async {
    _log.fine(
        '[SCTP] _transmit: outboundQueue=${_outboundQueue.length}, sentQueue=${_sentQueue.length}');

    // Send FORWARD-TSN first (RFC 3758)
    if (_forwardTsnChunk != null) {
      try {
        await _sendChunk(_forwardTsnChunk!);
      } catch (e) {
        _log.fine('[SCTP] Failed to send FORWARD-TSN: $e');
      }
      _forwardTsnChunk = null;

      if (_t3Timer == null && _sentQueue.isNotEmpty) {
        _t3Start();
      }
    }

    // Calculate effective cwnd for this burst
    final burstSize = _fastRecoveryExit != null
        ? 2 * SctpConstants.userDataMaxLength
        : 4 * SctpConstants.userDataMaxLength;
    final cwnd = min(_flightSize + burstSize, _cwnd);
    _log.fine('[SCTP] _transmit: cwnd=$cwnd, flightSize=$_flightSize');

    // First, retransmit marked chunks from sentQueue
    var retransmitEarliest = true;
    for (final sentChunk in _sentQueue) {
      if (sentChunk.retransmit) {
        if (_fastRecoveryTransmit) {
          _fastRecoveryTransmit = false;
        } else if (_flightSize >= cwnd) {
          return;
        }

        _flightSizeIncrease(sentChunk);
        sentChunk.misses = 0;
        sentChunk.retransmit = false;
        sentChunk.sentCount++;

        await _sendChunk(sentChunk.chunk);

        if (retransmitEarliest) {
          _t3Restart();
        }
      }
      retransmitEarliest = false;
    }

    // Then send new chunks from outboundQueue (with cwnd check)
    while (_outboundQueue.isNotEmpty) {
      // Check cwnd before sending new data (congestion control)
      if (_flightSize >= cwnd) {
        break; // Stop sending, wait for SACKs to free up cwnd
      }

      final sentChunk = _outboundQueue.removeAt(0);
      _sentQueue.add(sentChunk);
      _flightSizeIncrease(sentChunk);

      sentChunk.sentCount++;
      sentChunk.sentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

      _log.fine(
          '[SCTP] _transmit: sending DATA chunk tsn=${sentChunk.chunk.tsn}');
      await _sendChunk(sentChunk.chunk);
      _log.fine('[SCTP] _transmit: DATA chunk sent');

      if (_t3Timer == null) {
        _t3Start();
      }
    }

    // Reset outbound queue to avoid V8-style performance issues
    // Only reset if empty (may still have chunks if cwnd limited)
    if (_outboundQueue.isEmpty) {
      _outboundQueue = [];
    }
  }

  /// Handle incoming chunk
  Future<void> _handleChunk(SctpChunk chunk) async {
    switch (chunk.type) {
      case SctpChunkType.init:
        await _handleInit(chunk as SctpInitChunk);
        break;
      case SctpChunkType.initAck:
        await _handleInitAck(chunk as SctpInitAckChunk);
        break;
      case SctpChunkType.cookieEcho:
        await _handleCookieEcho(chunk as SctpCookieEchoChunk);
        break;
      case SctpChunkType.cookieAck:
        await _handleCookieAck();
        break;
      case SctpChunkType.data:
        await _handleData(chunk as SctpDataChunk);
        break;
      case SctpChunkType.sack:
        await _handleSack(chunk as SctpSackChunk);
        break;
      case SctpChunkType.shutdown:
        await _handleShutdown(chunk as SctpShutdownChunk);
        break;
      case SctpChunkType.shutdownAck:
        await _handleShutdownAck();
        break;
      case SctpChunkType.shutdownComplete:
        await _handleShutdownComplete();
        break;
      case SctpChunkType.abort:
        await _handleAbort();
        break;
      case SctpChunkType.forwardTsn:
        await _handleForwardTsn(chunk as SctpForwardTsnChunk);
        break;
      case SctpChunkType.reconfig:
        await _handleReconfig(chunk as SctpReconfigChunk);
        break;
      default:
        // Ignore unknown chunks
        break;
    }
  }

  /// Handle INIT chunk (matching werift: packages/sctp/src/sctp.ts)
  Future<void> _handleInit(SctpInitChunk chunk) async {
    _log.fine(
        '[SCTP] _handleInit: state=$_state, remoteTag=0x${chunk.initiateTag.toRadixString(16)}, remoteTsn=${chunk.initialTsn}');

    if (_state != SctpAssociationState.closed) {
      // Ignore INIT in non-closed state (matching werift: `if (!this.isServer) return`)
      // RFC 4960 Section 5.2 defines collision handling, but werift simply ignores
      _log.fine(' _handleInit: ignoring INIT in state $_state');
      return;
    }

    _remoteVerificationTag = chunk.initiateTag;
    _remoteCumulativeTsn = _tsnMinusOne(chunk.initialTsn);
    _lastReceivedTsn = _remoteCumulativeTsn;

    _log.fine(
        '[SCTP] _handleInit: sending INIT-ACK with localTag=0x${_localVerificationTag.toRadixString(16)}');
    await _sendInitAck();
  }

  /// Handle INIT-ACK chunk
  Future<void> _handleInitAck(SctpInitAckChunk chunk) async {
    _log.fine(
        '[SCTP] _handleInitAck: state=$_state, remoteTag=0x${chunk.initiateTag.toRadixString(16)}');

    if (_state != SctpAssociationState.cookieWait) {
      _log.fine(' _handleInitAck: ignoring INIT-ACK in state $_state');
      return;
    }

    _t1Cancel();

    _remoteVerificationTag = chunk.initiateTag;
    _remoteCumulativeTsn = _tsnMinusOne(chunk.initialTsn);
    _lastReceivedTsn = _remoteCumulativeTsn;

    // Extract state cookie from parameters
    final stateCookie = chunk.getStateCookie();
    _log.fine(
        '[SCTP] _handleInitAck: stateCookie=${stateCookie != null ? '${stateCookie.length} bytes' : 'null'}');
    if (stateCookie != null) {
      _log.fine(' _handleInitAck: sending COOKIE-ECHO');
      final cookieEchoChunk = SctpCookieEchoChunk(cookie: stateCookie);
      await _sendChunk(cookieEchoChunk);
      _setState(SctpAssociationState.cookieEchoed);
      // For COOKIE-ECHO retransmission, use remote verification tag
      _t1Start(cookieEchoChunk, verificationTag: _remoteVerificationTag);
    }
  }

  /// Handle COOKIE-ECHO chunk (matching werift: packages/sctp/src/sctp.ts)
  Future<void> _handleCookieEcho(SctpCookieEchoChunk chunk) async {
    _log.fine(
        '[SCTP] _handleCookieEcho: state=$_state, cookie=${chunk.cookie.length} bytes');

    // Verify cookie (matching werift cookie verification)
    final cookie = chunk.cookie;

    // Check cookie length
    if (cookie.length != _cookieLength) {
      _log.fine(
          '[SCTP] _handleCookieEcho: invalid cookie length ${cookie.length}, expected $_cookieLength');
      return;
    }

    // Verify HMAC
    final timestampBytes = cookie.sublist(0, 4);
    final receivedDigest = cookie.sublist(4, _cookieLength);

    final hmac = Hmac(sha1, _hmacKey);
    final expectedDigest = hmac.convert(timestampBytes);

    // Compare digests
    var digestMatch = true;
    for (var i = 0; i < 20; i++) {
      if (receivedDigest[i] != expectedDigest.bytes[i]) {
        digestMatch = false;
        break;
      }
    }

    if (!digestMatch) {
      _log.fine(' _handleCookieEcho: cookie HMAC verification failed');
      return;
    }

    // Check timestamp for expiry
    final bd = ByteData.sublistView(Uint8List.fromList(timestampBytes));
    final cookieTimestamp = bd.getUint32(0);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (cookieTimestamp < now - _cookieLifetime || cookieTimestamp > now) {
      _log.fine(
          '[SCTP] _handleCookieEcho: cookie expired (timestamp=$cookieTimestamp, now=$now)');
      // Send ERROR chunk with Stale Cookie Error (matching werift: packages/sctp/src/sctp.ts)
      await _sendChunk(SctpErrorChunk.staleCookie());
      return;
    }

    _log.fine(' _handleCookieEcho: cookie verified, sending COOKIE-ACK');
    await _sendChunk(SctpCookieAckChunk());
    _setState(SctpAssociationState.established);
  }

  /// Handle COOKIE-ACK chunk
  Future<void> _handleCookieAck() async {
    _log.fine(' _handleCookieAck: state=$_state');
    if (_state != SctpAssociationState.cookieEchoed) {
      _log.fine(' _handleCookieAck: ignoring in state $_state');
      return;
    }

    _t1Cancel();
    _log.fine(' _handleCookieAck: association established!');
    _setState(SctpAssociationState.established);
  }

  /// Handle DATA chunk
  /// Reference: werift-webrtc/packages/sctp/src/sctp.ts receiveDataChunk
  Future<void> _handleData(SctpDataChunk chunk) async {
    if (_state != SctpAssociationState.established) {
      return;
    }

    _sackNeeded = true;

    // Mark received and check for duplicates
    final isDuplicate = _markReceived(chunk.tsn);
    if (isDuplicate) {
      _scheduleSack();
      return;
    }

    // Store in receive buffer (for SACK generation)
    _receiveBuffer[chunk.tsn] = chunk;
    _scheduleSack();

    // Add chunk to inbound stream for reassembly
    final inboundStream = _getInboundStream(chunk.streamId);
    inboundStream.addChunk(chunk);
    advertisedRwnd -= chunk.userData.length;

    // Deliver complete messages (handles both fragmented and unfragmented)
    for (final (streamId, data, ppid) in inboundStream.popMessages()) {
      advertisedRwnd += data.length;
      if (onReceiveData != null) {
        onReceiveData!(streamId, data, ppid);
      }
    }
  }

  /// Get or create inbound stream for fragment reassembly
  InboundStream _getInboundStream(int streamId) {
    return _inboundStreams.putIfAbsent(streamId, () => InboundStream());
  }

  /// Handle SACK chunk (RFC 4960 Section 6.2.1)
  Future<void> _handleSack(SctpSackChunk chunk) async {
    // Ignore old SACKs (but accept first SACK when _lastSackedTsn is null)
    if (_lastSackedTsn != null && uint32Gt(_lastSackedTsn!, chunk.cumulativeTsnAck)) {
      return;
    }

    final receivedTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _lastSackedTsn = chunk.cumulativeTsnAck;
    final cwndFullyUtilized = _flightSize >= _cwnd;
    var done = 0;
    var doneBytes = 0;

    // Handle acknowledged data (remove from sentQueue)
    // Optimized: process in-place first, then batch remove with removeRange
    // This changes O(n²) repeated removeAt(0) to O(n) single removeRange
    var removeCount = 0;
    for (var i = 0; i < _sentQueue.length; i++) {
      final sChunk = _sentQueue[i];
      if (!uint32Gte(_lastSackedTsn!, sChunk.tsn)) break;

      removeCount++;
      done++;
      if (!sChunk.acked) {
        doneBytes += sChunk.bookSize;
        _flightSizeDecrease(sChunk);
      }

      // Decrement buffered amount for this stream
      _decrementBufferedAmount(sChunk);

      // Update RTO based on first ACKed chunk that was sent only once
      if (done == 1 && sChunk.sentCount == 1 && sChunk.sentTime != null) {
        _updateRto(receivedTime - sChunk.sentTime!);
      }
    }
    if (removeCount > 0) {
      _sentQueue.removeRange(0, removeCount);
    }

    // Reset sentQueue to avoid memory leaks from internal array slack
    if (_sentQueue.isEmpty) {
      _sentQueue = [];
    }

    // Handle gap ack blocks
    var loss = false;
    if (chunk.gapAckBlocks.isNotEmpty) {
      final seen = <int>{};
      int? highestSeenTsn;

      for (final gap in chunk.gapAckBlocks) {
        for (var pos = gap.start; pos <= gap.end; pos++) {
          highestSeenTsn =
              (chunk.cumulativeTsnAck + pos) % SctpConstants.tsnModulo;
          seen.add(highestSeenTsn);
        }
      }

      var highestNewlyAcked = chunk.cumulativeTsnAck;
      for (final sChunk in _sentQueue) {
        if (highestSeenTsn != null && uint32Gt(sChunk.tsn, highestSeenTsn)) {
          break;
        }
        if (seen.contains(sChunk.tsn) && !sChunk.acked) {
          doneBytes += sChunk.bookSize;
          sChunk.acked = true;
          _flightSizeDecrease(sChunk);
          highestNewlyAcked = sChunk.tsn;
        }
      }

      // Strike missing chunks prior to highest newly acked (fast retransmit)
      for (final sChunk in _sentQueue) {
        if (uint32Gt(sChunk.tsn, highestNewlyAcked)) {
          break;
        }
        if (!seen.contains(sChunk.tsn)) {
          sChunk.misses++;
          if (sChunk.misses == 3) {
            sChunk.misses = 0;
            // Try to abandon if partial reliability is enabled, otherwise retransmit
            if (!_maybeAbandon(sChunk)) {
              sChunk.retransmit = true;
            }
            sChunk.acked = false;
            _flightSizeDecrease(sChunk);
            loss = true;
          }
        }
      }
    }

    // Update advanced peer ack point for partial reliability
    _updateAdvancedPeerAckPoint();

    // Adjust congestion window (RFC 4960 Section 7.2)
    if (_fastRecoveryExit == null) {
      if (done > 0 && cwndFullyUtilized) {
        if (_cwnd <= _ssthresh) {
          // Slow start
          _cwnd += min(doneBytes, SctpConstants.userDataMaxLength);
        } else {
          // Congestion avoidance
          _partialBytesAcked += doneBytes;
          if (_partialBytesAcked >= _cwnd) {
            _partialBytesAcked -= _cwnd;
            _cwnd += SctpConstants.userDataMaxLength;
          }
        }
      }
      if (loss) {
        // Enter fast recovery
        _ssthresh = max(_cwnd ~/ 2, 4 * SctpConstants.userDataMaxLength);
        _cwnd = _ssthresh;
        _partialBytesAcked = 0;
        if (_sentQueue.isNotEmpty) {
          _fastRecoveryExit = _sentQueue.last.tsn;
        }
        _fastRecoveryTransmit = true;
      }
    } else if (uint32Gte(chunk.cumulativeTsnAck, _fastRecoveryExit!)) {
      // Exit fast recovery
      _fastRecoveryExit = null;
    }

    // Manage T3 timer
    if (_sentQueue.isEmpty) {
      _t3Cancel();
    } else if (done > 0) {
      _t3Restart();
    }

    // Transmit pending data
    await _transmit();
  }

  /// Handle FORWARD-TSN chunk (RFC 3758)
  /// Reference: werift-webrtc/packages/sctp/src/sctp.ts receiveForwardTsnChunk
  Future<void> _handleForwardTsn(SctpForwardTsnChunk chunk) async {
    _sackNeeded = true;

    if (_lastReceivedTsn != null &&
        uint32Gte(_lastReceivedTsn!, chunk.newCumulativeTsn)) {
      return;
    }

    // Advance cumulative TSN
    _lastReceivedTsn = chunk.newCumulativeTsn;
    _sackMisOrdered = _sackMisOrdered
        .where((tsn) => uint32Gt(tsn, _lastReceivedTsn!))
        .toSet();

    // Update cumulative TSN based on misordered set
    for (final tsn in _sackMisOrdered.toList()..sort()) {
      if (tsn == _tsnPlusOne(_lastReceivedTsn!)) {
        _lastReceivedTsn = tsn;
      } else {
        break;
      }
    }

    // Filter out obsolete entries
    _sackDuplicates = _sackDuplicates
        .where((tsn) => uint32Gt(tsn, _lastReceivedTsn!))
        .toList();
    _sackMisOrdered = _sackMisOrdered
        .where((tsn) => uint32Gt(tsn, _lastReceivedTsn!))
        .toSet();

    // Update reassembly - advance stream sequence numbers and deliver pending messages
    for (final stream in chunk.streams) {
      final inboundStream = _getInboundStream(stream.streamId);

      // Advance sequence number (uint16Add equivalent)
      inboundStream.streamSequenceNumber = (stream.streamSeq + 1) & 0xFFFF;

      // Deliver any pending messages
      for (final (streamId, data, ppid) in inboundStream.popMessages()) {
        advertisedRwnd += data.length;
        if (onReceiveData != null) {
          onReceiveData!(streamId, data, ppid);
        }
      }
    }

    // Prune obsolete chunks from all inbound streams
    for (final inboundStream in _inboundStreams.values) {
      advertisedRwnd += inboundStream.pruneChunks(_lastReceivedTsn!);
    }

    _scheduleSack();
  }

  /// Handle SHUTDOWN chunk
  Future<void> _handleShutdown(SctpShutdownChunk chunk) async {
    if (_state == SctpAssociationState.established) {
      _setState(SctpAssociationState.shutdownReceived);
      await _sendChunk(SctpShutdownAckChunk());
      _setState(SctpAssociationState.shutdownAckSent);
    }
  }

  /// Handle SHUTDOWN-ACK chunk
  Future<void> _handleShutdownAck() async {
    if (_state == SctpAssociationState.shutdownSent) {
      _t2Cancel();
      await _sendChunk(SctpShutdownCompleteChunk());
      _dispose();
    }
  }

  /// Handle SHUTDOWN-COMPLETE chunk
  Future<void> _handleShutdownComplete() async {
    _dispose();
  }

  /// Handle ABORT chunk
  Future<void> _handleAbort() async {
    _dispose();
  }

  // ============================================================================
  // Stream Reconfiguration (RFC 6525) Implementation
  // ============================================================================

  /// Handle RECONFIG chunk
  Future<void> _handleReconfig(SctpReconfigChunk chunk) async {
    for (final param in chunk.params) {
      if (param is OutgoingSsnResetRequestParam) {
        await _handleOutgoingSsnResetRequest(param);
      } else if (param is StreamAddOutgoingParam) {
        await _handleStreamAddOutgoing(param);
      } else if (param is ReconfigResponseParam) {
        await _handleReconfigResponse(param);
      }
    }
  }

  /// Handle incoming Outgoing SSN Reset Request
  /// (The remote peer wants to close streams)
  Future<void> _handleOutgoingSsnResetRequest(
      OutgoingSsnResetRequestParam param) async {
    // Update our response sequence to match the incoming request
    _reconfigResponseSeq = param.requestSequence;

    // Send response acknowledging the reset
    final response = ReconfigResponseParam(
      responseSequence: param.requestSequence,
      result: ReconfigResult.successPerformed,
    );

    final chunk = SctpReconfigChunk(params: [response]);
    await _sendChunk(chunk);

    // Notify the data channel layer about the reset streams
    // This will trigger the data channels to close
    if (param.streams.isNotEmpty) {
      // Send our own reset request for the same streams
      await transmitReconfigRequest();

      // Notify about closed streams
      onReconfigStreams?.call(param.streams);
    }
  }

  /// Handle incoming Add Outgoing Streams Request (RFC 6525 Section 4.5)
  /// (The remote peer wants to add more outgoing streams, which become our inbound streams)
  Future<void> _handleStreamAddOutgoing(StreamAddOutgoingParam param) async {
    // Increase our inbound stream count
    _currentInboundStreams += param.newStreams;

    // Update our response sequence to match the incoming request
    _reconfigResponseSeq = param.requestSequence;

    // Send success response
    final response = ReconfigResponseParam(
      responseSequence: param.requestSequence,
      result: ReconfigResult.successPerformed,
    );

    final chunk = SctpReconfigChunk(params: [response]);
    await _sendChunk(chunk);

    // Notify about added streams
    onStreamsAdded?.call(param.newStreams);

    _log.fine(
        ' Accepted ${param.newStreams} new streams, total inbound: $_currentInboundStreams');
  }

  /// Handle incoming Reconfig Response
  /// (Response to our outgoing reset request)
  Future<void> _handleReconfigResponse(ReconfigResponseParam param) async {
    if (_reconfigRequest == null) {
      return; // No pending request
    }

    if (param.result != ReconfigResult.successPerformed) {
      _log.fine(' Reconfig request failed: result=${param.result}');
      return;
    }

    // Check if this response matches our pending request
    if (param.responseSequence == _reconfigRequest!.requestSequence) {
      // Success - clear the pending request and notify about closed streams
      final closedStreams = _reconfigRequest!.streams.toList();
      _reconfigRequest = null;

      // Cancel reconfig timer
      _reconfigTimer?.cancel();
      _reconfigTimer = null;

      // Remove stream sequence tracking
      for (final streamId in closedStreams) {
        _outboundStreamSeq.remove(streamId);
      }

      // Notify about closed streams
      onReconfigStreams?.call(closedStreams);

      // Continue with any remaining streams in the queue
      await transmitReconfigRequest();
    }
  }

  /// Transmit a reconfig request for queued streams
  /// This is the main entry point for initiating stream reset
  Future<void> transmitReconfigRequest() async {
    // Only send if:
    // 1. We have streams queued
    // 2. Association is established
    // 3. No pending request in flight
    if (reconfigQueue.isEmpty ||
        _state != SctpAssociationState.established ||
        _reconfigRequest != null) {
      return;
    }

    // Remove duplicates and take up to 32 streams per request
    const maxStreamsPerRequest = 32;
    final uniqueStreams = reconfigQueue.toSet().toList();
    final streams = uniqueStreams.take(maxStreamsPerRequest).toList();
    reconfigQueue = uniqueStreams.skip(maxStreamsPerRequest).toList();

    // Create the request
    final param = OutgoingSsnResetRequestParam(
      requestSequence: _reconfigRequestSeq,
      responseSequence: _reconfigResponseSeq,
      lastTsn: _tsnMinusOne(_localTsn),
      streams: streams,
    );

    // Increment sequence for next request
    _reconfigRequestSeq = _tsnPlusOne(_reconfigRequestSeq);

    // Save as pending request
    _reconfigRequest = param;

    // Send the chunk
    final chunk = SctpReconfigChunk(params: [param]);
    await _sendChunk(chunk);

    // Start reconfig retransmit timer
    _startReconfigTimer();
  }

  /// Start reconfig retransmission timer
  void _startReconfigTimer() {
    _reconfigTimer?.cancel();
    _reconfigTimer = Timer(Duration(milliseconds: _rto), () async {
      if (_reconfigRequest != null) {
        // Retransmit
        final chunk = SctpReconfigChunk(params: [_reconfigRequest!]);
        await _sendChunk(chunk);
        _startReconfigTimer();
      }
    });
  }

  /// Send INIT-ACK chunk
  Future<void> _sendInitAck() async {
    _stateCookie = _generateStateCookie();

    // Encode state cookie as TLV parameter
    final cookieParamLength = 4 + _stateCookie!.length;
    final paddedParamLength = (cookieParamLength + 3) & ~3;
    final parameters = Uint8List(paddedParamLength);
    final paramBuffer = ByteData.sublistView(parameters);
    paramBuffer.setUint16(0, 7); // State Cookie type
    paramBuffer.setUint16(2, cookieParamLength);
    parameters.setRange(4, 4 + _stateCookie!.length, _stateCookie!);

    final initAckChunk = SctpInitAckChunk(
      initiateTag: _localVerificationTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: _localInitialTsn,
      parameters: parameters,
    );

    await _sendChunk(initAckChunk);
  }

  /// Mark TSN as received, returns true if duplicate
  bool _markReceived(int tsn) {
    if (_lastReceivedTsn != null &&
        (uint32Gte(_lastReceivedTsn!, tsn) || _sackMisOrdered.contains(tsn))) {
      _sackDuplicates.add(tsn);
      return true;
    }

    _sackMisOrdered.add(tsn);

    // Advance cumulative TSN through contiguous sequence
    for (final t in _sackMisOrdered.toList()..sort()) {
      if (_lastReceivedTsn != null && t == _tsnPlusOne(_lastReceivedTsn!)) {
        _lastReceivedTsn = t;
        _remoteCumulativeTsn = t; // Keep in sync for SACK
      } else {
        break;
      }
    }

    // Prune obsolete entries
    if (_lastReceivedTsn != null) {
      _sackDuplicates =
          _sackDuplicates.where((x) => uint32Gt(x, _lastReceivedTsn!)).toList();
      _sackMisOrdered =
          _sackMisOrdered.where((x) => uint32Gt(x, _lastReceivedTsn!)).toSet();
    }

    return false;
  }

  /// Schedule SACK to be sent
  ///
  /// Uses immediate scheduling (like werift) rather than RFC 4960's delayed ACK
  /// recommendation of 200ms. Immediate ACKs provide much better latency for
  /// DataChannel use cases while maintaining correctness.
  void _scheduleSack() {
    if (_sackTimer != null) return; // Already scheduled
    // Use Timer with Duration.zero for immediate execution on next event loop
    // This matches werift's setImmediate behavior
    _sackTimer = Timer(Duration.zero, () {
      _sackTimer = null;
      _sendSack();
    });
  }

  /// Send SACK chunk
  Future<void> _sendSack() async {
    if (!_sackNeeded) return;
    _sackNeeded = false;

    // Build gap ack blocks from misordered set
    final gapBlocks = <GapAckBlock>[];
    if (_sackMisOrdered.isNotEmpty && _lastReceivedTsn != null) {
      final sorted = _sackMisOrdered.toList()..sort();
      int? start;
      int? end;
      for (final tsn in sorted) {
        final offset = (tsn - _lastReceivedTsn!) & 0xFFFFFFFF;
        if (start == null) {
          start = offset;
          end = offset;
        } else if (offset == end! + 1) {
          end = offset;
        } else {
          gapBlocks.add(GapAckBlock(start: start, end: end));
          start = offset;
          end = offset;
        }
      }
      if (start != null && end != null) {
        gapBlocks.add(GapAckBlock(start: start, end: end));
      }
    }

    final sackChunk = SctpSackChunk(
      cumulativeTsnAck: _remoteCumulativeTsn,
      advertisedRwnd: advertisedRwnd,
      gapAckBlocks: gapBlocks,
      duplicateTsns: _sackDuplicates,
    );

    await _sendChunk(sackChunk);
    _sackDuplicates = [];
  }

  // === Timer T1 (INIT/COOKIE-ECHO retransmission) ===

  void _t1Start(SctpChunk chunk, {int? verificationTag}) {
    if (_t1Timer != null) throw StateError('T1 timer already running');
    _t1Chunk = chunk;
    _t1VerificationTag = verificationTag;
    _t1Failures = 0;
    _t1Timer = Timer(Duration(milliseconds: _rto), _t1Expired);
  }

  void _t1Expired() {
    _t1Failures++;
    _t1Timer = null;

    if (_t1Failures > SctpConstants.maxInitRetransmits) {
      _setState(SctpAssociationState.closed);
      _dispose();
    } else {
      _sendChunk(_t1Chunk!, verificationTag: _t1VerificationTag);
      _t1Timer = Timer(Duration(milliseconds: _rto), _t1Expired);
    }
  }

  void _t1Cancel() {
    _t1Timer?.cancel();
    _t1Timer = null;
    _t1Chunk = null;
    _t1VerificationTag = null;
  }

  // === Timer T2 (SHUTDOWN retransmission) ===

  void _t2Start(SctpChunk chunk) {
    if (_t2Timer != null) throw StateError('T2 timer already running');
    _t2Chunk = chunk;
    _t2Failures = 0;
    _t2Timer = Timer(Duration(milliseconds: _rto), _t2Expired);
  }

  void _t2Expired() {
    _t2Failures++;
    _t2Timer = null;

    if (_t2Failures > SctpConstants.maxAssocRetransmits) {
      _setState(SctpAssociationState.closed);
      _dispose();
    } else {
      _sendChunk(_t2Chunk!);
      _t2Timer = Timer(Duration(milliseconds: _rto), _t2Expired);
    }
  }

  void _t2Cancel() {
    _t2Timer?.cancel();
    _t2Timer = null;
    _t2Chunk = null;
  }

  // === Timer T3 (DATA retransmission) ===

  void _t3Start() {
    if (_t3Timer != null) throw StateError('T3 timer already running');
    _t3Timer = Timer(Duration(milliseconds: _rto), _t3Expired);
  }

  void _t3Restart() {
    _t3Cancel();
    _t3Timer = Timer(Duration(milliseconds: _rto), _t3Expired);
  }

  void _t3Expired() {
    _t3Timer = null;

    // Mark all sent chunks for retransmission (or abandon if partial reliability)
    for (final chunk in _sentQueue) {
      if (!_maybeAbandon(chunk)) {
        chunk.retransmit = true;
      }
    }

    // Update advanced peer ack point for partial reliability
    _updateAdvancedPeerAckPoint();

    // Reset congestion control (RFC 4960 Section 7.2.3)
    _fastRecoveryExit = null;
    _flightSize = 0;
    _partialBytesAcked = 0;
    _ssthresh = max(_cwnd ~/ 2, 4 * SctpConstants.userDataMaxLength);
    _cwnd = SctpConstants.userDataMaxLength;

    _transmit();
  }

  void _t3Cancel() {
    _t3Timer?.cancel();
    _t3Timer = null;
  }

  // === Flight size tracking ===

  void _flightSizeIncrease(_SentChunk chunk) {
    _flightSize += chunk.bookSize;
  }

  void _flightSizeDecrease(_SentChunk chunk) {
    _flightSize = max(0, _flightSize - chunk.bookSize);
  }

  // === RTO calculation (RFC 4960 Section 6.3.1) ===

  void _updateRto(double r) {
    if (_srtt == null) {
      _rttvar = r / 2;
      _srtt = r;
    } else {
      _rttvar = (1 - SctpConstants.rtoBeta) * _rttvar! +
          SctpConstants.rtoBeta * (_srtt! - r).abs();
      _srtt =
          (1 - SctpConstants.rtoAlpha) * _srtt! + SctpConstants.rtoAlpha * r;
    }
    _rto = max(
      SctpConstants.rtoMin,
      min((_srtt! + 4 * _rttvar!).toInt() * 1000, SctpConstants.rtoMax),
    );
  }

  // === TSN arithmetic helpers ===

  int _getNextTsn() {
    final tsn = _localTsn;
    _localTsn = (_localTsn + 1) & 0xFFFFFFFF;
    return tsn;
  }

  int _tsnPlusOne(int tsn) => (tsn + 1) & 0xFFFFFFFF;
  int _tsnMinusOne(int tsn) => (tsn - 1) & 0xFFFFFFFF;

  // Note: uint32Gt and uint32Gte are in inbound_stream.dart
  // for InboundStream fragment reassembly

  /// Verify verification tag
  bool _verifyVerificationTag(SctpPacket packet) {
    if (packet.hasChunkType<SctpInitChunk>()) {
      return packet.verificationTag == 0;
    }
    if (packet.hasChunkType<SctpShutdownCompleteChunk>()) {
      return true;
    }
    return packet.verificationTag == _localVerificationTag;
  }

  /// Generate state cookie with HMAC-SHA1 (matching werift: packages/sctp/src/sctp.ts)
  /// Format: 4 bytes timestamp (seconds) + 20 bytes HMAC-SHA1
  Uint8List _generateStateCookie() {
    // Get current timestamp in seconds
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Create 4-byte timestamp buffer
    final timestampBytes = Uint8List(4);
    final bd = ByteData.sublistView(timestampBytes);
    bd.setUint32(0, timestamp);

    // Compute HMAC-SHA1 of timestamp
    final hmac = Hmac(sha1, _hmacKey);
    final digest = hmac.convert(timestampBytes);

    // Combine timestamp + HMAC digest
    final cookie = Uint8List(_cookieLength);
    cookie.setRange(0, 4, timestampBytes);
    cookie.setRange(4, _cookieLength, digest.bytes);

    return cookie;
  }

  /// Set state
  void _setState(SctpAssociationState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Dispose resources
  void _dispose() {
    _t1Cancel();
    _t2Cancel();
    _t3Cancel();
    _sackTimer?.cancel();
    _outboundQueue.clear();
    _sentQueue.clear();
    _receiveBuffer.clear();
    _outboundStreamSeq.clear();
    _sackMisOrdered.clear();
    _sackDuplicates.clear();
    _setState(SctpAssociationState.closed);
    _stateController.close();
  }

  // === Buffered Amount Tracking ===

  /// Get buffered amount for a stream (bytes queued but not yet ACKed)
  int getBufferedAmount(int streamId) {
    return _streamBufferedAmount[streamId] ?? 0;
  }

  /// Update buffered amount for a stream and fire callback
  void _updateBufferedAmount(int streamId, int delta) {
    final oldAmount = _streamBufferedAmount[streamId] ?? 0;
    final newAmount = (oldAmount + delta).clamp(0, 0x7FFFFFFFFFFFFFFF);
    _streamBufferedAmount[streamId] = newAmount;

    if (newAmount != oldAmount) {
      onBufferedAmountChange?.call(streamId, newAmount);
    }
  }

  /// Decrement buffered amount when chunk is ACKed
  void _decrementBufferedAmount(_SentChunk chunk) {
    _updateBufferedAmount(chunk.chunk.streamId, -chunk.chunk.userData.length);
  }

  /// Generate verification tag
  static int _generateVerificationTag(Random? random) {
    final rng = random ?? Random.secure();
    var tag = 0;
    while (tag == 0) {
      tag = rng.nextInt(0xFFFFFFFF);
    }
    return tag;
  }

  /// Generate initial TSN
  static int _generateInitialTsn(Random? random) {
    final rng = random ?? Random.secure();
    return rng.nextInt(0xFFFFFFFF);
  }

  @override
  String toString() {
    return 'SctpAssociation(state=$_state, localPort=$localPort, remotePort=$remotePort)';
  }
}
