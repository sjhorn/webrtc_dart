import 'dart:typed_data';

/// RTP Extensions for Transport-wide Congestion Control
/// draft-holmer-rmcat-transport-wide-cc-extensions-01
///
///    0               1               2               3
///    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |V=2|P|  FMT=15 |    PT=205     |           length              |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |                     SSRC of packet sender                     |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |                      SSRC of media source                     |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |      base sequence number     |      packet status count      |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |                 reference time                | fb pkt. count |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |          packet chunk         |         packet chunk          |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   .                                                               .
///   .                                                               .
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |         packet chunk          |  recv delta   |  recv delta   |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   .                                                               .
///   .                                                               .
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///   |           recv delta          |  recv delta   | zero padding  |
///   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

/// RTCP Transport Layer Feedback Type (PT=205)
const int rtcpTransportLayerFeedbackType = 205;

/// TWCC Format/Count value (FMT=15)
const int twccCount = 15;

/// Packet chunk type enum
enum PacketChunk {
  /// Run-length chunk type (T=0)
  typeRunLength(0),

  /// Status vector chunk type (T=1)
  typeStatusVector(1);

  const PacketChunk(this.value);
  final int value;

  static const packetStatusChunkLength = 2;
}

/// Packet status enum
enum PacketStatus {
  /// Packet not received
  notReceived(0),

  /// Packet received with small delta (1 byte)
  receivedSmallDelta(1),

  /// Packet received with large delta (2 bytes)
  receivedLargeDelta(2),

  /// Packet received without delta
  receivedWithoutDelta(3);

  const PacketStatus(this.value);
  final int value;

  static PacketStatus fromValue(int value) {
    return PacketStatus.values.firstWhere((e) => e.value == value);
  }
}

/// Extract bits from a byte
int _getBit(int byte, int position, int length) {
  return (byte >> (8 - position - length)) & ((1 << length) - 1);
}

/// Run-length chunk for packet status encoding
///
///   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5
///  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///  |T| S |       Run Length        |
///  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RunLengthChunk {
  /// Chunk type (always 0 for run-length)
  final PacketChunk type = PacketChunk.typeRunLength;

  /// Packet status for all packets in this run
  final PacketStatus packetStatus;

  /// Number of packets (13 bits, max 8191)
  final int runLength;

  RunLengthChunk({
    required this.packetStatus,
    required this.runLength,
  });

  /// Deserialize from 2 bytes
  static RunLengthChunk deSerialize(Uint8List data) {
    final packetStatus = _getBit(data[0], 1, 2);
    final runLength = (_getBit(data[0], 3, 5) << 8) + data[1];

    return RunLengthChunk(
      packetStatus: PacketStatus.fromValue(packetStatus),
      runLength: runLength,
    );
  }

  /// Serialize to 2 bytes
  Uint8List serialize() {
    final result = Uint8List(2);
    // T=0 (1 bit), S (2 bits), runLength (13 bits)
    final value = (0 << 15) | // T=0
        (packetStatus.value << 13) | // S (2 bits)
        (runLength & 0x1FFF); // runLength (13 bits)
    result[0] = (value >> 8) & 0xFF;
    result[1] = value & 0xFF;
    return result;
  }

  /// Generate packet results from this chunk
  List<PacketResult> results(int currentSequenceNumber) {
    final received = packetStatus == PacketStatus.receivedSmallDelta ||
        packetStatus == PacketStatus.receivedLargeDelta;

    final results = <PacketResult>[];
    var seqNum = currentSequenceNumber;
    for (var i = 0; i <= runLength; i++) {
      seqNum++;
      results.add(PacketResult(sequenceNumber: seqNum, received: received));
    }
    return results;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunLengthChunk &&
          packetStatus == other.packetStatus &&
          runLength == other.runLength;

  @override
  int get hashCode => packetStatus.hashCode ^ runLength.hashCode;

  @override
  String toString() =>
      'RunLengthChunk(status: $packetStatus, runLength: $runLength)';
}

