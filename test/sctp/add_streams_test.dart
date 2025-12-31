import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';
import 'package:webrtc_dart/src/sctp/const.dart';

void main() {
  group('SCTP Add Streams (RFC 6525)', () {
    group('StreamAddOutgoingParam', () {
      test('serializes correctly', () {
        final param = StreamAddOutgoingParam(
          requestSequence: 0x12345678,
          newStreams: 10,
        );

        final bytes = param.serialize();

        expect(bytes.length, equals(12));

        final buffer = ByteData.sublistView(bytes);
        // Parameter type
        expect(
            buffer.getUint16(0), equals(ReconfigParamType.addOutgoingStreams));
        // Parameter length
        expect(buffer.getUint16(2), equals(12));
        // Request sequence
        expect(buffer.getUint32(4), equals(0x12345678));
        // New streams
        expect(buffer.getUint16(8), equals(10));
        // Reserved
        expect(buffer.getUint16(10), equals(0));
      });

      test('parses correctly', () {
        // Create a valid StreamAddOutgoingParam packet
        final data = Uint8List(12);
        final buffer = ByteData.sublistView(data);
        buffer.setUint16(0, ReconfigParamType.addOutgoingStreams);
        buffer.setUint16(2, 12);
        buffer.setUint32(4, 0xAABBCCDD);
        buffer.setUint16(8, 5);
        buffer.setUint16(10, 0); // Reserved

        final param = StreamAddOutgoingParam.parse(data);

        expect(param.paramType, equals(ReconfigParamType.addOutgoingStreams));
        expect(param.requestSequence, equals(0xAABBCCDD));
        expect(param.newStreams, equals(5));
      });

      test('roundtrip serialize/parse', () {
        final original = StreamAddOutgoingParam(
          requestSequence: 999,
          newStreams: 42,
        );

        final bytes = original.serialize();
        final parsed = StreamAddOutgoingParam.parse(bytes);

        expect(parsed.requestSequence, equals(original.requestSequence));
        expect(parsed.newStreams, equals(original.newStreams));
      });

      test('toString returns readable format', () {
        final param = StreamAddOutgoingParam(
          requestSequence: 100,
          newStreams: 3,
        );

        final str = param.toString();
        expect(str, contains('StreamAddOutgoing'));
        expect(str, contains('100'));
        expect(str, contains('3'));
      });
    });

    group('SctpReconfigChunk with StreamAddOutgoing', () {
      test('parses chunk containing StreamAddOutgoingParam', () {
        // Build a RECONFIG chunk with StreamAddOutgoingParam
        final paramData = Uint8List(12);
        final paramBuffer = ByteData.sublistView(paramData);
        paramBuffer.setUint16(0, ReconfigParamType.addOutgoingStreams);
        paramBuffer.setUint16(2, 12);
        paramBuffer.setUint32(4, 0x11223344);
        paramBuffer.setUint16(8, 8);
        paramBuffer.setUint16(10, 0);

        // Chunk header (4 bytes) + param (12 bytes) = 16 bytes
        final chunkData = Uint8List(16);
        final chunkBuffer = ByteData.sublistView(chunkData);
        chunkBuffer.setUint8(0, SctpChunkType.reconfig.value); // Type
        chunkBuffer.setUint8(1, 0); // Flags
        chunkBuffer.setUint16(2, 16); // Length
        chunkData.setRange(4, 16, paramData);

        final chunk = SctpReconfigChunk.parse(chunkData);

        expect(chunk.params.length, equals(1));
        expect(chunk.params[0], isA<StreamAddOutgoingParam>());

        final param = chunk.params[0] as StreamAddOutgoingParam;
        expect(param.requestSequence, equals(0x11223344));
        expect(param.newStreams, equals(8));
      });

      test('serializes chunk containing StreamAddOutgoingParam', () {
        final param = StreamAddOutgoingParam(
          requestSequence: 12345,
          newStreams: 16,
        );

        final chunk = SctpReconfigChunk(params: [param]);
        final bytes = chunk.serialize();

        // Parse it back
        final parsed = SctpReconfigChunk.parse(bytes);
        expect(parsed.params.length, equals(1));
        expect(parsed.params[0], isA<StreamAddOutgoingParam>());

        final parsedParam = parsed.params[0] as StreamAddOutgoingParam;
        expect(parsedParam.requestSequence, equals(12345));
        expect(parsedParam.newStreams, equals(16));
      });

      test('handles mixed param types in single chunk', () {
        // Create a chunk with both OutgoingSsnResetRequest and StreamAddOutgoing
        final resetParam = OutgoingSsnResetRequestParam(
          requestSequence: 100,
          responseSequence: 50,
          lastTsn: 200,
          streams: [0, 1],
        );

        final addParam = StreamAddOutgoingParam(
          requestSequence: 101,
          newStreams: 4,
        );

        final chunk = SctpReconfigChunk(params: [resetParam, addParam]);
        final bytes = chunk.serialize();

        final parsed = SctpReconfigChunk.parse(bytes);
        expect(parsed.params.length, equals(2));
        expect(parsed.params[0], isA<OutgoingSsnResetRequestParam>());
        expect(parsed.params[1], isA<StreamAddOutgoingParam>());
      });
    });

    group('ReconfigParamType constants', () {
      test('addOutgoingStreams has correct value', () {
        expect(ReconfigParamType.addOutgoingStreams, equals(17));
      });

      test('addIncomingStreams has correct value', () {
        expect(ReconfigParamType.addIncomingStreams, equals(18));
      });
    });
  });
}
