import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/datachannel/dcep.dart';

final _log = WebRtcLogging.datachannel;

/// Data Channel State
enum DataChannelState {
  connecting,
  open,
  closing,
  closed,
}

/// Data Channel
/// WebRTC Data Channel API
/// RFC 8831 - WebRTC Data Channels
class RTCDataChannel {
  /// Label
  final String label;

  /// Protocol
  final String protocol;

  /// Stream ID
  final int streamId;

  /// Channel type
  final DataChannelType channelType;

  /// Priority
  final int priority;

  /// Whether the channel was negotiated out-of-band
  ///
  /// When true, the data channel was set up via application-level
  /// negotiation (both peers create matching channels with the same ID).
  /// When false (default), the channel uses in-band DCEP signaling.
  final bool negotiated;

  /// Reliability parameter (maxRetransmits or maxPacketLifeTime)
  final int reliabilityParameter;

  /// Max retransmits (for partialReliableRexmit channel types)
  int? get maxRetransmits {
    if (channelType == DataChannelType.partialReliableRexmit ||
        channelType == DataChannelType.partialReliableRexmitUnordered) {
      return reliabilityParameter;
    }
    return null;
  }

  /// Max packet lifetime in milliseconds (for partialReliableTimed channel types)
  int? get maxPacketLifeTime {
    if (channelType == DataChannelType.partialReliableTimed ||
        channelType == DataChannelType.partialReliableTimedUnordered) {
      return reliabilityParameter;
    }
    return null;
  }

  /// SCTP association
  final SctpAssociation _association;

  /// Current state
  DataChannelState _state = DataChannelState.connecting;

  /// Message stream controller
  final StreamController<dynamic> _messageController =
      StreamController.broadcast();

  /// Error stream controller
  final StreamController<dynamic> _errorController =
      StreamController.broadcast();

  /// State change stream controller
  final StreamController<DataChannelState> _stateController =
      StreamController.broadcast();

  /// Buffered amount low stream controller
  /// Reference: werift-webrtc bufferedAmountLow Event
  final StreamController<void> _bufferedAmountLowController =
      StreamController.broadcast();

  /// Threshold for bufferedAmountLow event
  /// Reference: werift-webrtc bufferedAmountLowThreshold property
  int _bufferedAmountLowThreshold = 0;

  /// Previous buffered amount (for detecting threshold crossing)
  int _previousBufferedAmount = 0;

  /// Get current buffered amount from SCTP association
  /// This reflects bytes queued but not yet ACKed
  int get bufferedAmount => _association.getBufferedAmount(streamId);

  /// Get buffered amount low threshold
  int get bufferedAmountLowThreshold => _bufferedAmountLowThreshold;

  /// Set buffered amount low threshold
  set bufferedAmountLowThreshold(int value) {
    if (value < 0 || value > 4294967295) {
      throw ArgumentError(
          'bufferedAmountLowThreshold must be in range 0 - 4294967295');
    }
    _bufferedAmountLowThreshold = value;
  }

  /// Stream of buffered amount low events
  Stream<void> get onBufferedAmountLow => _bufferedAmountLowController.stream;

  /// Handle buffered amount change from SCTP association
  /// Fires onBufferedAmountLow when crossing threshold from above
  void handleBufferedAmountChange(int newAmount) {
    final crossesThreshold = _previousBufferedAmount > _bufferedAmountLowThreshold &&
        newAmount <= _bufferedAmountLowThreshold;
    _previousBufferedAmount = newAmount;
    if (crossesThreshold) {
      _bufferedAmountLowController.add(null);
    }
  }

  /// Ordered delivery
  bool get ordered => channelType.isOrdered;

  /// Reliable delivery
  bool get reliable => channelType.isReliable;

  RTCDataChannel({
    required this.label,
    required this.protocol,
    required this.streamId,
    required this.channelType,
    required this.priority,
    required this.reliabilityParameter,
    required SctpAssociation association,
    this.negotiated = false,
  }) : _association = association;

