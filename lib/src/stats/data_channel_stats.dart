import 'rtc_stats.dart';

/// Data channel state for stats
enum RTCDataChannelState {
  connecting('connecting'),
  open('open'),
  closing('closing'),
  closed('closed');

  final String value;
  const RTCDataChannelState(this.value);

  @override
  String toString() => value;
}

/// RTCDataChannelStats - Statistics for data channels
class RTCDataChannelStats extends RTCStats {
  /// Label of the data channel
  final String? label;

  /// Protocol of the data channel
  final String? protocol;

  /// ID of the data channel (as negotiated in SCTP)
  final int? dataChannelIdentifier;

  /// Current state of the data channel
  final RTCDataChannelState state;

  /// Number of messages sent
  final int? messagesSent;

  /// Number of bytes sent
  final int? bytesSent;

  /// Number of messages received
  final int? messagesReceived;

  /// Number of bytes received
  final int? bytesReceived;

  const RTCDataChannelStats({
    required super.timestamp,
    required super.id,
    this.label,
    this.protocol,
    this.dataChannelIdentifier,
    required this.state,
    this.messagesSent,
    this.bytesSent,
    this.messagesReceived,
    this.bytesReceived,
  }) : super(type: RTCStatsType.dataChannel);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'state': state.value,
      if (label != null) 'label': label,
      if (protocol != null) 'protocol': protocol,
      if (dataChannelIdentifier != null)
        'dataChannelIdentifier': dataChannelIdentifier,
      if (messagesSent != null) 'messagesSent': messagesSent,
      if (bytesSent != null) 'bytesSent': bytesSent,
      if (messagesReceived != null) 'messagesReceived': messagesReceived,
      if (bytesReceived != null) 'bytesReceived': bytesReceived,
    });
    return json;
  }
}
