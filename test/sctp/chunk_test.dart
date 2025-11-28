import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';
import 'package:webrtc_dart/src/sctp/const.dart';

void main() {
  group('SctpDataChunk', () {
    test('serializes and parses DATA chunk', () {
      final userData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final chunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: userData,
      );

      final serialized = chunk.serialize();
      final parsed = SctpDataChunk.parse(serialized);

      expect(parsed.tsn, 100);
      expect(parsed.streamId, 1);
      expect(parsed.streamSeq, 10);
      expect(parsed.ppid, SctpPpid.webrtcBinary.value);
      expect(parsed.userData, equals(userData));
    });

    test('handles fragment flags', () {
      final chunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: Uint8List(10),
        flags: SctpDataChunkFlags.beginningFragment,
      );

      expect(chunk.beginningFragment, true);
      expect(chunk.endFragment, false);
      expect(chunk.unordered, false);
    });

    test('handles unordered flag', () {
      final chunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: Uint8List(10),
        flags: SctpDataChunkFlags.unordered | 0x03,
      );

      expect(chunk.unordered, true);
      expect(chunk.beginningFragment, true);
      expect(chunk.endFragment, true);
    });
  });

  group('SctpInitChunk', () {
    test('serializes and parses INIT chunk', () {
      final chunk = SctpInitChunk(
        initiateTag: 0x12345678,
        advertisedRwnd: 131072,
        outboundStreams: 10,
        inboundStreams: 10,
        initialTsn: 1000,
      );

      final serialized = chunk.serialize();
      final parsed = SctpInitChunk.parse(serialized);

      expect(parsed.initiateTag, 0x12345678);
      expect(parsed.advertisedRwnd, 131072);
      expect(parsed.outboundStreams, 10);
      expect(parsed.inboundStreams, 10);
      expect(parsed.initialTsn, 1000);
    });

    test('handles optional parameters', () {
      final params = Uint8List.fromList([1, 2, 3, 4]);
      final chunk = SctpInitChunk(
        initiateTag: 0x12345678,
        advertisedRwnd: 131072,
        outboundStreams: 10,
        inboundStreams: 10,
        initialTsn: 1000,
        parameters: params,
      );

      final serialized = chunk.serialize();
      final parsed = SctpInitChunk.parse(serialized);

      expect(parsed.parameters, equals(params));
    });
  });

  group('SctpSackChunk', () {
    test('serializes and parses SACK chunk', () {
      final chunk = SctpSackChunk(
        cumulativeTsnAck: 500,
        advertisedRwnd: 65536,
      );

      final serialized = chunk.serialize();
      final parsed = SctpSackChunk.parse(serialized);

      expect(parsed.cumulativeTsnAck, 500);
      expect(parsed.advertisedRwnd, 65536);
      expect(parsed.gapAckBlocks.length, 0);
      expect(parsed.duplicateTsns.length, 0);
    });

    test('handles gap ack blocks', () {
      final chunk = SctpSackChunk(
        cumulativeTsnAck: 500,
        advertisedRwnd: 65536,
        gapAckBlocks: [
          GapAckBlock(start: 2, end: 5),
          GapAckBlock(start: 10, end: 15),
        ],
      );

      final serialized = chunk.serialize();
      final parsed = SctpSackChunk.parse(serialized);

      expect(parsed.gapAckBlocks.length, 2);
      expect(parsed.gapAckBlocks[0].start, 2);
      expect(parsed.gapAckBlocks[0].end, 5);
      expect(parsed.gapAckBlocks[1].start, 10);
      expect(parsed.gapAckBlocks[1].end, 15);
    });

    test('handles duplicate TSNs', () {
      final chunk = SctpSackChunk(
        cumulativeTsnAck: 500,
        advertisedRwnd: 65536,
        duplicateTsns: [100, 150, 200],
      );

      final serialized = chunk.serialize();
      final parsed = SctpSackChunk.parse(serialized);

      expect(parsed.duplicateTsns, equals([100, 150, 200]));
    });
  });

  group('SctpShutdownChunk', () {
    test('serializes and parses SHUTDOWN chunk', () {
      final chunk = SctpShutdownChunk(cumulativeTsnAck: 1000);

      final serialized = chunk.serialize();
      final parsed = SctpShutdownChunk.parse(serialized);

      expect(parsed.cumulativeTsnAck, 1000);
    });
  });

  group('SctpCookieEchoChunk', () {
    test('serializes and parses COOKIE-ECHO chunk', () {
      final cookie = Uint8List.fromList(List.generate(32, (i) => i));
      final chunk = SctpCookieEchoChunk(cookie: cookie);

      final serialized = chunk.serialize();
      final parsed = SctpCookieEchoChunk.parse(serialized);

      expect(parsed.cookie, equals(cookie));
    });
  });

  group('SctpCookieAckChunk', () {
    test('serializes and parses COOKIE-ACK chunk', () {
      final chunk = SctpCookieAckChunk();

      final serialized = chunk.serialize();
      final parsed = SctpCookieAckChunk.parse(serialized);

      expect(parsed.type, SctpChunkType.cookieAck);
    });
  });

  group('SctpHeartbeatChunk', () {
    test('serializes and parses HEARTBEAT chunk', () {
      final info = Uint8List.fromList([1, 2, 3, 4, 5]);
      final chunk = SctpHeartbeatChunk(info: info);

      final serialized = chunk.serialize();
      final parsed = SctpHeartbeatChunk.parse(serialized);

      expect(parsed.info, equals(info));
    });
  });

  group('SctpHeartbeatAckChunk', () {
    test('serializes and parses HEARTBEAT-ACK chunk', () {
      final info = Uint8List.fromList([1, 2, 3, 4, 5]);
      final chunk = SctpHeartbeatAckChunk(info: info);

      final serialized = chunk.serialize();
      final parsed = SctpHeartbeatAckChunk.parse(serialized);

      expect(parsed.info, equals(info));
    });
  });

  group('SctpAbortChunk', () {
    test('serializes and parses ABORT chunk', () {
      final chunk = SctpAbortChunk();

      final serialized = chunk.serialize();
      final parsed = SctpAbortChunk.parse(serialized);

      expect(parsed.type, SctpChunkType.abort);
    });
  });

  group('SctpForwardTsnChunk', () {
    test('serializes and parses FORWARD-TSN chunk', () {
      final chunk = SctpForwardTsnChunk(
        newCumulativeTsn: 1000,
        streams: [
          ForwardTsnStream(streamId: 1, streamSeq: 10),
          ForwardTsnStream(streamId: 2, streamSeq: 20),
        ],
      );

      final serialized = chunk.serialize();
      final parsed = SctpForwardTsnChunk.parse(serialized);

      expect(parsed.newCumulativeTsn, 1000);
      expect(parsed.streams.length, 2);
      expect(parsed.streams[0].streamId, 1);
      expect(parsed.streams[0].streamSeq, 10);
      expect(parsed.streams[1].streamId, 2);
      expect(parsed.streams[1].streamSeq, 20);
    });
  });
}
