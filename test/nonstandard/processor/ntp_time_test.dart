import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/processor/ntp_time.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

RtpPacket _createRtpPacket({
  required int sequenceNumber,
  required int timestamp,
}) {
  return RtpPacket(
    version: 2,
    padding: false,
    extension: false,
    marker: false,
    payloadType: 96,
    sequenceNumber: sequenceNumber,
    timestamp: timestamp,
    ssrc: 0x12345678,
    csrcs: [],
    payload: Uint8List(100),
  );
}

RtcpPacket _createSrPacket({
  required int ntpHigh,
  required int ntpLow,
  required int rtpTimestamp,
}) {
  // SR payload: NTP (8 bytes) + RTP timestamp (4 bytes) + sender info (12 bytes)
  final payload = Uint8List(20);
  final buffer = ByteData.sublistView(payload);
  buffer.setUint32(0, ntpHigh);
  buffer.setUint32(4, ntpLow);
  buffer.setUint32(8, rtpTimestamp);
  // Rest is sender info (packet count, octet count) - set to 0

  return RtcpPacket(
    reportCount: 0,
    packetType: RtcpPacketType.senderReport,
    length: 6, // (28 bytes - 4) / 4 - 1 = 6
    ssrc: 0x12345678,
    payload: payload,
  );
}

void main() {
  group('NtpTimeProcessor', () {
    test('creates with clock rate', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      expect(processor.clockRate, equals(90000));
      expect(processor.started, isFalse);
    });

    test('has unique ID', () {
      final p1 = NtpTimeProcessor(clockRate: 90000);
      final p2 = NtpTimeProcessor(clockRate: 90000);

      expect(p1.id, isNotEmpty);
      expect(p1.id.length, equals(36));
      expect(p1.id, isNot(equals(p2.id)));
    });

    test('buffers RTP until SR received', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      final results = processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 100, timestamp: 0),
      ));

      // Should buffer, not output
      expect(results, isEmpty);
      expect(processor.started, isFalse);
    });

    test('starts after receiving SR', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      processor.processInput(NtpTimeInput(
        rtcp: _createSrPacket(
          ntpHigh: 3000000000,
          ntpLow: 0,
          rtpTimestamp: 0,
        ),
      ));

      expect(processor.started, isTrue);
    });

    test('outputs RTP with time after SR', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      // First, send SR to establish mapping
      processor.processInput(NtpTimeInput(
        rtcp: _createSrPacket(
          ntpHigh: 3000000000, // ~95 years since 1900
          ntpLow: 0,
          rtpTimestamp: 0,
        ),
      ));

      // Now send RTP
      final results = processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(
            sequenceNumber: 100, timestamp: 9000), // 100ms at 90kHz
      ));

      expect(results.length, equals(1));
      expect(results.first.rtp, isNotNull);
      expect(results.first.timeMs, isNotNull);
    });

    test('flushes buffered RTP when SR arrives', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      // Buffer some RTP packets
      processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 100, timestamp: 0),
      ));
      processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 101, timestamp: 3000),
      ));

      // Now send SR
      processor.processInput(NtpTimeInput(
        rtcp: _createSrPacket(
          ntpHigh: 3000000000,
          ntpLow: 0,
          rtpTimestamp: 0,
        ),
      ));

      // Send another RTP to trigger buffer flush
      final results = processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 102, timestamp: 6000),
      ));

      // All 3 packets should be output (2 buffered + 1 new)
      expect(results.length, equals(3));
    });

    test('handles eol signal', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      final results = processor.processInput(NtpTimeInput(eol: true));

      expect(results.length, equals(1));
      expect(results.first.eol, isTrue);
    });

    test('clears state on eol', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      // Setup
      processor.processInput(NtpTimeInput(
        rtcp: _createSrPacket(ntpHigh: 3000000000, ntpLow: 0, rtpTimestamp: 0),
      ));
      processor.processInput(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 100, timestamp: 0),
      ));

      // EOL
      processor.processInput(NtpTimeInput(eol: true));

      // After eol, buffer should be cleared (but started flag remains)
      final json = processor.toJson();
      expect(json['bufferLength'], equals(0));
    });

    test('toJson includes state', () {
      final processor = NtpTimeProcessor(clockRate: 90000);

      processor.processInput(NtpTimeInput(
        rtcp: _createSrPacket(
          ntpHigh: 3000000000,
          ntpLow: 0,
          rtpTimestamp: 12345,
        ),
      ));

      final json = processor.toJson();

      expect(json['id'], equals(processor.id));
      expect(json['clockRate'], equals(90000));
      expect(json['baseRtpTimestamp'], equals(12345));
      expect(json.containsKey('baseNtpTimestamp'), isTrue);
    });

    test('callback pattern works', () {
      final processor = NtpTimeProcessor(clockRate: 90000);
      final received = <NtpTimeOutput>[];

      processor.pipe(received.add);

      // Setup
      processor.input(NtpTimeInput(
        rtcp: _createSrPacket(ntpHigh: 3000000000, ntpLow: 0, rtpTimestamp: 0),
      ));

      // Send RTP
      processor.input(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 100, timestamp: 9000),
      ));

      expect(received.length, equals(1));
      expect(received.first.timeMs, isNotNull);
    });

    test('time calculation increases with RTP timestamp', () {
      final processor = NtpTimeProcessor(clockRate: 90000);
      final times = <int?>[];

      processor.pipe((output) => times.add(output.timeMs));

      // Setup
      processor.input(NtpTimeInput(
        rtcp: _createSrPacket(ntpHigh: 3000000000, ntpLow: 0, rtpTimestamp: 0),
      ));

      // Send multiple RTP packets
      processor.input(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 100, timestamp: 0),
      ));
      processor.input(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 101, timestamp: 9000), // +100ms
      ));
      processor.input(NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 102, timestamp: 18000), // +200ms
      ));

      expect(times.length, equals(3));
      // Times should be increasing
      expect(times[1]! > times[0]!, isTrue);
      expect(times[2]! > times[1]!, isTrue);
    });
  });

  group('NtpTimeInput', () {
    test('defaults eol to false', () {
      final input = NtpTimeInput();
      expect(input.eol, isFalse);
    });

    test('accepts rtp only', () {
      final input = NtpTimeInput(
        rtp: _createRtpPacket(sequenceNumber: 1, timestamp: 0),
      );
      expect(input.rtp, isNotNull);
      expect(input.rtcp, isNull);
    });

    test('accepts rtcp only', () {
      final input = NtpTimeInput(
        rtcp: _createSrPacket(ntpHigh: 0, ntpLow: 0, rtpTimestamp: 0),
      );
      expect(input.rtcp, isNotNull);
      expect(input.rtp, isNull);
    });
  });

  group('NtpTimeOutput', () {
    test('defaults eol to false', () {
      final output = NtpTimeOutput();
      expect(output.eol, isFalse);
    });

    test('stores rtp and time', () {
      final rtp = _createRtpPacket(sequenceNumber: 100, timestamp: 0);
      final output = NtpTimeOutput(rtp: rtp, timeMs: 12345);

      expect(output.rtp, equals(rtp));
      expect(output.timeMs, equals(12345));
    });
  });
}
