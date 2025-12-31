import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/datachannel/dcep.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/sctp/const.dart';

final _log = WebRtcLogging.datachannel;

/// DataChannel Manager
/// Manages multiple DataChannels over a single SCTP association
class DataChannelManager {
  /// SCTP association
  final SctpAssociation _association;

  /// Map of stream ID to DataChannel
  final Map<int, DataChannel> _channels = {};

  /// Next stream ID for outgoing channels
  /// Per RFC 8832: DTLS client uses even (0, 2, 4...), server uses odd (1, 3, 5...)
  int _nextStreamId;

  /// Stream controller for new channels
  final StreamController<DataChannel> _channelController =
      StreamController<DataChannel>.broadcast();

  /// Create a DataChannel manager
  /// [isDtlsServer] determines stream ID allocation per RFC 8832:
  /// - DTLS client uses even stream IDs (0, 2, 4, ...)
  /// - DTLS server uses odd stream IDs (1, 3, 5, ...)
  DataChannelManager({
    required SctpAssociation association,
    bool isDtlsServer = false,
  })  : _association = association,
        _nextStreamId = isDtlsServer ? 1 : 0 {
    // Listen for incoming data from SCTP
    // Note: This requires modifying SctpAssociation to expose a stream
    // For now, we'll set up the callback

    // Handle stream reconfiguration (RFC 6525)
    _association.onReconfigStreams = _handleReconfigStreams;

    // Handle buffered amount changes for flow control
    _association.onBufferedAmountChange = _handleBufferedAmountChange;
  }

  /// Handle buffered amount changes from SCTP association
  /// Dispatches to the appropriate DataChannel based on streamId
  void _handleBufferedAmountChange(int streamId, int bufferedAmount) {
    final channel = _channels[streamId];
    if (channel != null) {
      channel.handleBufferedAmountChange(bufferedAmount);
    }
  }

  /// Handle stream reconfiguration (close event from peer or response to our close)
  void _handleReconfigStreams(List<int> streamIds) {
    for (final streamId in streamIds) {
      final channel = _channels[streamId];
      if (channel != null) {
        channel.handleStreamReset();
        _channels.remove(streamId);
      }
    }
  }

  /// Stream of new incoming DataChannels
  Stream<DataChannel> get onDataChannel => _channelController.stream;

  /// Create a new outbound DataChannel
  DataChannel createDataChannel({
    required String label,
    String protocol = '',
    bool ordered = true,
    int? maxRetransmits,
    int? maxPacketLifeTime,
    int priority = 0,
  }) {
    // Determine channel type based on reliability parameters
    DataChannelType channelType;
    int reliabilityParameter;

    if (maxRetransmits != null) {
      channelType = ordered
          ? DataChannelType.partialReliableRexmit
          : DataChannelType.partialReliableRexmitUnordered;
      reliabilityParameter = maxRetransmits;
    } else if (maxPacketLifeTime != null) {
      channelType = ordered
          ? DataChannelType.partialReliableTimed
          : DataChannelType.partialReliableTimedUnordered;
      reliabilityParameter = maxPacketLifeTime;
    } else {
      channelType = ordered
          ? DataChannelType.reliable
          : DataChannelType.reliableUnordered;
      reliabilityParameter = 0;
    }

    // Allocate stream ID (even numbers for locally initiated channels)
    final streamId = _nextStreamId;
    _nextStreamId += 2;

    // Create channel
    final channel = DataChannel(
      label: label,
      protocol: protocol,
      streamId: streamId,
      channelType: channelType,
      priority: priority,
      reliabilityParameter: reliabilityParameter,
      association: _association,
    );

    // Register channel
    _channels[streamId] = channel;

    _log.fine('Creating DataChannel: label=$label, streamId=$streamId');

    // Open the channel (sends DCEP OPEN)
    _log.fine('Calling channel.open() for streamId=$streamId');
    channel.open().then((_) {
      _log.fine('channel.open() completed for streamId=$streamId');
    }).catchError((e) {
      // Handle error
      _log.warning('Failed to open DataChannel: $e');
    });

    return channel;
  }

  /// Handle incoming SCTP data
  void handleIncomingData(int streamId, Uint8List data, int ppid) {
    // Check if we have a channel for this stream
    var channel = _channels[streamId];

    if (channel == null) {
      // New incoming channel, check if this is a DCEP OPEN
      if (ppid == SctpPpid.dcep.value) {
        final message = parseDcepMessage(data);
        if (message is DcepOpenMessage) {
          // Create incoming channel
          channel = DataChannel(
            label: message.label,
            protocol: message.protocol,
            streamId: streamId,
            channelType: message.channelType,
            priority: message.priority,
            reliabilityParameter: message.reliabilityParameter,
            association: _association,
          );

          _channels[streamId] = channel;

          // Deliver the OPEN message to trigger ACK
          channel.handleIncomingData(data, ppid);

          // Notify listeners of new channel
          _channelController.add(channel);
          return;
        }
      }

      // Unknown stream, ignore
      _log.warning('Received data on unknown stream $streamId');
      return;
    }

    // Deliver to channel
    channel.handleIncomingData(data, ppid);
  }

  /// Close all channels
  Future<void> close() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
    _channels.clear();
    await _channelController.close();
  }
}