  /// Get current state
  DataChannelState get state => _state;

  // ===========================================================================
  // W3C Standard Property Aliases
  // ===========================================================================

  /// Channel ID (W3C standard name for 'streamId')
  int get id => streamId;

  /// Ready state (W3C standard name for 'state')
  DataChannelState get readyState => _state;

  // ===========================================================================
  // W3C-style listener subscriptions (for setter-based callbacks)
  // ===========================================================================
  StreamSubscription? _onopenSubscription;
  StreamSubscription? _oncloseSubscription;
  StreamSubscription? _onclosingSubscription;
  StreamSubscription? _onmessageSubscription;
  StreamSubscription? _onerrorSubscription;
  StreamSubscription? _onbufferedamountlowSubscription;

  /// Stream of received messages
  Stream<dynamic> get onMessage => _messageController.stream;

  /// Stream of errors
  Stream<dynamic> get onError => _errorController.stream;

  /// Stream of state changes
  Stream<DataChannelState> get onStateChange => _stateController.stream;

  // ===========================================================================
  // W3C-style Listener Setters (for JavaScript-like callback syntax)
  // ===========================================================================
  // These provide an alternative to Dart Streams for developers familiar
  // with the JavaScript WebRTC API: dc.onmessage = (e) => {...};

  /// Set open callback (W3C-style)
  /// Fires when readyState changes to 'open'
  set onopen(void Function()? callback) {
    _onopenSubscription?.cancel();
    _onopenSubscription = callback != null
        ? onStateChange
            .where((s) => s == DataChannelState.open)
            .listen((_) => callback())
        : null;
  }

  /// Set close callback (W3C-style)
  /// Fires when readyState changes to 'closed'
  set onclose(void Function()? callback) {
    _oncloseSubscription?.cancel();
    _oncloseSubscription = callback != null
        ? onStateChange
            .where((s) => s == DataChannelState.closed)
            .listen((_) => callback())
        : null;
  }

  /// Set closing callback (W3C-style)
  /// Fires when readyState changes to 'closing'
  set onclosing(void Function()? callback) {
    _onclosingSubscription?.cancel();
    _onclosingSubscription = callback != null
        ? onStateChange
            .where((s) => s == DataChannelState.closing)
            .listen((_) => callback())
        : null;
  }

  /// Set message callback (W3C-style)
  set onmessage(void Function(dynamic)? callback) {
    _onmessageSubscription?.cancel();
    _onmessageSubscription =
        callback != null ? onMessage.listen(callback) : null;
  }

  /// Set error callback (W3C-style)
  set onerror(void Function(dynamic)? callback) {
    _onerrorSubscription?.cancel();
    _onerrorSubscription = callback != null ? onError.listen(callback) : null;
  }

  /// Set buffered amount low callback (W3C-style)
  set onbufferedamountlow(void Function()? callback) {
    _onbufferedamountlowSubscription?.cancel();
    _onbufferedamountlowSubscription = callback != null
        ? onBufferedAmountLow.listen((_) => callback())
        : null;
  }

  /// Open the data channel (send DCEP OPEN)
  Future<void> open() async {
    _log.fine(
        'RTCDataChannel.open() called: label=$label, streamId=$streamId, state=$_state');
    if (_state != DataChannelState.connecting) {
      throw StateError('RTCDataChannel already opened or closed');
    }

    final openMessage = DcepOpenMessage(
      channelType: channelType,
      priority: priority,
      reliabilityParameter: reliabilityParameter,
      label: label,
      protocol: protocol,
    );

    _log.fine('Sending DCEP OPEN: streamId=$streamId, label=$label');
    await _association.sendData(
      streamId: streamId,
      data: openMessage.serialize(),
      ppid: SctpPpid.dcep.value,
      unordered: false,
    );
    _log.fine('DCEP OPEN sent: streamId=$streamId');
  }

  /// Handle DCEP ACK
  void _handleDcepAck() {
    if (_state == DataChannelState.connecting) {
      _setState(DataChannelState.open);
    }
  }

