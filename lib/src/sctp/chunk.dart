import 'dart:typed_data';
import 'package:webrtc_dart/src/sctp/const.dart';

/// SCTP Chunk
/// RFC 4960 Section 3.2
///
/// Chunk Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |   Chunk Type  | Chunk  Flags  |        Chunk Length           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                                                               |
/// |                          Chunk Value                          |
/// |                                                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
abstract class SctpChunk {
  /// Chunk type
  SctpChunkType get type;

  /// Chunk flags
  int get flags;

  /// Chunk length (including header)
  int get length;

  /// Serialize chunk to bytes
  Uint8List serialize();

  /// Parse chunk from bytes
  static SctpChunk parse(Uint8List data) {
    if (data.length < SctpConstants.chunkHeaderSize) {
      throw FormatException('Chunk too short');
    }

    final buffer = ByteData.sublistView(data);
    final typeValue = buffer.getUint8(0);
    final type = SctpChunkType.fromValue(typeValue);

    if (type == null) {
      throw FormatException('Unknown chunk type: $typeValue');
    }

    switch (type) {
      case SctpChunkType.data:
        return SctpDataChunk.parse(data);
      case SctpChunkType.init:
        return SctpInitChunk.parse(data);
      case SctpChunkType.initAck:
        return SctpInitAckChunk.parse(data);
      case SctpChunkType.sack:
        return SctpSackChunk.parse(data);
      case SctpChunkType.heartbeat:
        return SctpHeartbeatChunk.parse(data);
      case SctpChunkType.heartbeatAck:
        return SctpHeartbeatAckChunk.parse(data);
      case SctpChunkType.abort:
        return SctpAbortChunk.parse(data);
      case SctpChunkType.shutdown:
        return SctpShutdownChunk.parse(data);
      case SctpChunkType.shutdownAck:
        return SctpShutdownAckChunk.parse(data);
      case SctpChunkType.error:
        return SctpErrorChunk.parse(data);
      case SctpChunkType.cookieEcho:
        return SctpCookieEchoChunk.parse(data);
      case SctpChunkType.cookieAck:
        return SctpCookieAckChunk.parse(data);
      case SctpChunkType.shutdownComplete:
        return SctpShutdownCompleteChunk.parse(data);
      case SctpChunkType.forwardTsn:
        return SctpForwardTsnChunk.parse(data);
      case SctpChunkType.reconfig:
        throw UnimplementedError('RECONFIG chunk not implemented');
    }
  }

  /// Write chunk header
  void writeHeader(ByteData buffer, int offset) {
    buffer.setUint8(offset, type.value);
    buffer.setUint8(offset + 1, flags);
    buffer.setUint16(offset + 2, length);
  }
}

/// SCTP DATA Chunk
/// RFC 4960 Section 3.3.1
class SctpDataChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.data;

  @override
  final int flags;

  /// Transmission Sequence Number
  final int tsn;

  /// Stream Identifier
  final int streamId;

  /// Stream Sequence Number
  final int streamSeq;

  /// Payload Protocol Identifier
  final int ppid;

  /// User data
  final Uint8List userData;

  /// Unordered flag
  bool get unordered => (flags & SctpDataChunkFlags.unordered) != 0;

  /// Beginning fragment flag
  bool get beginningFragment =>
      (flags & SctpDataChunkFlags.beginningFragment) != 0;

  /// End fragment flag
  bool get endFragment => (flags & SctpDataChunkFlags.endFragment) != 0;

  @override
  int get length => SctpConstants.dataChunkMinSize + userData.length;

  SctpDataChunk({
    required this.tsn,
    required this.streamId,
    required this.streamSeq,
    required this.ppid,
    required this.userData,
    this.flags = 0x03, // Default: B=1, E=1 (complete message)
  });

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, tsn);
    buffer.setUint16(8, streamId);
    buffer.setUint16(10, streamSeq);
    buffer.setUint32(12, ppid);

    result.setRange(16, 16 + userData.length, userData);

    return result;
  }

  static SctpDataChunk parse(Uint8List data) {
    if (data.length < SctpConstants.dataChunkMinSize) {
      throw FormatException('DATA chunk too short');
    }

    final buffer = ByteData.sublistView(data);
    final flags = buffer.getUint8(1);
    final length = buffer.getUint16(2);
    final tsn = buffer.getUint32(4);
    final streamId = buffer.getUint16(8);
    final streamSeq = buffer.getUint16(10);
    final ppid = buffer.getUint32(12);

    final userDataLength = length - SctpConstants.dataChunkMinSize;
    final userData = data.sublist(16, 16 + userDataLength);

    return SctpDataChunk(
      tsn: tsn,
      streamId: streamId,
      streamSeq: streamSeq,
      ppid: ppid,
      userData: userData,
      flags: flags,
    );
  }

  @override
  String toString() {
    return 'DATA(tsn=$tsn, stream=$streamId, seq=$streamSeq, ppid=$ppid, ${userData.length} bytes)';
  }
}