/// Status vector chunk for packet status encoding
///
///   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5
///  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///  |T|S|       symbol list         |
///  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class StatusVectorChunk {
  /// Chunk type (always 1 for status vector)
  final PacketChunk type = PacketChunk.typeStatusVector;

  /// Symbol size: 0 = 1-bit symbols (14 symbols), 1 = 2-bit symbols (7 symbols)
  final int symbolSize;

  /// List of packet statuses
  final List<int> symbolList;

  StatusVectorChunk({
    required this.symbolSize,
    required this.symbolList,
  });

  /// Deserialize from 2 bytes
  static StatusVectorChunk deSerialize(Uint8List data) {
    final symbolSize = _getBit(data[0], 1, 1);
    final symbolList = <int>[];

    if (symbolSize == 0) {
      // 1-bit symbols: 6 from first byte, 8 from second byte
      for (var i = 0; i < 6; i++) {
        symbolList.add(_getBit(data[0], 2 + i, 1));
      }
      for (var i = 0; i < 8; i++) {
        symbolList.add(_getBit(data[1], i, 1));
      }
    } else {
      // 2-bit symbols: 3 from first byte, 4 from second byte
      for (var i = 0; i < 3; i++) {
        symbolList.add(_getBit(data[0], 2 + i * 2, 2));
      }
      for (var i = 0; i < 4; i++) {
        symbolList.add(_getBit(data[1], i * 2, 2));
      }
    }

    return StatusVectorChunk(
      symbolSize: symbolSize,
      symbolList: symbolList,
    );
  }

  /// Serialize to 2 bytes
  Uint8List serialize() {
    final result = Uint8List(2);

    // Build 16-bit value: T(1) | S(1) | symbols(14)
    var value = (1 << 15) | (symbolSize << 14); // T=1, S

    final bits = symbolSize == 0 ? 1 : 2;
    var bitPosition = 14;

    for (final symbol in symbolList) {
      bitPosition -= bits;
      value |= (symbol & ((1 << bits) - 1)) << bitPosition;
    }

    result[0] = (value >> 8) & 0xFF;
    result[1] = value & 0xFF;
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusVectorChunk &&
          symbolSize == other.symbolSize &&
          _listEquals(symbolList, other.symbolList);

  @override
  int get hashCode => symbolSize.hashCode ^ symbolList.hashCode;

  @override
  String toString() =>
      'StatusVectorChunk(symbolSize: $symbolSize, symbolList: $symbolList)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Receive delta - time between consecutive received packets
///
/// Small delta (1 byte): 250µs resolution, 0 to 63.75ms
/// Large delta (2 bytes): 250µs resolution, -8192ms to +8191.75ms
class RecvDelta {
  /// Delta type (small or large)
  PacketStatus? type;

  /// Delta in microseconds
  int delta;

  /// Whether delta has been parsed for serialization
  bool _parsed = false;

  RecvDelta({
    this.type,
    required this.delta,
  });

  /// Deserialize from buffer
  static RecvDelta deSerialize(Uint8List data) {
    PacketStatus type;
    int delta;

    if (data.length == 1) {
      type = PacketStatus.receivedSmallDelta;
      delta = 250 * data[0];
    } else if (data.length == 2) {
      type = PacketStatus.receivedLargeDelta;
      final view = ByteData.sublistView(data);
      delta = 250 * view.getInt16(0);
    } else {
      throw FormatException('Invalid RecvDelta length: ${data.length}');
    }

    return RecvDelta(type: type, delta: delta);
  }

  /// Parse delta value for serialization
  void _parseDelta() {
    delta = delta ~/ 250;

    if (delta < 0 || delta > 255) {
      if (delta > 32767) delta = 32767;
      if (delta < -32768) delta = -32768;
      type ??= PacketStatus.receivedLargeDelta;
    } else {
      type ??= PacketStatus.receivedSmallDelta;
    }
    _parsed = true;
  }

  /// Serialize to bytes
  Uint8List serialize() {
    if (!_parsed) _parseDelta();

    if (type == PacketStatus.receivedSmallDelta) {
      return Uint8List.fromList([delta & 0xFF]);
    } else if (type == PacketStatus.receivedLargeDelta) {
      final buf = Uint8List(2);
      final view = ByteData.sublistView(buf);
      view.setInt16(0, delta);
      return buf;
    }

    throw StateError('Invalid delta type: $type, delta: $delta');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecvDelta && type == other.type && delta == other.delta;

  @override
  int get hashCode => type.hashCode ^ delta.hashCode;

  @override
  String toString() => 'RecvDelta(type: $type, delta: $delta)';
}

/// Packet result from TWCC feedback
class PacketResult {
  /// Transport-wide sequence number
  int sequenceNumber;

  /// Delta time in microseconds
  int delta;

  /// Whether packet was received
  bool received;

  /// Receive time in milliseconds (from reference time)
  int receivedAtMs;

  PacketResult({
    this.sequenceNumber = 0,
    this.delta = 0,
    this.received = false,
    this.receivedAtMs = 0,
  });
}

/// RTCP Header for TWCC packets
class RtcpHeader {
  final int version;
  final bool padding;
  final int count;
  final int type;
  int length;

  RtcpHeader({
    this.version = 2,
    this.padding = false,
    this.count = 0,
    this.type = 0,
    this.length = 0,
  });

  static const headerSize = 4;

  /// Deserialize from buffer
  static RtcpHeader deSerialize(Uint8List data) {
    final byte0 = data[0];
    final version = (byte0 >> 6) & 0x03;
    final padding = (byte0 & 0x20) != 0;
    final count = byte0 & 0x1F;
    final type = data[1];
    final length = (data[2] << 8) | data[3];

    return RtcpHeader(
      version: version,
      padding: padding,
      count: count,
      type: type,
      length: length,
    );
  }

  /// Serialize to bytes
  Uint8List serialize() {
    final result = Uint8List(4);
    result[0] = (version << 6) | (padding ? 0x20 : 0) | (count & 0x1F);
    result[1] = type;
    result[2] = (length >> 8) & 0xFF;
    result[3] = length & 0xFF;
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtcpHeader &&
          version == other.version &&
          padding == other.padding &&
          count == other.count &&
          type == other.type &&
          length == other.length;

  @override
  int get hashCode =>
      version.hashCode ^
      padding.hashCode ^
      count.hashCode ^
      type.hashCode ^
      length.hashCode;
}

/// Transport-Wide Congestion Control RTCP Feedback
class TransportWideCC {
  /// TWCC format count (FMT=15)
  static const int count = 15;

  /// SSRC of packet sender
  final int senderSsrc;

  /// SSRC of media source
  final int mediaSourceSsrc;

  /// Base transport-wide sequence number
  final int baseSequenceNumber;

  /// Number of packets reported on
  final int packetStatusCount;

  /// Reference time (24-bit, multiples of 64ms)
  final int referenceTime;

  /// Feedback packet count (8-bit, wraps at 256)
  final int fbPktCount;

  /// Packet status chunks
  final List<dynamic> packetChunks; // RunLengthChunk or StatusVectorChunk

  /// Receive deltas
  final List<RecvDelta> recvDeltas;

  /// RTCP header
  RtcpHeader header;

  TransportWideCC({
    required this.senderSsrc,
    required this.mediaSourceSsrc,
    required this.baseSequenceNumber,
    required this.packetStatusCount,
    required this.referenceTime,
    required this.fbPktCount,
    required this.packetChunks,
    required this.recvDeltas,
    RtcpHeader? header,
  }) : header = header ??
            RtcpHeader(
              type: rtcpTransportLayerFeedbackType,
              count: count,
              version: 2,
            );

  /// Deserialize from buffer (without RTCP header)
  static TransportWideCC deSerialize(Uint8List data, RtcpHeader header) {
    final view = ByteData.sublistView(data);

    final senderSsrc = view.getUint32(0);
    final mediaSourceSsrc = view.getUint32(4);
    final baseSequenceNumber = view.getUint16(8);
    final packetStatusCount = view.getUint16(10);

    // Reference time is 24-bit, fbPktCount is 8-bit
    final referenceTime =
        (data[12] << 16) | (data[13] << 8) | data[14];
    final fbPktCount = data[15];

    final packetChunks = <dynamic>[];
    final recvDeltas = <RecvDelta>[];

    var packetStatusPos = 16;
    var processedPacketNum = 0;

    while (processedPacketNum < packetStatusCount) {
      if (packetStatusPos + 2 > data.length) break;

      final chunkType = _getBit(data[packetStatusPos], 0, 1);

      if (chunkType == PacketChunk.typeRunLength.value) {
        final chunk = RunLengthChunk.deSerialize(
          data.sublist(packetStatusPos, packetStatusPos + 2),
        );
        packetChunks.add(chunk);

        final packetNumberToProcess = (packetStatusCount - processedPacketNum)
            .clamp(0, chunk.runLength);

        if (chunk.packetStatus == PacketStatus.receivedSmallDelta ||
            chunk.packetStatus == PacketStatus.receivedLargeDelta) {
          for (var i = 0; i < packetNumberToProcess; i++) {
            recvDeltas.add(RecvDelta(type: chunk.packetStatus, delta: 0));
          }
        }
        processedPacketNum += packetNumberToProcess;
      } else {
        final chunk = StatusVectorChunk.deSerialize(
          data.sublist(packetStatusPos, packetStatusPos + 2),
        );
        packetChunks.add(chunk);

        if (chunk.symbolSize == 0) {
          for (final v in chunk.symbolList) {
            if (v == PacketStatus.receivedSmallDelta.value) {
              recvDeltas.add(
                  RecvDelta(type: PacketStatus.receivedSmallDelta, delta: 0));
            }
          }
        } else {
          for (final v in chunk.symbolList) {
            if (v == PacketStatus.receivedSmallDelta.value ||
                v == PacketStatus.receivedLargeDelta.value) {
              recvDeltas
                  .add(RecvDelta(type: PacketStatus.fromValue(v), delta: 0));
            }
          }
        }
        processedPacketNum += chunk.symbolList.length;
      }

      packetStatusPos += 2;
    }

    // Parse receive deltas
    var recvDeltaPos = packetStatusPos;
    for (final delta in recvDeltas) {
      if (delta.type == PacketStatus.receivedSmallDelta) {
        if (recvDeltaPos + 1 > data.length) break;
        final parsed =
            RecvDelta.deSerialize(data.sublist(recvDeltaPos, recvDeltaPos + 1));
        delta.delta = parsed.delta;
        recvDeltaPos++;
      } else if (delta.type == PacketStatus.receivedLargeDelta) {
        if (recvDeltaPos + 2 > data.length) break;
        final parsed =
            RecvDelta.deSerialize(data.sublist(recvDeltaPos, recvDeltaPos + 2));
        delta.delta = parsed.delta;
        recvDeltaPos += 2;
      }
    }

    return TransportWideCC(
      senderSsrc: senderSsrc,
      mediaSourceSsrc: mediaSourceSsrc,
      baseSequenceNumber: baseSequenceNumber,
      packetStatusCount: packetStatusCount,
      referenceTime: referenceTime,
      fbPktCount: fbPktCount,
      packetChunks: packetChunks,
      recvDeltas: recvDeltas,
      header: header,
    );
  }

  /// Serialize to bytes (including RTCP header)
  Uint8List serialize() {
    // Build payload
    final payloadParts = <int>[];

    // Fixed fields (16 bytes)
    final constBuf = Uint8List(16);
    final constView = ByteData.sublistView(constBuf);
    constView.setUint32(0, senderSsrc);
    constView.setUint32(4, mediaSourceSsrc);
    constView.setUint16(8, baseSequenceNumber);
    constView.setUint16(10, packetStatusCount);
    constBuf[12] = (referenceTime >> 16) & 0xFF;
    constBuf[13] = (referenceTime >> 8) & 0xFF;
    constBuf[14] = referenceTime & 0xFF;
    constBuf[15] = fbPktCount;
    payloadParts.addAll(constBuf);

    // Packet chunks
    for (final chunk in packetChunks) {
      if (chunk is RunLengthChunk) {
        payloadParts.addAll(chunk.serialize());
      } else if (chunk is StatusVectorChunk) {
        payloadParts.addAll(chunk.serialize());
      }
    }

    // Receive deltas
    for (final delta in recvDeltas) {
      try {
        payloadParts.addAll(delta.serialize());
      } catch (e) {
        // Skip invalid deltas
      }
    }

    final payload = Uint8List.fromList(payloadParts);

    // Add padding if needed
    if (header.padding && payload.length % 4 != 0) {
      final rest = 4 - (payload.length % 4);
      final padding = Uint8List(rest);
      padding[padding.length - 1] = padding.length;

      header.length = (payload.length + padding.length) ~/ 4;
      final headerBytes = header.serialize();

      return Uint8List.fromList([...headerBytes, ...payload, ...padding]);
    }

    header.length = payload.length ~/ 4;
    final headerBytes = header.serialize();

    return Uint8List.fromList([...headerBytes, ...payload]);
  }

  /// Get decoded packet results
  List<PacketResult> get packetResults {
    final currentSequenceNumber = baseSequenceNumber - 1;
    final results = packetChunks
        .whereType<RunLengthChunk>()
        .expand((chunk) => chunk.results(currentSequenceNumber))
        .toList();

    var deltaIdx = 0;
    final refTime = BigInt.from(referenceTime) * BigInt.from(64);
    var currentReceivedAtMs = refTime;

    for (final result in results) {
      if (deltaIdx >= recvDeltas.length) break;
      final recvDelta = recvDeltas[deltaIdx];
      if (!result.received) continue;

      currentReceivedAtMs += BigInt.from(recvDelta.delta) ~/ BigInt.from(1000);
      result.delta = recvDelta.delta;
      result.receivedAtMs = currentReceivedAtMs.toInt();
      deltaIdx++;
    }

    return results;
  }
}