  /// Handle incoming DCEP OPEN
  Future<void> _handleDcepOpen(DcepOpenMessage message) async {
    // Send ACK
    final ackMessage = const DcepAckMessage();
    await _association.sendData(
      streamId: streamId,
      data: ackMessage.serialize(),
      ppid: SctpPpid.dcep.value,
      unordered: false,
    );

    _setState(DataChannelState.open);
  }

  /// Handle incoming data
  Future<void> handleIncomingData(Uint8List data, int ppid) async {
    // Check if DCEP message
    if (ppid == SctpPpid.dcep.value) {
      final message = parseDcepMessage(data);
      if (message is DcepOpenMessage) {
        await _handleDcepOpen(message);
      } else if (message is DcepAckMessage) {
        _handleDcepAck();
      }
      return;
    }

    // Check state
    if (_state != DataChannelState.open) {
      return;
    }

    // Deliver message based on PPID
    switch (SctpPpid.fromValue(ppid)) {
      case SctpPpid.webrtcString:
      case SctpPpid.webrtcStringEmpty:
        // String message
        final message = String.fromCharCodes(data);
        _messageController.add(message);
        break;
      case SctpPpid.webrtcBinary:
      case SctpPpid.webrtcBinaryEmpty:
        // Binary message
        _messageController.add(data);
        break;
      default:
        // Unknown PPID, deliver as binary
        _messageController.add(data);
        break;
    }
  }

  /// Calculate expiry time for timed partial reliability
  double? _calculateExpiry() {
    final lifetime = maxPacketLifeTime;
    if (lifetime == null) return null;
    // Convert milliseconds to seconds and add to current time
    return DateTime.now().millisecondsSinceEpoch / 1000.0 + lifetime / 1000.0;
  }

  /// Send string message
  Future<void> sendString(String message) async {
    if (_state != DataChannelState.open) {
      throw StateError('RTCDataChannel not open');
    }

    final data = Uint8List.fromList(message.codeUnits);
    final ppid = data.isEmpty
        ? SctpPpid.webrtcStringEmpty.value
        : SctpPpid.webrtcString.value;

    // bufferedAmount is tracked at SCTP level via onBufferedAmountChange callback
    await _association.sendData(
      streamId: streamId,
      data: data,
      ppid: ppid,
      unordered: !ordered,
      expiry: _calculateExpiry(),
      maxRetransmits: maxRetransmits,
    );
  }

  /// Send binary message
  Future<void> sendBinary(Uint8List message) async {
    if (_state != DataChannelState.open) {
      throw StateError('RTCDataChannel not open');
    }

    final ppid = message.isEmpty
        ? SctpPpid.webrtcBinaryEmpty.value
        : SctpPpid.webrtcBinary.value;

    // bufferedAmount is tracked at SCTP level via onBufferedAmountChange callback
    await _association.sendData(
      streamId: streamId,
      data: message,
      ppid: ppid,
      unordered: !ordered,
      expiry: _calculateExpiry(),
      maxRetransmits: maxRetransmits,
    );
  }

  /// Send message (auto-detect type)
  Future<void> send(dynamic message) async {
    if (message is String) {
      await sendString(message);
    } else if (message is Uint8List) {
      await sendBinary(message);
    } else if (message is List<int>) {
      await sendBinary(Uint8List.fromList(message));
    } else {
      throw ArgumentError('Message must be String or Uint8List');
    }
  }

  /// Close the data channel
  /// Uses SCTP Stream Reconfiguration (RFC 6525) for graceful close
  Future<void> close() async {
    if (_state == DataChannelState.closed ||
        _state == DataChannelState.closing) {
      return;
    }

    _setState(DataChannelState.closing);

    // Check if SCTP association is established
    if (_association.state == SctpAssociationState.established) {
      // Add to reconfig queue if not already there
      if (!_association.reconfigQueue.contains(streamId)) {
        _association.reconfigQueue.add(streamId);
      }
      // Trigger reconfig request if this is the first item in queue
      if (_association.reconfigQueue.length == 1) {
        await _association.transmitReconfigRequest();
      }
      // The actual close will happen when we receive the reconfig response
      // via onReconfigStreams callback
    } else {
      // Association not established, close immediately
      _setState(DataChannelState.closed);
      await _dispose();
    }
  }