/// SCTP INIT Chunk
/// RFC 4960 Section 3.3.2
class SctpInitChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.init;

  @override
  final int flags = 0;

  /// Initiate Tag
  final int initiateTag;

  /// Advertised Receiver Window Credit
  final int advertisedRwnd;

  /// Number of Outbound Streams
  final int outboundStreams;

  /// Number of Inbound Streams
  final int inboundStreams;

  /// Initial TSN
  final int initialTsn;

  /// Optional parameters
  final Uint8List? parameters;

  @override
  int get length =>
      SctpConstants.chunkHeaderSize +
      SctpConstants.initChunkMinSize +
      (parameters?.length ?? 0);

  SctpInitChunk({
    required this.initiateTag,
    required this.advertisedRwnd,
    required this.outboundStreams,
    required this.inboundStreams,
    required this.initialTsn,
    this.parameters,
  });

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, initiateTag);
    buffer.setUint32(8, advertisedRwnd);
    buffer.setUint16(12, outboundStreams);
    buffer.setUint16(14, inboundStreams);
    buffer.setUint32(16, initialTsn);

    if (parameters != null) {
      result.setRange(20, 20 + parameters!.length, parameters!);
    }

    return result;
  }

  static SctpInitChunk parse(Uint8List data) {
    if (data.length < SctpConstants.initChunkMinSize + 4) {
      throw FormatException('INIT chunk too short');
    }

    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final initiateTag = buffer.getUint32(4);
    final advertisedRwnd = buffer.getUint32(8);
    final outboundStreams = buffer.getUint16(12);
    final inboundStreams = buffer.getUint16(14);
    final initialTsn = buffer.getUint32(16);

    Uint8List? parameters;
    final totalMinSize =
        SctpConstants.chunkHeaderSize + SctpConstants.initChunkMinSize;
    if (length > totalMinSize) {
      final paramLength = length - totalMinSize;
      parameters = data.sublist(20, 20 + paramLength);
    }

    return SctpInitChunk(
      initiateTag: initiateTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: initialTsn,
      parameters: parameters,
    );
  }

  @override
  String toString() {
    return 'INIT(tag=0x${initiateTag.toRadixString(16)}, rwnd=$advertisedRwnd, out=$outboundStreams, in=$inboundStreams, tsn=$initialTsn)';
  }
}

