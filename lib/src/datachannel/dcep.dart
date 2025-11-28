import 'dart:typed_data';

/// Data Channel Establishment Protocol (DCEP)
/// RFC 8832 - WebRTC Data Channel Establishment Protocol

/// DCEP Message Types
enum DcepMessageType {
  dataChannelOpen(0x03),
  dataChannelAck(0x02);

  final int value;
  const DcepMessageType(this.value);

  static DcepMessageType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Data Channel Types
enum DataChannelType {
  /// Reliable ordered
  reliable(0x00),

  /// Reliable unordered
  reliableUnordered(0x80),

  /// Partial reliable rexmit
  partialReliableRexmit(0x01),

  /// Partial reliable rexmit unordered
  partialReliableRexmitUnordered(0x81),

  /// Partial reliable timed
  partialReliableTimed(0x02),

  /// Partial reliable timed unordered
  partialReliableTimedUnordered(0x82);

  final int value;
  const DataChannelType(this.value);

  static DataChannelType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }

  /// Check if ordered
  bool get isOrdered => (value & 0x80) == 0;

  /// Check if reliable
  bool get isReliable => (value & 0x7F) == 0;
}

/// Data Channel Priority
enum DataChannelPriority {
  veryLow(128),
  low(256),
  medium(512),
  high(1024);

  final int value;
  const DataChannelPriority(this.value);
}

/// DATA_CHANNEL_OPEN Message
/// RFC 8832 Section 5.1
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  Message Type |  Channel Type |            Priority           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                    Reliability Parameter                      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |         Label Length          |       Protocol Length         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                                                               |
/// |                             Label                             |
/// |                                                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                                                               |
/// |                            Protocol                           |
/// |                                                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class DcepOpenMessage {
  /// Message type (always DATA_CHANNEL_OPEN)
  final DcepMessageType messageType = DcepMessageType.dataChannelOpen;

  /// Channel type
  final DataChannelType channelType;

  /// Priority
  final int priority;

  /// Reliability parameter
  final int reliabilityParameter;

  /// Label
  final String label;

  /// Protocol
  final String protocol;

  const DcepOpenMessage({
    required this.channelType,
    required this.priority,
    required this.reliabilityParameter,
    required this.label,
    required this.protocol,
  });

  /// Serialize to bytes
  Uint8List serialize() {
    final labelBytes = Uint8List.fromList(label.codeUnits);
    final protocolBytes = Uint8List.fromList(protocol.codeUnits);

    final size = 12 + labelBytes.length + protocolBytes.length;
    final result = Uint8List(size);
    final buffer = ByteData.sublistView(result);

    buffer.setUint8(0, messageType.value);
    buffer.setUint8(1, channelType.value);
    buffer.setUint16(2, priority);
    buffer.setUint32(4, reliabilityParameter);
    buffer.setUint16(8, labelBytes.length);
    buffer.setUint16(10, protocolBytes.length);

    result.setRange(12, 12 + labelBytes.length, labelBytes);
    result.setRange(
        12 + labelBytes.length,
        12 + labelBytes.length + protocolBytes.length,
        protocolBytes);

    return result;
  }

  /// Parse from bytes
  static DcepOpenMessage parse(Uint8List data) {
    if (data.length < 12) {
      throw FormatException('DCEP OPEN message too short');
    }

    final buffer = ByteData.sublistView(data);

    final messageType = DcepMessageType.fromValue(buffer.getUint8(0));
    if (messageType != DcepMessageType.dataChannelOpen) {
      throw FormatException('Not a DATA_CHANNEL_OPEN message');
    }

    final channelTypeValue = buffer.getUint8(1);
    final channelType = DataChannelType.fromValue(channelTypeValue);
    if (channelType == null) {
      throw FormatException('Unknown channel type: $channelTypeValue');
    }

    final priority = buffer.getUint16(2);
    final reliabilityParameter = buffer.getUint32(4);
    final labelLength = buffer.getUint16(8);
    final protocolLength = buffer.getUint16(10);

    if (data.length < 12 + labelLength + protocolLength) {
      throw FormatException('DCEP OPEN message incomplete');
    }

    final labelBytes = data.sublist(12, 12 + labelLength);
    final protocolBytes = data.sublist(12 + labelLength, 12 + labelLength + protocolLength);

    final label = String.fromCharCodes(labelBytes);
    final protocol = String.fromCharCodes(protocolBytes);

    return DcepOpenMessage(
      channelType: channelType,
      priority: priority,
      reliabilityParameter: reliabilityParameter,
      label: label,
      protocol: protocol,
    );
  }

  @override
  String toString() {
    return 'DCEP_OPEN(type=$channelType, label="$label", protocol="$protocol")';
  }
}

/// DATA_CHANNEL_ACK Message
/// RFC 8832 Section 5.2
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  Message Type |
/// +-+-+-+-+-+-+-+-+
class DcepAckMessage {
  /// Message type (always DATA_CHANNEL_ACK)
  final DcepMessageType messageType = DcepMessageType.dataChannelAck;

  const DcepAckMessage();

  /// Serialize to bytes
  Uint8List serialize() {
    final result = Uint8List(1);
    result[0] = messageType.value;
    return result;
  }

  /// Parse from bytes
  static DcepAckMessage parse(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('DCEP ACK message too short');
    }

    final messageType = DcepMessageType.fromValue(data[0]);
    if (messageType != DcepMessageType.dataChannelAck) {
      throw FormatException('Not a DATA_CHANNEL_ACK message');
    }

    return const DcepAckMessage();
  }

  @override
  String toString() {
    return 'DCEP_ACK';
  }
}

/// Parse DCEP message
dynamic parseDcepMessage(Uint8List data) {
  if (data.isEmpty) {
    throw FormatException('DCEP message empty');
  }

  final messageType = DcepMessageType.fromValue(data[0]);
  if (messageType == null) {
    throw FormatException('Unknown DCEP message type: ${data[0]}');
  }

  switch (messageType) {
    case DcepMessageType.dataChannelOpen:
      return DcepOpenMessage.parse(data);
    case DcepMessageType.dataChannelAck:
      return DcepAckMessage.parse(data);
  }
}
