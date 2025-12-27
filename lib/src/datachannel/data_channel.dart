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
class DataChannel {
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

  /// Ordered delivery
  bool get ordered => channelType.isOrdered;

  /// Reliable delivery
  bool get reliable => channelType.isReliable;

  DataChannel({
    required this.label,
    required this.protocol,
    required this.streamId,
    required this.channelType,
    required this.priority,
    required this.reliabilityParameter,
    required SctpAssociation association,
  }) : _association = association;

  /// Get current state
  DataChannelState get state => _state;

  /// Stream of received messages
  Stream<dynamic> get onMessage => _messageController.stream;

  /// Stream of errors
  Stream<dynamic> get onError => _errorController.stream;

  /// Stream of state changes
  Stream<DataChannelState> get onStateChange => _stateController.stream;

  /// Open the data channel (send DCEP OPEN)
  Future<void> open() async {
    _log.fine('DataChannel.open() called: label=$label, streamId=$streamId, state=$_state');
    if (_state != DataChannelState.connecting) {
      throw StateError('DataChannel already opened or closed');
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
      throw StateError('DataChannel not open');
    }

    final data = Uint8List.fromList(message.codeUnits);
    final ppid = data.isEmpty
        ? SctpPpid.webrtcStringEmpty.value
        : SctpPpid.webrtcString.value;

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
      throw StateError('DataChannel not open');
    }

    final ppid = message.isEmpty
        ? SctpPpid.webrtcBinaryEmpty.value
        : SctpPpid.webrtcBinary.value;

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
    await _messageController.close();
    await _errorController.close();
    await _stateController.close();
  }

  @override
  String toString() {
    return 'DataChannel(label="$label", id=$streamId, state=$_state)';
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
  final ProxyDataChannel proxy;

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
/// This allows createDataChannel() to return immediately while the real
/// channel is created asynchronously when the connection is established.
class ProxyDataChannel {
  /// Channel configuration
  final String _label;
  final String _protocol;
  final bool _ordered;
  final int? _maxRetransmits;
  final int? _maxPacketLifeTime;
  final int _priority;

  /// The real data channel (set when SCTP is ready)
  DataChannel? _realChannel;

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

  /// Completer for when channel is ready
  final Completer<DataChannel> _readyCompleter = Completer<DataChannel>();

  ProxyDataChannel({
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

  // DataChannel-like interface

  String get label => _realChannel?.label ?? _label;
  String get protocol => _realChannel?.protocol ?? _protocol;
  int get streamId => _realChannel?.streamId ?? -1;
  int get priority => _realChannel?.priority ?? _priority;
  bool get ordered => _realChannel?.ordered ?? _ordered;
  DataChannelState get state => _realChannel?.state ?? _state;

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

  Stream<dynamic> get onMessage =>
      _realChannel?.onMessage ?? _messageController.stream;

  Stream<dynamic> get onError =>
      _realChannel?.onError ?? _errorController.stream;

  Stream<DataChannelState> get onStateChange =>
      _realChannel?.onStateChange ?? _stateController.stream;

  /// Future that completes when channel is ready
  Future<DataChannel> get ready => _readyCompleter.future;

  /// Whether the channel has been initialized
  bool get isInitialized => _realChannel != null;

  /// Track if we've been closed
  bool _isClosed = false;

  /// Initialize with a real DataChannel (called when SCTP is ready)
  void initializeWithChannel(DataChannel channel) {
    if (_realChannel != null) return;

    _realChannel = channel;

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
    await _messageController.close();
    await _errorController.close();
    await _stateController.close();
  }

  @override
  String toString() {
    return 'ProxyDataChannel(label="$_label", initialized=${_realChannel != null}, state=$_state)';
  }
}