/// SCTP INIT ACK Chunk
/// RFC 4960 Section 3.3.3
class SctpInitAckChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.initAck;

  @override
  final int flags = 0;

  /// Initiate Tag
  final int initiateTag;

  /// Advertised Receiver Window Credit
  final int advertisedRwnd;

  /// Number of Outbound Streams
  final int outboundStreams;

  /// Number of Inbound Streams
  final int inboundStreams;

  /// Initial TSN
  final int initialTsn;

  /// Optional parameters (including State Cookie)
  final Uint8List? parameters;

  @override
  int get length =>
      SctpConstants.chunkHeaderSize +
      SctpConstants.initChunkMinSize +
      (parameters?.length ?? 0);

  SctpInitAckChunk({
    required this.initiateTag,
    required this.advertisedRwnd,
    required this.outboundStreams,
    required this.inboundStreams,
    required this.initialTsn,
    this.parameters,
  });

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, initiateTag);
    buffer.setUint32(8, advertisedRwnd);
    buffer.setUint16(12, outboundStreams);
    buffer.setUint16(14, inboundStreams);
    buffer.setUint32(16, initialTsn);

    if (parameters != null) {
      result.setRange(20, 20 + parameters!.length, parameters!);
    }

    return result;
  }

  static SctpInitAckChunk parse(Uint8List data) {
    if (data.length < SctpConstants.initChunkMinSize + 4) {
      throw FormatException('INIT-ACK chunk too short');
    }

    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final initiateTag = buffer.getUint32(4);
    final advertisedRwnd = buffer.getUint32(8);
    final outboundStreams = buffer.getUint16(12);
    final inboundStreams = buffer.getUint16(14);
    final initialTsn = buffer.getUint32(16);

    Uint8List? parameters;
    final totalMinSize =
        SctpConstants.chunkHeaderSize + SctpConstants.initChunkMinSize;
    if (length > totalMinSize) {
      final paramLength = length - totalMinSize;
      parameters = data.sublist(20, 20 + paramLength);
    }

    return SctpInitAckChunk(
      initiateTag: initiateTag,
      advertisedRwnd: advertisedRwnd,
      outboundStreams: outboundStreams,
      inboundStreams: inboundStreams,
      initialTsn: initialTsn,
      parameters: parameters,
    );
  }

  /// Extract state cookie from parameters (TLV encoded)
  /// State Cookie parameter type = 7
  Uint8List? getStateCookie() {
    if (parameters == null || parameters!.isEmpty) return null;

    var offset = 0;
    while (offset + 4 <= parameters!.length) {
      final buffer = ByteData.sublistView(parameters!, offset);
      final paramType = buffer.getUint16(0);
      final paramLength = buffer.getUint16(2);

      // State Cookie parameter type is 7
      if (paramType == 7) {
        // Return the value (skip 4-byte TLV header)
        final valueLength = paramLength - 4;
        if (offset + 4 + valueLength <= parameters!.length) {
          return parameters!.sublist(offset + 4, offset + 4 + valueLength);
        }
      }

      // Move to next parameter (with padding to 4-byte boundary)
      final paddedLength = (paramLength + 3) & ~3;
      offset += paddedLength;
    }

    return null;
  }

  @override
  String toString() {
    return 'INIT-ACK(tag=0x${initiateTag.toRadixString(16)}, rwnd=$advertisedRwnd, out=$outboundStreams, in=$inboundStreams, tsn=$initialTsn)';
  }
}

/// SCTP SACK Chunk
/// RFC 4960 Section 3.3.4
class SctpSackChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.sack;

  @override
  final int flags = 0;

  /// Cumulative TSN Ack
  final int cumulativeTsnAck;

  /// Advertised Receiver Window Credit
  final int advertisedRwnd;

  /// Gap Ack Blocks
  final List<GapAckBlock> gapAckBlocks;

  /// Duplicate TSNs
  final List<int> duplicateTsns;

  @override
  int get length =>
      SctpConstants.chunkHeaderSize +
      SctpConstants.sackChunkMinSize +
      (gapAckBlocks.length * 4) +
      (duplicateTsns.length * 4);

  SctpSackChunk({
    required this.cumulativeTsnAck,
    required this.advertisedRwnd,
    this.gapAckBlocks = const [],
    this.duplicateTsns = const [],
  });

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, cumulativeTsnAck);
    buffer.setUint32(8, advertisedRwnd);
    buffer.setUint16(12, gapAckBlocks.length);
    buffer.setUint16(14, duplicateTsns.length);

    var offset = 16;

    // Write gap ack blocks
    for (final gap in gapAckBlocks) {
      buffer.setUint16(offset, gap.start);
      buffer.setUint16(offset + 2, gap.end);
      offset += 4;
    }

    // Write duplicate TSNs
    for (final tsn in duplicateTsns) {
      buffer.setUint32(offset, tsn);
      offset += 4;
    }

    return result;
  }

  static SctpSackChunk parse(Uint8List data) {
    if (data.length < SctpConstants.sackChunkMinSize + 4) {
      throw FormatException('SACK chunk too short');
    }

    final buffer = ByteData.sublistView(data);
    final cumulativeTsnAck = buffer.getUint32(4);
    final advertisedRwnd = buffer.getUint32(8);
    final numGapAckBlocks = buffer.getUint16(12);
    final numDuplicateTsns = buffer.getUint16(14);

    var offset = 16;

    // Read gap ack blocks
    final gapAckBlocks = <GapAckBlock>[];
    for (var i = 0; i < numGapAckBlocks; i++) {
      final start = buffer.getUint16(offset);
      final end = buffer.getUint16(offset + 2);
      gapAckBlocks.add(GapAckBlock(start: start, end: end));
      offset += 4;
    }

    // Read duplicate TSNs
    final duplicateTsns = <int>[];
    for (var i = 0; i < numDuplicateTsns; i++) {
      duplicateTsns.add(buffer.getUint32(offset));
      offset += 4;
    }

    return SctpSackChunk(
      cumulativeTsnAck: cumulativeTsnAck,
      advertisedRwnd: advertisedRwnd,
      gapAckBlocks: gapAckBlocks,
      duplicateTsns: duplicateTsns,
    );
  }

  @override
  String toString() {
    return 'SACK(cumTsn=$cumulativeTsnAck, rwnd=$advertisedRwnd, gaps=${gapAckBlocks.length}, dups=${duplicateTsns.length})';
  }
}

