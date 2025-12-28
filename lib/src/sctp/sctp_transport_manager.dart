import 'dart:async';

import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/stats/data_channel_stats.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';

/// SctpTransportManager handles DataChannel lifecycle management.
///
/// This class matches the architecture of werift-webrtc's SctpTransportManager,
/// providing separation of concerns from the main PeerConnection class.
///
/// Responsibilities:
/// - Managing the list of data channels
/// - Tracking data channel counters (opened/closed)
/// - Firing onDataChannel events
/// - Providing DataChannel statistics
///
/// Reference: werift-webrtc/packages/webrtc/src/sctpManager.ts
class SctpTransportManager {
  /// List of all data channels
  final List<DataChannel> _dataChannels = [];

  /// Counter for data channels opened
  int _dataChannelsOpened = 0;

  /// Counter for data channels closed
  int _dataChannelsClosed = 0;

  /// Stream controller for data channel events
  final StreamController<DataChannel> _dataChannelController =
      StreamController<DataChannel>.broadcast();

  /// Stream of data channel events (when remote creates a channel)
  Stream<DataChannel> get onDataChannel => _dataChannelController.stream;

  /// Get count of data channels opened
  int get dataChannelsOpened => _dataChannelsOpened;

  /// Get count of data channels closed
  int get dataChannelsClosed => _dataChannelsClosed;

  /// Get all data channels (unmodifiable list)
  List<DataChannel> get dataChannels => List.unmodifiable(_dataChannels);

  /// Register a locally created data channel
  /// Accepts dynamic to handle both DataChannel and ProxyDataChannel
  void registerLocalChannel(dynamic channel) {
    _dataChannelsOpened++;
    if (channel is DataChannel) {
      _dataChannels.add(channel);
      _setupChannelCloseHandler(channel);
    }
    // ProxyDataChannel will be registered when it connects to a real channel
    // The stats for proxy channels are tracked via the counter above
  }

  /// Register a remotely created data channel (fires onDataChannel event)
  void registerRemoteChannel(DataChannel channel) {
    _dataChannelsOpened++;
    _dataChannels.add(channel);
    _setupChannelCloseHandler(channel);
    _dataChannelController.add(channel);
  }

  /// Setup handler to track when channel closes
  void _setupChannelCloseHandler(DataChannel channel) {
    channel.onStateChange.listen((state) {
      if (state == DataChannelState.closed) {
        _dataChannelsClosed++;
        _dataChannels.remove(channel);
      }
    });
  }

  /// Convert DataChannelState to RTCDataChannelState for stats
  RTCDataChannelState _toStatsState(DataChannelState state) {
    switch (state) {
      case DataChannelState.connecting:
        return RTCDataChannelState.connecting;
      case DataChannelState.open:
        return RTCDataChannelState.open;
      case DataChannelState.closing:
        return RTCDataChannelState.closing;
      case DataChannelState.closed:
        return RTCDataChannelState.closed;
    }
  }

  /// Get DataChannel statistics
  /// Matches werift's SctpTransportManager.getStats()
  List<RTCStats> getStats() {
    final timestamp = getStatsTimestamp();
    final stats = <RTCStats>[];

    for (final channel in _dataChannels) {
      final channelStats = RTCDataChannelStats(
        timestamp: timestamp,
        id: generateStatsId('data-channel', [channel.streamId]),
        label: channel.label,
        protocol: channel.protocol,
        dataChannelIdentifier: channel.streamId,
        state: _toStatsState(channel.state),
        // Note: message/byte counters not yet implemented in DataChannel
        // These can be added when DataChannel tracks send/receive stats
      );
      stats.add(channelStats);
    }

    return stats;
  }

  /// Close the manager and release resources
  Future<void> close() async {
    await _dataChannelController.close();
    _dataChannels.clear();
  }
}
