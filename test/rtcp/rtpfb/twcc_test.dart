import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/rtpfb/twcc.dart';

void main() {
  group('TWCC', () {
    group('RunLengthChunk', () {
      test('deserialize - not received', () {
        final res =
            RunLengthChunk.deSerialize(Uint8List.fromList([0x00, 0xdd]));
        expect(res.type, equals(PacketChunk.typeRunLength));
        expect(res.packetStatus, equals(PacketStatus.notReceived));
        expect(res.runLength, equals(221));
      });

      test('deserialize - received without delta', () {
        final res =
            RunLengthChunk.deSerialize(Uint8List.fromList([0x60, 0x18]));
        expect(res.type, equals(PacketChunk.typeRunLength));
        expect(res.packetStatus, equals(PacketStatus.receivedWithoutDelta));
        expect(res.runLength, equals(24));
      });

      test('serialize - not received', () {
        final chunk = RunLengthChunk(
          packetStatus: PacketStatus.notReceived,
          runLength: 221,
        );
        expect(chunk.serialize(), equals(Uint8List.fromList([0x00, 0xdd])));
      });

      test('serialize - received without delta', () {
        final chunk = RunLengthChunk(
          packetStatus: PacketStatus.receivedWithoutDelta,
          runLength: 24,
        );
        expect(chunk.serialize(), equals(Uint8List.fromList([0x60, 0x18])));
      });
    });

    group('StatusVectorChunk', () {
      test('deserialize - 1-bit symbols', () {
        final data = Uint8List.fromList([0x9f, 0x1c]);
        final res = StatusVectorChunk.deSerialize(data);
        expect(res.type, equals(PacketChunk.typeStatusVector));
        expect(res.symbolSize, equals(0));
        expect(
            res.symbolList,
            equals([
              PacketStatus.notReceived.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
            ]));
        expect(res.serialize(), equals(data));
      });

      test('deserialize - 2-bit symbols', () {
        final data = Uint8List.fromList([0xcd, 0x50]);
        final res = StatusVectorChunk.deSerialize(data);
        expect(res.type, equals(PacketChunk.typeStatusVector));
        expect(res.symbolSize, equals(1));
        expect(
            res.symbolList,
            equals([
              PacketStatus.notReceived.value,
              PacketStatus.receivedWithoutDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
            ]));
        expect(res.serialize(), equals(data));
      });
    });

    group('RecvDelta', () {
      test('deserialize - small delta', () {
        final data = Uint8List.fromList([0xff]);
        final res = RecvDelta.deSerialize(data);
        expect(res.type, equals(PacketStatus.receivedSmallDelta));
        expect(res.delta, equals(63750));
        expect(res.serialize(), equals(data));
      });

      test('deserialize - large positive delta', () {
        final data = Uint8List.fromList([0x7f, 0xff]);
        final res = RecvDelta.deSerialize(data);
        expect(res.type, equals(PacketStatus.receivedLargeDelta));
        expect(res.delta, equals(8191750));
        expect(res.serialize(), equals(data));
      });

      test('deserialize - large negative delta', () {
        final data = Uint8List.fromList([0x80, 0x00]);
        final res = RecvDelta.deSerialize(data);
        expect(res.type, equals(PacketStatus.receivedLargeDelta));
        expect(res.delta, equals(-8192000));
        expect(res.serialize(), equals(data));
      });
    });

    group('TransportWideCC', () {
      test('example1 - single packet with small delta', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x5,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x43,
          0x3,
          0x2f,
          0xa0,
          0x0,
          0x99,
          0x0,
          0x1,
          0x3d,
          0xe8,
          0x2,
          0x17,
          0x20,
          0x1,
          0x94,
          0x1,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.header.padding, isTrue);
        expect(twcc.header.count, equals(TransportWideCC.count));
        expect(twcc.header.type, equals(rtcpTransportLayerFeedbackType));
        expect(twcc.header.length, equals(5));

        expect(twcc.senderSsrc, equals(4195875351));
        expect(twcc.mediaSourceSsrc, equals(1124282272));
        expect(twcc.baseSequenceNumber, equals(153));
        expect(twcc.packetStatusCount, equals(1));
        expect(twcc.referenceTime, equals(4057090));
        expect(twcc.fbPktCount, equals(23));

        expect(twcc.packetChunks.length, equals(1));
        expect(twcc.packetChunks[0], isA<RunLengthChunk>());
        final chunk = twcc.packetChunks[0] as RunLengthChunk;
        expect(chunk.packetStatus, equals(PacketStatus.receivedSmallDelta));
        expect(chunk.runLength, equals(1));

        expect(twcc.recvDeltas.length, equals(1));
        expect(
            twcc.recvDeltas[0].type, equals(PacketStatus.receivedSmallDelta));
        expect(twcc.recvDeltas[0].delta, equals(37000));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });

      test('example2 - status vector chunks', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x6,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x19,
          0x3d,
          0xd8,
          0xbb,
          0x1,
          0x74,
          0x0,
          0xe,
          0x45,
          0xb1,
          0x5a,
          0x40,
          0xd8,
          0x0,
          0xf0,
          0xff,
          0xd0,
          0x0,
          0x0,
          0x1,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.senderSsrc, equals(4195875351));
        expect(twcc.mediaSourceSsrc, equals(423483579));
        expect(twcc.baseSequenceNumber, equals(372));
        expect(twcc.packetStatusCount, equals(14));
        expect(twcc.referenceTime, equals(4567386));
        expect(twcc.fbPktCount, equals(64));

        expect(twcc.packetChunks.length, equals(2));
        expect(twcc.packetChunks[0], isA<StatusVectorChunk>());
        expect(twcc.packetChunks[1], isA<StatusVectorChunk>());

        final chunk1 = twcc.packetChunks[0] as StatusVectorChunk;
        expect(chunk1.symbolSize, equals(1));
        expect(
            chunk1.symbolList,
            equals([
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedLargeDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
            ]));

        expect(twcc.recvDeltas.length, equals(2));
        expect(twcc.recvDeltas[0].delta, equals(52000));
        expect(twcc.recvDeltas[1].delta, equals(0));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });

      test('example3 - run length chunks with large deltas', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x7,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x19,
          0x3d,
          0xd8,
          0xbb,
          0x1,
          0x74,
          0x0,
          0x6,
          0x45,
          0xb1,
          0x5a,
          0x40,
          0x40,
          0x2,
          0x20,
          0x04,
          0x1f,
          0xfe,
          0x1f,
          0x9a,
          0xd0,
          0x0,
          0xd0,
          0x0,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.baseSequenceNumber, equals(372));
        expect(twcc.packetStatusCount, equals(6));

        expect(twcc.packetChunks.length, equals(2));
        final chunk1 = twcc.packetChunks[0] as RunLengthChunk;
        expect(chunk1.packetStatus, equals(PacketStatus.receivedLargeDelta));
        expect(chunk1.runLength, equals(2));

        final chunk2 = twcc.packetChunks[1] as RunLengthChunk;
        expect(chunk2.packetStatus, equals(PacketStatus.receivedSmallDelta));
        expect(chunk2.runLength, equals(4));

        expect(twcc.recvDeltas.length, equals(6));
        expect(twcc.recvDeltas[0].delta, equals(2047500));
        expect(twcc.recvDeltas[1].delta, equals(2022500));
        expect(twcc.recvDeltas[2].delta, equals(52000));
        expect(twcc.recvDeltas[3].delta, equals(0));
        expect(twcc.recvDeltas[4].delta, equals(52000));
        expect(twcc.recvDeltas[5].delta, equals(0));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });

      test('example4 - 7 packets with small deltas', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x7,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x19,
          0x3d,
          0xd8,
          0xbb,
          0x0,
          0x4,
          0x0,
          0x7,
          0x10,
          0x63,
          0x6e,
          0x1,
          0x20,
          0x7,
          0x4c,
          0x24,
          0x24,
          0x10,
          0xc,
          0xc,
          0x10,
          0x0,
          0x0,
          0x3,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.baseSequenceNumber, equals(4));
        expect(twcc.packetStatusCount, equals(7));
        expect(twcc.referenceTime, equals(1074030));
        expect(twcc.fbPktCount, equals(1));

        expect(twcc.packetChunks.length, equals(1));
        final chunk = twcc.packetChunks[0] as RunLengthChunk;
        expect(chunk.packetStatus, equals(PacketStatus.receivedSmallDelta));
        expect(chunk.runLength, equals(7));

        expect(twcc.recvDeltas.length, equals(7));
        expect(twcc.recvDeltas[0].delta, equals(19000));
        expect(twcc.recvDeltas[1].delta, equals(9000));
        expect(twcc.recvDeltas[2].delta, equals(9000));
        expect(twcc.recvDeltas[3].delta, equals(4000));
        expect(twcc.recvDeltas[4].delta, equals(3000));
        expect(twcc.recvDeltas[5].delta, equals(3000));
        expect(twcc.recvDeltas[6].delta, equals(4000));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });

      test('example5 - 1-bit status vector with packet loss', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x6,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x19,
          0x3d,
          0xd8,
          0xbb,
          0x0,
          0x1,
          0x0,
          0xe,
          0x10,
          0x63,
          0x6d,
          0x0,
          0xba,
          0x0,
          0x10,
          0xc,
          0xc,
          0x10,
          0x0,
          0x2,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.baseSequenceNumber, equals(1));
        expect(twcc.packetStatusCount, equals(14));
        expect(twcc.referenceTime, equals(1074029));
        expect(twcc.fbPktCount, equals(0));

        expect(twcc.packetChunks.length, equals(1));
        final chunk = twcc.packetChunks[0] as StatusVectorChunk;
        expect(chunk.symbolSize, equals(0));
        expect(
            chunk.symbolList,
            equals([
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
              PacketStatus.notReceived.value,
            ]));

        expect(twcc.recvDeltas.length, equals(4));
        expect(twcc.recvDeltas[0].delta, equals(4000));
        expect(twcc.recvDeltas[1].delta, equals(3000));
        expect(twcc.recvDeltas[2].delta, equals(3000));
        expect(twcc.recvDeltas[3].delta, equals(4000));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });

      test('example6 - mixed chunks with large delta', () {
        final data = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x7,
          0x9b,
          0x74,
          0xf6,
          0x1f,
          0x93,
          0x71,
          0xdc,
          0xbc,
          0x85,
          0x3c,
          0x0,
          0x9,
          0x63,
          0xf9,
          0x16,
          0xb3,
          0xd5,
          0x52,
          0x0,
          0x30,
          0x9b,
          0xaa,
          0x6a,
          0xaa,
          0x7b,
          0x1,
          0x9,
          0x1,
        ]);

        final header = RtcpHeader.deSerialize(data);
        final twcc = TransportWideCC.deSerialize(data.sublist(4), header);

        expect(twcc.senderSsrc, equals(2608133663));
        expect(twcc.mediaSourceSsrc, equals(2473712828));
        expect(twcc.baseSequenceNumber, equals(34108));
        expect(twcc.packetStatusCount, equals(9));
        expect(twcc.referenceTime, equals(6551830));
        expect(twcc.fbPktCount, equals(179));

        expect(twcc.packetChunks.length, equals(2));

        final chunk1 = twcc.packetChunks[0] as StatusVectorChunk;
        expect(chunk1.symbolSize, equals(1));
        expect(
            chunk1.symbolList,
            equals([
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.receivedSmallDelta.value,
              PacketStatus.notReceived.value,
              PacketStatus.receivedLargeDelta.value,
            ]));

        final chunk2 = twcc.packetChunks[1] as RunLengthChunk;
        expect(chunk2.packetStatus, equals(PacketStatus.notReceived));
        expect(chunk2.runLength, equals(48));

        expect(twcc.recvDeltas.length, equals(6));
        expect(twcc.recvDeltas[0].delta, equals(38750));
        expect(twcc.recvDeltas[1].delta, equals(42500));
        expect(twcc.recvDeltas[2].delta, equals(26500));
        expect(twcc.recvDeltas[3].delta, equals(42500));
        expect(twcc.recvDeltas[4].delta, equals(30750));
        expect(twcc.recvDeltas[5].delta, equals(66250));

        // Round-trip
        expect(twcc.serialize(), equals(data));
      });
    });

    group('TransportWideCC serialize', () {
      test('serialize example1', () {
        final twcc = TransportWideCC(
          header: RtcpHeader(
            padding: true,
            count: TransportWideCC.count,
            type: rtcpTransportLayerFeedbackType,
            length: 5,
          ),
          senderSsrc: 4195875351,
          mediaSourceSsrc: 1124282272,
          baseSequenceNumber: 153,
          packetStatusCount: 1,
          referenceTime: 4057090,
          fbPktCount: 23,
          packetChunks: [
            RunLengthChunk(
              packetStatus: PacketStatus.receivedSmallDelta,
              runLength: 1,
            ),
          ],
          recvDeltas: [
            RecvDelta(
              type: PacketStatus.receivedSmallDelta,
              delta: 37000,
            ),
          ],
        );

        final expected = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x5,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x43,
          0x3,
          0x2f,
          0xa0,
          0x0,
          0x99,
          0x0,
          0x1,
          0x3d,
          0xe8,
          0x2,
          0x17,
          0x20,
          0x1,
          0x94,
          0x1,
        ]);

        expect(twcc.serialize(), equals(expected));
      });

      test('serialize example2', () {
        final twcc = TransportWideCC(
          header: RtcpHeader(
            padding: true,
            count: TransportWideCC.count,
            type: rtcpTransportLayerFeedbackType,
            length: 6,
          ),
          senderSsrc: 4195875351,
          mediaSourceSsrc: 423483579,
          baseSequenceNumber: 372,
          packetStatusCount: 2,
          referenceTime: 4567386,
          fbPktCount: 64,
          packetChunks: [
            StatusVectorChunk(
              symbolSize: 1,
              symbolList: [
                PacketStatus.receivedSmallDelta.value,
                PacketStatus.receivedLargeDelta.value,
                PacketStatus.notReceived.value,
                PacketStatus.notReceived.value,
                PacketStatus.notReceived.value,
                PacketStatus.notReceived.value,
                PacketStatus.notReceived.value,
              ],
            ),
            StatusVectorChunk(
              symbolSize: 1,
              symbolList: [
                PacketStatus.receivedWithoutDelta.value,
                PacketStatus.notReceived.value,
                PacketStatus.notReceived.value,
                PacketStatus.receivedWithoutDelta.value,
                PacketStatus.receivedWithoutDelta.value,
                PacketStatus.receivedWithoutDelta.value,
                PacketStatus.receivedWithoutDelta.value,
              ],
            ),
          ],
          recvDeltas: [
            RecvDelta(
              type: PacketStatus.receivedSmallDelta,
              delta: 52000,
            ),
            RecvDelta(
              type: PacketStatus.receivedLargeDelta,
              delta: 0,
            ),
          ],
        );

        final expected = Uint8List.fromList([
          0xaf,
          0xcd,
          0x0,
          0x6,
          0xfa,
          0x17,
          0xfa,
          0x17,
          0x19,
          0x3d,
          0xd8,
          0xbb,
          0x1,
          0x74,
          0x0,
          0x2,
          0x45,
          0xb1,
          0x5a,
          0x40,
          0xd8,
          0x0,
          0xf0,
          0xff,
          0xd0,
          0x0,
          0x0,
          0x1,
        ]);

        expect(twcc.serialize(), equals(expected));
      });
    });
  });
}