/// Gap Ack Block for SACK
class GapAckBlock {
  final int start;
  final int end;

  const GapAckBlock({required this.start, required this.end});

  @override
  String toString() => 'Gap($start-$end)';
}

/// SCTP HEARTBEAT Chunk
/// RFC 4960 Section 3.3.5
class SctpHeartbeatChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.heartbeat;

  @override
  final int flags = 0;

  /// Heartbeat info (opaque to receiver)
  final Uint8List info;

  @override
  int get length => SctpConstants.chunkHeaderSize + info.length;

  SctpHeartbeatChunk({required this.info});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    result.setRange(4, 4 + info.length, info);

    return result;
  }

  static SctpHeartbeatChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final infoLength = length - SctpConstants.chunkHeaderSize;
    final info = data.sublist(4, 4 + infoLength);

    return SctpHeartbeatChunk(info: info);
  }

  @override
  String toString() => 'HEARTBEAT(${info.length} bytes)';
}

/// SCTP HEARTBEAT ACK Chunk
/// RFC 4960 Section 3.3.6
class SctpHeartbeatAckChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.heartbeatAck;

  @override
  final int flags = 0;

  /// Heartbeat info (echoed from HEARTBEAT)
  final Uint8List info;

  @override
  int get length => SctpConstants.chunkHeaderSize + info.length;

  SctpHeartbeatAckChunk({required this.info});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    result.setRange(4, 4 + info.length, info);

    return result;
  }

  static SctpHeartbeatAckChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final infoLength = length - SctpConstants.chunkHeaderSize;
    final info = data.sublist(4, 4 + infoLength);

    return SctpHeartbeatAckChunk(info: info);
  }

  @override
  String toString() => 'HEARTBEAT-ACK(${info.length} bytes)';
}

/// SCTP ABORT Chunk
/// RFC 4960 Section 3.3.7
class SctpAbortChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.abort;

  @override
  final int flags;

  /// Error causes
  final Uint8List? causes;

  @override
  int get length => SctpConstants.chunkHeaderSize + (causes?.length ?? 0);

  SctpAbortChunk({this.flags = 0, this.causes});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);

    if (causes != null) {
      result.setRange(4, 4 + causes!.length, causes!);
    }

    return result;
  }

  static SctpAbortChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final flags = buffer.getUint8(1);
    final length = buffer.getUint16(2);

    Uint8List? causes;
    if (length > SctpConstants.chunkHeaderSize) {
      final causeLength = length - SctpConstants.chunkHeaderSize;
      causes = data.sublist(4, 4 + causeLength);
    }

    return SctpAbortChunk(flags: flags, causes: causes);
  }

  @override
  String toString() => 'ABORT';
}

/// SCTP SHUTDOWN Chunk
/// RFC 4960 Section 3.3.8
class SctpShutdownChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.shutdown;

  @override
  final int flags = 0;

  /// Cumulative TSN Ack
  final int cumulativeTsnAck;

  @override
  int get length => 8; // 4-byte header + 4-byte TSN

  SctpShutdownChunk({required this.cumulativeTsnAck});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, cumulativeTsnAck);

    return result;
  }

  static SctpShutdownChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final cumulativeTsnAck = buffer.getUint32(4);

    return SctpShutdownChunk(cumulativeTsnAck: cumulativeTsnAck);
  }

  @override
  String toString() => 'SHUTDOWN(cumTsn=$cumulativeTsnAck)';
}

/// SCTP SHUTDOWN ACK Chunk
/// RFC 4960 Section 3.3.9
class SctpShutdownAckChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.shutdownAck;

  @override
  final int flags = 0;

  @override
  int get length => SctpConstants.chunkHeaderSize;

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);
    writeHeader(buffer, 0);
    return result;
  }

  static SctpShutdownAckChunk parse(Uint8List data) {
    return SctpShutdownAckChunk();
  }

  @override
  String toString() => 'SHUTDOWN-ACK';
}

