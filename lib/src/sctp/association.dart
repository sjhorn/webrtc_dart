import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/sctp/packet.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';

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

  /// Number of outbound streams
  final int outboundStreams;

  /// Number of inbound streams
  final int inboundStreams;

  /// Advertised receive window
  final int advertisedRwnd;

  /// Send buffer
  final List<SctpDataChunk> _sendBuffer = [];

  /// Receive buffer (by TSN)
  final Map<int, SctpDataChunk> _receiveBuffer = {};

  /// Callback for sending packets
  final Future<void> Function(Uint8List packet) onSendPacket;

  /// Callback for receiving data
  final void Function(int streamId, Uint8List data, int ppid)? onReceiveData;

  /// Timer for retransmissions
  Timer? _t1Timer;

  /// Timer for SACK
  Timer? _sackTimer;

  /// Retransmission timeout (RTO)
  final int _rto = SctpConstants.rtoInitial;

  /// State cookie (for server)
  Uint8List? _stateCookie;

  /// Random number generator
  final Random _random;

  /// State change stream
  final _stateController = StreamController<SctpAssociationState>.broadcast();

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
        _localTsn = _generateInitialTsn(random);

  /// Get current state
  SctpAssociationState get state => _state;

  /// Stream of state changes
  Stream<SctpAssociationState> get onStateChange => _stateController.stream;

  /// Get local verification tag
  int get localVerificationTag => _localVerificationTag;

  /// Get remote verification tag
  int? get remoteVerificationTag => _remoteVerificationTag;

  /// Start association as client (send INIT)
  Future<void> connect() async {
    print('[SCTP] connect: state=$_state, localTag=0x${_localVerificationTag.toRadixString(16)}, localTsn=$_localInitialTsn');
    if (_state != SctpAssociationState.closed) {
      throw StateError('Association already started');
    }

    print('[SCTP] connect: sending INIT');
    await _sendInit();
    _setState(SctpAssociationState.cookieWait);
    _startT1Timer();
  }

  /// Handle incoming SCTP packet
  Future<void> handlePacket(Uint8List data) async {
    print('[SCTP] handlePacket: ${data.length} bytes, state=$_state');
    print('[SCTP]   first 16 bytes: ${data.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    final packet = SctpPacket.parse(data);
    print('[SCTP]   parsed: srcPort=${packet.sourcePort}, dstPort=${packet.destinationPort}, verTag=0x${packet.verificationTag.toRadixString(16)}, chunks=${packet.chunks.length}');

    // Verify verification tag (except for INIT and SHUTDOWN-COMPLETE)
    if (!_verifyVerificationTag(packet)) {
      // Silently discard
      print('[SCTP]   verification tag mismatch - discarding (expected 0x${_localVerificationTag.toRadixString(16)}, got 0x${packet.verificationTag.toRadixString(16)})');
      return;
    }

    // Process each chunk
    for (final chunk in packet.chunks) {
      print('[SCTP]   processing chunk type=${chunk.type}');
      await _handleChunk(chunk);
    }
  }

  /// Send data on a stream
  Future<void> sendData({
    required int streamId,
    required Uint8List data,
    required int ppid,
    bool unordered = false,
  }) async {
    if (_state != SctpAssociationState.established) {
      throw StateError('Association not established');
    }

    if (streamId >= outboundStreams) {
      throw ArgumentError('Invalid stream ID: $streamId');
    }

    final chunk = SctpDataChunk(
      tsn: _getNextTsn(),
      streamId: streamId,
      streamSeq: 0, // TODO: Track per-stream sequence numbers
      ppid: ppid,
      userData: data,
      flags: unordered
          ? SctpDataChunkFlags.beginningFragment |
              SctpDataChunkFlags.endFragment |
              SctpDataChunkFlags.unordered
          : SctpDataChunkFlags.beginningFragment |
              SctpDataChunkFlags.endFragment,
    );

    _sendBuffer.add(chunk);
    await _flushSendBuffer();
  }

  /// Close association gracefully
  Future<void> close() async {
    if (_state == SctpAssociationState.closed) {
      return;
    }

    if (_state == SctpAssociationState.established) {
      _setState(SctpAssociationState.shutdownPending);
      await _sendShutdown();
    }
  }

  /// Abort association
  Future<void> abort({Uint8List? cause}) async {
    await _sendAbort(cause: cause);
    _dispose();
  }

  /// Send INIT chunk
  Future<void> _sendInit() async {
    final initChunk = SctpInitChunk(
      initiateTag: _localVerificationTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: _localInitialTsn,
    );

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: 0, // Always 0 for INIT
      chunks: [initChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send INIT-ACK chunk
  Future<void> _sendInitAck() async {
    // Generate state cookie
    _stateCookie = _generateStateCookie();

    // Encode state cookie as TLV parameter
    // Type: 7 (State Cookie), Length: 4 + cookie_length
    final cookieParamLength = 4 + _stateCookie!.length;
    // Pad to 4-byte boundary
    final paddedParamLength = (cookieParamLength + 3) & ~3;
    final parameters = Uint8List(paddedParamLength);
    final paramBuffer = ByteData.sublistView(parameters);
    paramBuffer.setUint16(0, 7); // State Cookie type
    paramBuffer.setUint16(2, cookieParamLength); // Length including header
    parameters.setRange(4, 4 + _stateCookie!.length, _stateCookie!);

    print('[SCTP] _sendInitAck: cookie=${_stateCookie!.length} bytes, param=${parameters.length} bytes');

    final initAckChunk = SctpInitAckChunk(
      initiateTag: _localVerificationTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: _localInitialTsn,
      parameters: parameters,
    );

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [initAckChunk],
    );

    print('[SCTP] _sendInitAck: sending packet with verTag=0x${_remoteVerificationTag!.toRadixString(16)}');
    await onSendPacket(packet.serialize());
  }

  /// Send COOKIE-ECHO chunk
  Future<void> _sendCookieEcho(Uint8List cookie) async {
    final cookieEchoChunk = SctpCookieEchoChunk(cookie: cookie);

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [cookieEchoChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send COOKIE-ACK chunk
  Future<void> _sendCookieAck() async {
    final cookieAckChunk = SctpCookieAckChunk();

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [cookieAckChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send SHUTDOWN chunk
  Future<void> _sendShutdown() async {
    final shutdownChunk =
        SctpShutdownChunk(cumulativeTsnAck: _remoteCumulativeTsn);

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [shutdownChunk],
    );

    await onSendPacket(packet.serialize());
    _setState(SctpAssociationState.shutdownSent);
  }

  /// Send SHUTDOWN-ACK chunk
  Future<void> _sendShutdownAck() async {
    final shutdownAckChunk = SctpShutdownAckChunk();

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [shutdownAckChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send SHUTDOWN-COMPLETE chunk
  Future<void> _sendShutdownComplete() async {
    final shutdownCompleteChunk = SctpShutdownCompleteChunk();

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [shutdownCompleteChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send ABORT chunk
  Future<void> _sendAbort({Uint8List? cause}) async {
    final abortChunk = SctpAbortChunk(causes: cause);

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag ?? 0,
      chunks: [abortChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Send SACK chunk
  Future<void> _sendSack() async {
    final sackChunk = SctpSackChunk(
      cumulativeTsnAck: _remoteCumulativeTsn,
      advertisedRwnd: advertisedRwnd,
    );

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: [sackChunk],
    );

    await onSendPacket(packet.serialize());
  }

  /// Flush send buffer
  Future<void> _flushSendBuffer() async {
    if (_sendBuffer.isEmpty) return;

    final chunks = _sendBuffer.toList();
    _sendBuffer.clear();

    final packet = SctpPacket(
      sourcePort: localPort,
      destinationPort: remotePort,
      verificationTag: _remoteVerificationTag!,
      chunks: chunks,
    );

    await onSendPacket(packet.serialize());
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
      default:
        // Ignore unknown chunks
        break;
    }
  }

  /// Handle INIT chunk
  Future<void> _handleInit(SctpInitChunk chunk) async {
    print('[SCTP] _handleInit: state=$_state, remoteTag=0x${chunk.initiateTag.toRadixString(16)}, remoteTsn=${chunk.initialTsn}');

    if (_state != SctpAssociationState.closed) {
      // TODO: Handle collision scenarios
      print('[SCTP] _handleInit: ignoring INIT in state $_state');
      return;
    }

    _remoteVerificationTag = chunk.initiateTag;
    _remoteCumulativeTsn = chunk.initialTsn - 1;

    print('[SCTP] _handleInit: sending INIT-ACK with localTag=0x${_localVerificationTag.toRadixString(16)}');
    await _sendInitAck();
    // Note: Server stays in closed state waiting for COOKIE-ECHO, not cookieWait
    // cookieWait is only for client waiting for INIT-ACK
  }

  /// Handle INIT-ACK chunk
  Future<void> _handleInitAck(SctpInitAckChunk chunk) async {
    print('[SCTP] _handleInitAck: state=$_state, remoteTag=0x${chunk.initiateTag.toRadixString(16)}');

    if (_state != SctpAssociationState.cookieWait) {
      print('[SCTP] _handleInitAck: ignoring INIT-ACK in state $_state');
      return;
    }

    _stopT1Timer();

    _remoteVerificationTag = chunk.initiateTag;
    _remoteCumulativeTsn = chunk.initialTsn - 1;

    // Extract state cookie from parameters
    final stateCookie = chunk.getStateCookie();
    print('[SCTP] _handleInitAck: stateCookie=${stateCookie != null ? '${stateCookie.length} bytes' : 'null'}');
    if (stateCookie != null) {
      print('[SCTP] _handleInitAck: sending COOKIE-ECHO');
      await _sendCookieEcho(stateCookie);
      _setState(SctpAssociationState.cookieEchoed);
      _startT1Timer();
    }
  }

  /// Handle COOKIE-ECHO chunk
  Future<void> _handleCookieEcho(SctpCookieEchoChunk chunk) async {
    print('[SCTP] _handleCookieEcho: state=$_state, cookie=${chunk.cookie.length} bytes');
    // TODO: Verify state cookie

    print('[SCTP] _handleCookieEcho: sending COOKIE-ACK, establishing association');
    await _sendCookieAck();
    _setState(SctpAssociationState.established);
  }

  /// Handle COOKIE-ACK chunk
  Future<void> _handleCookieAck() async {
    print('[SCTP] _handleCookieAck: state=$_state');
    if (_state != SctpAssociationState.cookieEchoed) {
      print('[SCTP] _handleCookieAck: ignoring in state $_state');
      return;
    }

    _stopT1Timer();
    print('[SCTP] _handleCookieAck: association established!');
    _setState(SctpAssociationState.established);
  }

  /// Handle DATA chunk
  Future<void> _handleData(SctpDataChunk chunk) async {
    if (_state != SctpAssociationState.established) {
      return;
    }

    // Store in receive buffer
    _receiveBuffer[chunk.tsn] = chunk;

    // Update cumulative TSN
    _updateCumulativeTsn();

    // Schedule SACK
    _scheduleSack();

    // Deliver data if complete
    if (chunk.beginningFragment && chunk.endFragment) {
      if (onReceiveData != null) {
        onReceiveData!(chunk.streamId, chunk.userData, chunk.ppid);
      }
    }
  }

  /// Handle SACK chunk
  Future<void> _handleSack(SctpSackChunk chunk) async {
    // Update based on cumulative TSN ACK
    // TODO: Handle gap ack blocks and retransmissions
  }

  /// Handle SHUTDOWN chunk
  Future<void> _handleShutdown(SctpShutdownChunk chunk) async {
    if (_state == SctpAssociationState.established) {
      _setState(SctpAssociationState.shutdownReceived);
      await _sendShutdownAck();
      _setState(SctpAssociationState.shutdownAckSent);
    }
  }

  /// Handle SHUTDOWN-ACK chunk
  Future<void> _handleShutdownAck() async {
    if (_state == SctpAssociationState.shutdownSent) {
      await _sendShutdownComplete();
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

  /// Update cumulative TSN from receive buffer
  void _updateCumulativeTsn() {
    var expectedTsn = _remoteCumulativeTsn + 1;

    while (_receiveBuffer.containsKey(expectedTsn)) {
      _remoteCumulativeTsn = expectedTsn;
      _receiveBuffer.remove(expectedTsn);
      expectedTsn++;
    }
  }

  /// Schedule SACK to be sent
  void _scheduleSack() {
    _sackTimer?.cancel();
    _sackTimer = Timer(
      Duration(milliseconds: SctpConstants.sackTimeout),
      () => _sendSack(),
    );
  }

  /// Start T1 timer (for INIT/COOKIE-ECHO retransmission)
  void _startT1Timer() {
    _t1Timer?.cancel();
    _t1Timer = Timer(Duration(milliseconds: _rto), () {
      // TODO: Implement retransmission logic
    });
  }

  /// Stop T1 timer
  void _stopT1Timer() {
    _t1Timer?.cancel();
    _t1Timer = null;
  }

  /// Get next TSN
  int _getNextTsn() {
    final tsn = _localTsn;
    _localTsn = (_localTsn + 1) & 0xFFFFFFFF;
    return tsn;
  }

  /// Verify verification tag
  bool _verifyVerificationTag(SctpPacket packet) {
    // INIT always uses verification tag 0
    if (packet.hasChunkType<SctpInitChunk>()) {
      return packet.verificationTag == 0;
    }

    // SHUTDOWN-COMPLETE may use peer's tag
    if (packet.hasChunkType<SctpShutdownCompleteChunk>()) {
      return true; // Accept either tag
    }

    // All other packets must use our verification tag
    return packet.verificationTag == _localVerificationTag;
  }

  /// Generate state cookie
  Uint8List _generateStateCookie() {
    // Simple implementation: just return random bytes
    // In production, should include HMAC and timestamp
    final cookie = Uint8List(32);
    for (var i = 0; i < cookie.length; i++) {
      cookie[i] = _random.nextInt(256);
    }
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
    _stopT1Timer();
    _sackTimer?.cancel();
    _sendBuffer.clear();
    _receiveBuffer.clear();
    _setState(SctpAssociationState.closed);
    _stateController.close();
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
