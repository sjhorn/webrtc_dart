import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/psfb/psfb.dart';
import 'package:webrtc_dart/src/rtcp/psfb/pli.dart';
import 'package:webrtc_dart/src/rtcp/psfb/fir.dart';
import 'package:webrtc_dart/src/rtcp/psfb/remb.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('PayloadFeedbackType', () {
    test('fromValue returns correct type', () {
      expect(
        PayloadFeedbackType.fromValue(PictureLossIndication.fmt),
        equals(PayloadFeedbackType.pli),
      );
      expect(
        PayloadFeedbackType.fromValue(FullIntraRequest.fmt),
        equals(PayloadFeedbackType.fir),
      );
      expect(
        PayloadFeedbackType.fromValue(ReceiverEstimatedMaxBitrate.fmt),
        equals(PayloadFeedbackType.remb),
      );
    });

    test('fromValue returns null for unknown type', () {
      expect(PayloadFeedbackType.fromValue(99), isNull);
    });
  });

  group('PayloadSpecificFeedback PLI', () {
    test('factory creates PLI feedback', () {
      final psfb = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );

      expect(psfb.type, equals(PayloadFeedbackType.pli));
      expect(psfb.fmt, equals(PictureLossIndication.fmt));
      expect(psfb.feedback, isA<PictureLossIndication>());

      final pli = psfb.feedback as PictureLossIndication;
      expect(pli.senderSsrc, equals(12345678));
      expect(pli.mediaSsrc, equals(87654321));
    });

    test('serialize creates valid bytes', () {
      final psfb = PayloadSpecificFeedback.pli(
        senderSsrc: 0x12345678,
        mediaSsrc: 0x87654321,
      );

      final bytes = psfb.serialize();

      // PLI has 8 bytes (sender SSRC + media SSRC)
      expect(bytes.length, equals(8));

      // Check sender SSRC
      expect(bytes[0], equals(0x12));
      expect(bytes[1], equals(0x34));
      expect(bytes[2], equals(0x56));
      expect(bytes[3], equals(0x78));

      // Check media SSRC
      expect(bytes[4], equals(0x87));
      expect(bytes[5], equals(0x65));
      expect(bytes[6], equals(0x43));
      expect(bytes[7], equals(0x21));
    });

    test('toRtcpPacket creates valid packet', () {
      final psfb = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );

      final packet = psfb.toRtcpPacket();

      expect(packet.packetType, equals(RtcpPacketType.payloadFeedback));
      expect(packet.reportCount, equals(PictureLossIndication.fmt));
      expect(packet.ssrc, equals(12345678));
    });
  });

  group('PayloadSpecificFeedback FIR', () {
    test('factory creates FIR feedback', () {
      final psfb = PayloadSpecificFeedback.fir(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
        entries: [FirEntry(ssrc: 0xAABBCCDD, sequenceNumber: 5)],
      );

      expect(psfb.type, equals(PayloadFeedbackType.fir));
      expect(psfb.fmt, equals(FullIntraRequest.fmt));
      expect(psfb.feedback, isA<FullIntraRequest>());

      final fir = psfb.feedback as FullIntraRequest;
      expect(fir.senderSsrc, equals(12345678));
      expect(fir.entries.length, equals(1));
      expect(fir.entries[0].ssrc, equals(0xAABBCCDD));
    });

    test('serialize creates valid bytes', () {
      final psfb = PayloadSpecificFeedback.fir(
        senderSsrc: 0x12345678,
        mediaSsrc: 0x87654321,
        entries: [FirEntry(ssrc: 0xAABBCCDD, sequenceNumber: 1)],
      );

      final bytes = psfb.serialize();

      // FIR: 8 bytes header (sender + media SSRC) + 8 bytes per entry
      expect(bytes.length, equals(16));
    });
  });

  group('PayloadSpecificFeedback REMB', () {
    test('factory creates REMB feedback', () {
      final psfb = PayloadSpecificFeedback.remb(
        senderSsrc: 12345678,
        mediaSsrc: 0,
        bitrate: BigInt.from(1000000),
        ssrcFeedbacks: [0x11111111, 0x22222222],
      );

      expect(psfb.type, equals(PayloadFeedbackType.remb));
      expect(psfb.fmt, equals(ReceiverEstimatedMaxBitrate.fmt));
      expect(psfb.feedback, isA<ReceiverEstimatedMaxBitrate>());

      final remb = psfb.feedback as ReceiverEstimatedMaxBitrate;
      expect(remb.senderSsrc, equals(12345678));
      expect(remb.ssrcFeedbacks.length, equals(2));
    });

    test('serialize creates valid bytes', () {
      final psfb = PayloadSpecificFeedback.remb(
        senderSsrc: 0x12345678,
        mediaSsrc: 0,
        bitrate: BigInt.from(1000000),
        ssrcFeedbacks: [0x11111111],
      );

      final bytes = psfb.serialize();

      // REMB: 4 (media SSRC) + 4 (REMB) + 4 (num/exp/mantissa) + 4 (SSRC)
      expect(bytes.length, greaterThan(12));
    });
  });

  group('PayloadSpecificFeedback deserialize', () {
    test('deserialize throws for non-payload-feedback packet', () {
      final packet = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport, // Wrong type
        length: 6,
        ssrc: 12345678,
        payload: Uint8List(0),
      );

      expect(
        () => PayloadSpecificFeedback.deserialize(packet),
        throwsA(isA<FormatException>()),
      );
    });

    test('deserialize throws for unknown FMT', () {
      final packet = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 99, // Unknown FMT
        packetType: RtcpPacketType.payloadFeedback,
        length: 2,
        ssrc: 12345678,
        payload: Uint8List.fromList([0, 0, 0, 0]),
      );

      expect(
        () => PayloadSpecificFeedback.deserialize(packet),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PayloadSpecificFeedback equality', () {
    test('equal PLI feedbacks are equal', () {
      final psfb1 = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );
      final psfb2 = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );

      expect(psfb1, equals(psfb2));
      expect(psfb1.hashCode, equals(psfb2.hashCode));
    });

    test('different PLI feedbacks are not equal', () {
      final psfb1 = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );
      final psfb2 = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 11111111,
      );

      expect(psfb1, isNot(equals(psfb2)));
    });

    test('toString returns readable format', () {
      final psfb = PayloadSpecificFeedback.pli(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );

      final str = psfb.toString();
      expect(str, contains('PayloadSpecificFeedback'));
    });
  });

  group('createPliPacket', () {
    test('creates compound packet with PLI', () {
      final compound = createPliPacket(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
      );

      expect(compound.packets.length, equals(1));
      expect(compound.packets[0].packetType,
          equals(RtcpPacketType.payloadFeedback));
      expect(
          compound.packets[0].reportCount, equals(PictureLossIndication.fmt));
    });
  });

  group('createFirPacket', () {
    test('creates compound packet with FIR', () {
      final compound = createFirPacket(
        senderSsrc: 12345678,
        mediaSsrc: 87654321,
        entries: [FirEntry(ssrc: 0xAABBCCDD, sequenceNumber: 1)],
      );

      expect(compound.packets.length, equals(1));
      expect(compound.packets[0].packetType,
          equals(RtcpPacketType.payloadFeedback));
      expect(compound.packets[0].reportCount, equals(FullIntraRequest.fmt));
    });
  });

  group('createRembPacket', () {
    test('creates compound packet with REMB', () {
      final compound = createRembPacket(
        senderSsrc: 12345678,
        bitrate: BigInt.from(2000000),
        ssrcFeedbacks: [0x11111111],
      );

      expect(compound.packets.length, equals(1));
      expect(compound.packets[0].packetType,
          equals(RtcpPacketType.payloadFeedback));
      expect(compound.packets[0].reportCount,
          equals(ReceiverEstimatedMaxBitrate.fmt));
    });
  });
}