  /// Called when the stream is reconfigured (closed by peer or response received)
  void handleStreamReset() {
    _setState(DataChannelState.closed);
    _dispose();
  }

  /// Set state
  void _setState(DataChannelState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// Dispose resources
  Future<void> _dispose() async {
    // Cancel W3C-style listener subscriptions
    _onopenSubscription?.cancel();
    _oncloseSubscription?.cancel();
    _onclosingSubscription?.cancel();
    _onmessageSubscription?.cancel();
    _onerrorSubscription?.cancel();
    _onbufferedamountlowSubscription?.cancel();

    await _messageController.close();
    await _errorController.close();
    await _stateController.close();
    await _bufferedAmountLowController.close();
  }

  @override
  String toString() {
    return 'RTCDataChannel(label="$label", id=$streamId, state=$_state)';
  }
}

/// Configuration for a pending data channel
/// Used to store data channel parameters before SCTP is ready
class PendingDataChannelConfig {
  final String label;
  final String protocol;
  final bool ordered;
  final int? maxRetransmits;
  final int? maxPacketLifeTime;
  final int priority;

  /// The proxy data channel that will be wired up when initialized
  final ProxyRTCDataChannel proxy;

  PendingDataChannelConfig({
    required this.label,
    required this.proxy,
    this.protocol = '',
    this.ordered = true,
    this.maxRetransmits,
    this.maxPacketLifeTime,
    this.priority = 0,
  });
}

/// A proxy data channel that forwards to a real channel once SCTP is ready.
/// This allows createRTCDataChannel() to return immediately while the real
/// channel is created asynchronously when the connection is established.
class ProxyRTCDataChannel {
  /// Channel configuration
  final String _label;
  final String _protocol;
  final bool _ordered;
  final int? _maxRetransmits;
  final int? _maxPacketLifeTime;
  final int _priority;

  /// The real data channel (set when SCTP is ready)
  RTCDataChannel? _realChannel;

  /// Current state (before real channel is created)
  DataChannelState _state = DataChannelState.connecting;

  /// Queued messages to send when channel opens
  final List<dynamic> _pendingMessages = [];

  /// Stream controllers for events before real channel exists
  final StreamController<dynamic> _messageController =
      StreamController.broadcast();
  final StreamController<dynamic> _errorController =
      StreamController.broadcast();
  final StreamController<DataChannelState> _stateController =
      StreamController.broadcast();
  final StreamController<void> _bufferedAmountLowController =
      StreamController.broadcast();

  // W3C-style listener subscriptions
  StreamSubscription? _onopenSubscription;
  StreamSubscription? _oncloseSubscription;
  StreamSubscription? _onclosingSubscription;
  StreamSubscription? _onmessageSubscription;
  StreamSubscription? _onerrorSubscription;
  StreamSubscription? _onbufferedamountlowSubscription;

  /// Completer for when channel is ready
  final Completer<RTCDataChannel> _readyCompleter = Completer<RTCDataChannel>();

  /// Buffered amount tracking (before real channel exists)
  /// Note: _bufferedAmount is always 0 for proxy since sends are queued
  final int _bufferedAmount = 0;
  int _bufferedAmountLowThreshold = 0;

  ProxyRTCDataChannel({
    required String label,
    String protocol = '',
    bool ordered = true,
    int? maxRetransmits,
    int? maxPacketLifeTime,
    int priority = 0,
  })  : _label = label,
        _protocol = protocol,
        _ordered = ordered,
        _maxRetransmits = maxRetransmits,
        _maxPacketLifeTime = maxPacketLifeTime,
        _priority = priority;

