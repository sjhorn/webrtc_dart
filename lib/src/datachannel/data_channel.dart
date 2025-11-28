import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/datachannel/dcep.dart';

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

  /// Reliability parameter
  final int reliabilityParameter;

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

    await _association.sendData(
      streamId: streamId,
      data: openMessage.serialize(),
      ppid: SctpPpid.dcep.value,
      unordered: false,
    );
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
  Future<void> close() async {
    if (_state == DataChannelState.closed ||
        _state == DataChannelState.closing) {
      return;
    }

    _setState(DataChannelState.closing);

    // TODO: Send final messages and wait for delivery

    _setState(DataChannelState.closed);
    await _dispose();
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

/// Data Channel Manager
/// Manages multiple data channels over an SCTP association
class DataChannelManager {
  /// SCTP association
  final SctpAssociation association;

  /// Data channels by stream ID
  final Map<int, DataChannel> _channels = {};

  /// Next even stream ID (for locally initiated channels)
  int _nextEvenStreamId = 0;

  DataChannelManager({required this.association}) {
    // Setup association data handler
    // Note: This would need to be integrated with SctpAssociation.onReceiveData
  }

  /// Create a new data channel
  Future<DataChannel> createDataChannel({
    required String label,
    String protocol = '',
    DataChannelType channelType = DataChannelType.reliable,
    int priority = 0,
    int reliabilityParameter = 0,
  }) async {
    // Allocate even stream ID (locally initiated)
    final streamId = _nextEvenStreamId;
    _nextEvenStreamId += 2;

    final channel = DataChannel(
      label: label,
      protocol: protocol,
      streamId: streamId,
      channelType: channelType,
      priority: priority,
      reliabilityParameter: reliabilityParameter,
      association: association,
    );

    _channels[streamId] = channel;

    // Open the channel
    await channel.open();

    return channel;
  }

  /// Handle incoming data on a stream
  Future<void> handleIncomingData(
      int streamId, Uint8List data, int ppid) async {
    var channel = _channels[streamId];

    // If channel doesn't exist and this is a DCEP OPEN, create it
    if (channel == null && ppid == SctpPpid.dcep.value) {
      try {
        final message = parseDcepMessage(data);
        if (message is DcepOpenMessage) {
          channel = DataChannel(
            label: message.label,
            protocol: message.protocol,
            streamId: streamId,
            channelType: message.channelType,
            priority: message.priority,
            reliabilityParameter: message.reliabilityParameter,
            association: association,
          );
          _channels[streamId] = channel;
        }
      } catch (e) {
        // Invalid DCEP message, ignore
        return;
      }
    }

    if (channel != null) {
      await channel.handleIncomingData(data, ppid);
    }
  }

  /// Get data channel by stream ID
  DataChannel? getChannel(int streamId) {
    return _channels[streamId];
  }

  /// Get all data channels
  List<DataChannel> getAllChannels() {
    return _channels.values.toList();
  }

  /// Close all data channels
  Future<void> closeAll() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
    _channels.clear();
  }
}
