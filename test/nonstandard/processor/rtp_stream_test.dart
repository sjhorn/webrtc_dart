import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/processor/rtp_stream.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RtpSourceStream', () {
    test('creates with default options', () {
      final source = RtpSourceStream();
      expect(source.isClosed, isFalse);
    });

    test('accepts RtpPacket directly', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      source.stream.listen(outputs.add);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1000,
        timestamp: 12345,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      source.push(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.rtp, isNotNull);
      expect(outputs.first.rtp!.sequenceNumber, equals(1000));
      expect(outputs.first.eol, isFalse);

      source.stop();
    });

    test('accepts raw bytes and parses to RtpPacket', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      source.stream.listen(outputs.add);

      // Create a valid RTP packet bytes
      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 2000,
        timestamp: 54321,
        ssrc: 0xABCDEF00,
        csrcs: [],
        payload: Uint8List.fromList([5, 6, 7, 8]),
      );
      final bytes = packet.serialize();

      source.push(bytes);
      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.rtp!.sequenceNumber, equals(2000));

      source.stop();
    });

    test('filters by payload type when specified', () async {
      final source = RtpSourceStream(
        options: RtpSourceStreamOptions(payloadType: 96),
      );
      final outputs = <RtpOutput>[];

      source.stream.listen(outputs.add);

      // Matching payload type
      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 100,
        ssrc: 1,
        csrcs: [],
        payload: Uint8List(10),
      ));

      // Non-matching payload type
      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 97,
        sequenceNumber: 2,
        timestamp: 200,
        ssrc: 1,
        csrcs: [],
        payload: Uint8List(10),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.rtp!.payloadType, equals(96));

      source.stop();
    });

    test('emits eol on stop', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      source.stream.listen(outputs.add);
      source.stop();

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.eol, isTrue);
      expect(source.isClosed, isTrue);
    });

    test('ignores push after stop', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      source.stream.listen(outputs.add);
      source.stop();

      // Try to push after stop
      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 100,
        ssrc: 1,
        csrcs: [],
        payload: Uint8List(10),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      // Only the eol should be in outputs
      expect(outputs.length, equals(1));
      expect(outputs.first.eol, isTrue);
    });

    test('throws on invalid input type', () {
      final source = RtpSourceStream();

      expect(
        () => source.push('invalid'),
        throwsA(isA<ArgumentError>()),
      );

      source.stop();
    });
  });

  group('RtpSinkStream', () {
    test('receives data from connected source', () async {
      final source = RtpSourceStream();
      final receivedData = <Uint8List>[];

      final sink = RtpSinkStream(
        onData: receivedData.add,
      );

      sink.connect(source);

      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List.fromList([1, 2, 3]),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData.length, equals(1));
      // Verify it's serialized RTP data
      final parsed = RtpPacket.parse(receivedData.first);
      expect(parsed.sequenceNumber, equals(100));

      source.stop();
      await sink.disconnect();
    });

    test('can disconnect from source', () async {
      final source = RtpSourceStream();
      final receivedData = <Uint8List>[];

      final sink = RtpSinkStream(
        onData: receivedData.add,
      );

      sink.connect(source);
      await sink.disconnect();

      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List(10),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData, isEmpty);

      source.stop();
    });
  });

  group('RtpTransformStream', () {
    test('transforms packets', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      // Transform: double the sequence number
      final transform = RtpTransformStream(
        input: source,
        transform: (rtp) => RtpPacket(
          version: rtp.version,
          padding: rtp.padding,
          extension: rtp.extension,
          marker: rtp.marker,
          payloadType: rtp.payloadType,
          sequenceNumber: rtp.sequenceNumber * 2,
          timestamp: rtp.timestamp,
          ssrc: rtp.ssrc,
          csrcs: rtp.csrcs,
          payload: rtp.payload,
        ),
      );

      transform.stream.listen(outputs.add);

      source.push(RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 50,
        timestamp: 1000,
        ssrc: 1,
        csrcs: [],
        payload: Uint8List(10),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.rtp!.sequenceNumber, equals(100)); // Doubled

      source.stop();
      await transform.stop();
    });

    test('can filter packets by returning null', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      // Filter: only pass packets with even sequence numbers
      final transform = RtpTransformStream(
        input: source,
        transform: (rtp) =>
            rtp.sequenceNumber % 2 == 0 ? rtp : null,
      );

      transform.stream.listen(outputs.add);

      for (var i = 1; i <= 5; i++) {
        source.push(RtpPacket(
          version: 2,
          padding: false,
          extension: false,
          marker: false,
          payloadType: 96,
          sequenceNumber: i,
          timestamp: i * 100,
          ssrc: 1,
          csrcs: [],
          payload: Uint8List(10),
        ));
      }

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(2)); // seq 2 and 4
      expect(outputs[0].rtp!.sequenceNumber, equals(2));
      expect(outputs[1].rtp!.sequenceNumber, equals(4));

      source.stop();
      await transform.stop();
    });

    test('propagates eol from source', () async {
      final source = RtpSourceStream();
      final outputs = <RtpOutput>[];

      final transform = RtpTransformStream(
        input: source,
        transform: (rtp) => rtp,
      );

      transform.stream.listen(outputs.add);
      source.stop();

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.eol, isTrue);

      await transform.stop();
    });
  });

  group('RtpOutput', () {
    test('defaults eol to false', () {
      final output = RtpOutput(rtp: null);
      expect(output.eol, isFalse);
    });

    test('can have both rtp and eol', () {
      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 100,
        ssrc: 1,
        csrcs: [],
        payload: Uint8List(10),
      );

      final output = RtpOutput(rtp: packet, eol: true);
      expect(output.rtp, isNotNull);
      expect(output.eol, isTrue);
    });
  });
}