  // RTCDataChannel-like interface

  String get label => _realChannel?.label ?? _label;
  String get protocol => _realChannel?.protocol ?? _protocol;
  int get streamId => _realChannel?.streamId ?? -1;
  int get priority => _realChannel?.priority ?? _priority;
  bool get ordered => _realChannel?.ordered ?? _ordered;
  DataChannelState get state => _realChannel?.state ?? _state;

  // W3C Standard Property Aliases
  int get id => streamId;
  DataChannelState get readyState => state;

  DataChannelType get channelType {
    if (_realChannel != null) return _realChannel!.channelType;
    if (_maxRetransmits != null) {
      return _ordered
          ? DataChannelType.partialReliableRexmit
          : DataChannelType.partialReliableRexmitUnordered;
    } else if (_maxPacketLifeTime != null) {
      return _ordered
          ? DataChannelType.partialReliableTimed
          : DataChannelType.partialReliableTimedUnordered;
    }
    return _ordered
        ? DataChannelType.reliable
        : DataChannelType.reliableUnordered;
  }

  bool get reliable => _realChannel?.reliable ?? channelType.isReliable;

  /// Get current buffered amount
  int get bufferedAmount => _realChannel?.bufferedAmount ?? _bufferedAmount;

  /// Get buffered amount low threshold
  int get bufferedAmountLowThreshold =>
      _realChannel?.bufferedAmountLowThreshold ?? _bufferedAmountLowThreshold;

  /// Set buffered amount low threshold
  set bufferedAmountLowThreshold(int value) {
    if (value < 0 || value > 4294967295) {
      throw ArgumentError(
          'bufferedAmountLowThreshold must be in range 0 - 4294967295');
    }
    if (_realChannel != null) {
      _realChannel!.bufferedAmountLowThreshold = value;
    } else {
      _bufferedAmountLowThreshold = value;
    }
  }

  Stream<dynamic> get onMessage =>
      _realChannel?.onMessage ?? _messageController.stream;

  Stream<dynamic> get onError =>
      _realChannel?.onError ?? _errorController.stream;

  Stream<DataChannelState> get onStateChange =>
      _realChannel?.onStateChange ?? _stateController.stream;

  Stream<void> get onBufferedAmountLow =>
      _realChannel?.onBufferedAmountLow ?? _bufferedAmountLowController.stream;

  // ===========================================================================
  // W3C-style Listener Setters (for JavaScript-like callback syntax)
  // ===========================================================================

  /// Set open callback (W3C-style)
  set onopen(void Function()? callback) {
    _onopenSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onopen = callback;
    } else {
      _onopenSubscription = callback != null
          ? onStateChange
              .where((s) => s == DataChannelState.open)
              .listen((_) => callback())
          : null;
    }
  }