/// SCTP ERROR Chunk
/// RFC 4960 Section 3.3.10
class SctpErrorChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.error;

  @override
  final int flags = 0;

  /// Error causes
  final Uint8List? causes;

  @override
  int get length => SctpConstants.chunkHeaderSize + (causes?.length ?? 0);

  SctpErrorChunk({this.causes});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);

    if (causes != null) {
      result.setRange(4, 4 + causes!.length, causes!);
    }

    return result;
  }

  static SctpErrorChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);

    Uint8List? causes;
    if (length > SctpConstants.chunkHeaderSize) {
      final causeLength = length - SctpConstants.chunkHeaderSize;
      causes = data.sublist(4, 4 + causeLength);
    }

    return SctpErrorChunk(causes: causes);
  }

  @override
  String toString() => 'ERROR';
}

/// SCTP COOKIE ECHO Chunk
/// RFC 4960 Section 3.3.11
class SctpCookieEchoChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.cookieEcho;

  @override
  final int flags = 0;

  /// State cookie
  final Uint8List cookie;

  @override
  int get length => SctpConstants.chunkHeaderSize + cookie.length;

  SctpCookieEchoChunk({required this.cookie});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    result.setRange(4, 4 + cookie.length, cookie);

    return result;
  }

  static SctpCookieEchoChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final cookieLength = length - SctpConstants.chunkHeaderSize;
    final cookie = data.sublist(4, 4 + cookieLength);

    return SctpCookieEchoChunk(cookie: cookie);
  }

  @override
  String toString() => 'COOKIE-ECHO(${cookie.length} bytes)';
}

/// SCTP COOKIE ACK Chunk
/// RFC 4960 Section 3.3.12
class SctpCookieAckChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.cookieAck;

  @override
  final int flags = 0;

  @override
  int get length => SctpConstants.chunkHeaderSize;

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);
    writeHeader(buffer, 0);
    return result;
  }

  static SctpCookieAckChunk parse(Uint8List data) {
    return SctpCookieAckChunk();
  }

  @override
  String toString() => 'COOKIE-ACK';
}

/// SCTP SHUTDOWN COMPLETE Chunk
/// RFC 4960 Section 3.3.13
class SctpShutdownCompleteChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.shutdownComplete;

  @override
  final int flags;

  @override
  int get length => SctpConstants.chunkHeaderSize;

  SctpShutdownCompleteChunk({this.flags = 0});

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);
    writeHeader(buffer, 0);
    return result;
  }

  static SctpShutdownCompleteChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final flags = buffer.getUint8(1);
    return SctpShutdownCompleteChunk(flags: flags);
  }

  @override
  String toString() => 'SHUTDOWN-COMPLETE';
}

/// SCTP FORWARD TSN Chunk
/// RFC 3758 Section 3.2
class SctpForwardTsnChunk extends SctpChunk {
  @override
  final SctpChunkType type = SctpChunkType.forwardTsn;

  @override
  final int flags = 0;

  /// New Cumulative TSN
  final int newCumulativeTsn;

  /// Stream identifiers
  final List<ForwardTsnStream> streams;

  @override
  int get length => 8 + (streams.length * 4);

  SctpForwardTsnChunk({
    required this.newCumulativeTsn,
    required this.streams,
  });

  @override
  Uint8List serialize() {
    final result = Uint8List(length);
    final buffer = ByteData.sublistView(result);

    writeHeader(buffer, 0);
    buffer.setUint32(4, newCumulativeTsn);

    var offset = 8;
    for (final stream in streams) {
      buffer.setUint16(offset, stream.streamId);
      buffer.setUint16(offset + 2, stream.streamSeq);
      offset += 4;
    }

    return result;
  }

  static SctpForwardTsnChunk parse(Uint8List data) {
    final buffer = ByteData.sublistView(data);
    final length = buffer.getUint16(2);
    final newCumulativeTsn = buffer.getUint32(4);

    final streams = <ForwardTsnStream>[];
    var offset = 8;

    while (offset < length) {
      final streamId = buffer.getUint16(offset);
      final streamSeq = buffer.getUint16(offset + 2);
      streams.add(ForwardTsnStream(streamId: streamId, streamSeq: streamSeq));
      offset += 4;
    }

    return SctpForwardTsnChunk(
      newCumulativeTsn: newCumulativeTsn,
      streams: streams,
    );
  }

  @override
  String toString() => 'FORWARD-TSN(tsn=$newCumulativeTsn, streams=${streams.length})';
}

/// Forward TSN Stream info
class ForwardTsnStream {
  final int streamId;
  final int streamSeq;

  const ForwardTsnStream({required this.streamId, required this.streamSeq});
}