  /// Set close callback (W3C-style)
  set onclose(void Function()? callback) {
    _oncloseSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onclose = callback;
    } else {
      _oncloseSubscription = callback != null
          ? onStateChange
              .where((s) => s == DataChannelState.closed)
              .listen((_) => callback())
          : null;
    }
  }

  /// Set closing callback (W3C-style)
  set onclosing(void Function()? callback) {
    _onclosingSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onclosing = callback;
    } else {
      _onclosingSubscription = callback != null
          ? onStateChange
              .where((s) => s == DataChannelState.closing)
              .listen((_) => callback())
          : null;
    }
  }

  /// Set message callback (W3C-style)
  set onmessage(void Function(dynamic)? callback) {
    _onmessageSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onmessage = callback;
    } else {
      _onmessageSubscription =
          callback != null ? onMessage.listen(callback) : null;
    }
  }

  /// Set error callback (W3C-style)
  set onerror(void Function(dynamic)? callback) {
    _onerrorSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onerror = callback;
    } else {
      _onerrorSubscription = callback != null ? onError.listen(callback) : null;
    }
  }

  /// Set buffered amount low callback (W3C-style)
  set onbufferedamountlow(void Function()? callback) {
    _onbufferedamountlowSubscription?.cancel();
    if (_realChannel != null) {
      _realChannel!.onbufferedamountlow = callback;
    } else {
      _onbufferedamountlowSubscription = callback != null
          ? onBufferedAmountLow.listen((_) => callback())
          : null;
    }
  }

  /// Future that completes when channel is ready
  Future<RTCDataChannel> get ready => _readyCompleter.future;

  /// Whether the channel has been initialized
  bool get isInitialized => _realChannel != null;

  /// Track if we've been closed
  bool _isClosed = false;

  /// Initialize with a real RTCDataChannel (called when SCTP is ready)
  void initializeWithChannel(RTCDataChannel channel) {
    if (_realChannel != null) return;

    _realChannel = channel;

    // Transfer bufferedAmountLowThreshold to real channel
    if (_bufferedAmountLowThreshold > 0) {
      channel.bufferedAmountLowThreshold = _bufferedAmountLowThreshold;
    }

    // Forward events from real channel to our controllers
    channel.onMessage.listen((msg) {
      if (!_isClosed && !_messageController.isClosed) {
        _messageController.add(msg);
      }
    });
    channel.onError.listen((err) {
      if (!_isClosed && !_errorController.isClosed) {
        _errorController.add(err);
      }
    });
    channel.onStateChange.listen((newState) {
      _state = newState;
      if (!_isClosed && !_stateController.isClosed) {
        _stateController.add(newState);
      }

      // Send queued messages when channel opens
      if (newState == DataChannelState.open && _pendingMessages.isNotEmpty) {
        _flushPendingMessages();
      }
    });
    channel.onBufferedAmountLow.listen((_) {
      if (!_isClosed && !_bufferedAmountLowController.isClosed) {
        _bufferedAmountLowController.add(null);
      }
    });

    // Update state
    _state = channel.state;
    _stateController.add(_state);

    // If already open, flush pending messages
    if (_state == DataChannelState.open && _pendingMessages.isNotEmpty) {
      _flushPendingMessages();
    }

    // Complete the ready future
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete(channel);
    }
  }

  void _flushPendingMessages() {
    if (_realChannel == null) return;
    for (final msg in _pendingMessages) {
      try {
        _realChannel!.send(msg);
      } catch (e) {
        // Ignore send errors for queued messages
      }
    }
    _pendingMessages.clear();
  }

  Future<void> send(dynamic message) async {
    if (_realChannel != null && _realChannel!.state == DataChannelState.open) {
      await _realChannel!.send(message);
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> sendString(String message) async {
    if (_realChannel != null && _realChannel!.state == DataChannelState.open) {
      await _realChannel!.sendString(message);
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> sendBinary(Uint8List message) async {
    if (_realChannel != null && _realChannel!.state == DataChannelState.open) {
      await _realChannel!.sendBinary(message);
    } else {
      _pendingMessages.add(message);
    }
  }

  Future<void> close() async {
    _isClosed = true;
    if (_realChannel != null) {
      await _realChannel!.close();
    } else {
      _state = DataChannelState.closed;
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }
    }

    // Cancel W3C-style listener subscriptions
    _onopenSubscription?.cancel();
    _oncloseSubscription?.cancel();
    _onclosingSubscription?.cancel();
    _onmessageSubscription?.cancel();
    _onerrorSubscription?.cancel();
    _onbufferedamountlowSubscription?.cancel();

    await _messageController.close();
    await _errorController.close();
    await _stateController.close();
    await _bufferedAmountLowController.close();
  }

  @override
  String toString() {
    return 'ProxyRTCDataChannel(label="$_label", initialized=${_realChannel != null}, state=$_state)';
  }
}

// =============================================================================
// Backward Compatibility TypeDef
// =============================================================================

/// @deprecated Use RTCDataChannel instead
@Deprecated('Use RTCDataChannel instead')
typedef DataChannel = RTCDataChannel;
