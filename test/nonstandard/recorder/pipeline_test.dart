import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/pipeline.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('NtpTimeProcessor', () {
    test('creates with clock rate', () {
      final processor = NtpTimeProcessor(90000);
      expect(processor.clockRate, equals(90000));
    });

    test('tracks statistics', () {
      final processor = NtpTimeProcessor(90000);

      final rtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 90000,
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );

      processor.processRtp(rtp);

      final stats = processor.toJson();
      expect(stats['clockRate'], equals(90000));
      expect(stats.containsKey('bufferLength'), isTrue);
    });

    test('processes RTCP SR', () {
      final processor = NtpTimeProcessor(90000);

      final sr = RtcpSenderReport(
        ssrc: 12345,
        ntpTimestamp: 0x0123456789ABCDEF,
        rtpTimestamp: 90000,
        packetCount: 100,
        octetCount: 5000,
      );

      // Should not throw
      processor.processRtcp(sr);

      // Processing RTCP should enable started state
      expect(processor.started, isTrue);
    });
  });

  group('RtpTimeProcessor', () {
    test('converts RTP timestamp to milliseconds', () {
      final processor = RtpTimeProcessor(90000);

      // First packet establishes base timestamp (returns 0)
      final rtp1 = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );
      processor.processRtp(rtp1); // base = 0

      // Second packet shows elapsed time
      final rtp2 = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 2,
        timestamp: 90000, // 1 second at 90kHz
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );

      final timeMs = processor.processRtp(rtp2);
      expect(timeMs, equals(1000)); // 90000 / 90 = 1000ms
    });

    test('handles audio clock rate', () {
      final processor = RtpTimeProcessor(48000);

      // First packet establishes base
      final rtp1 = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );
      processor.processRtp(rtp1); // base = 0

      // Second packet should show elapsed time
      final rtp2 = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 2,
        timestamp: 48000, // 1 second at 48kHz
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );

      final timeMs = processor.processRtp(rtp2);
      expect(timeMs, equals(1000)); // 48000 / 48 = 1000ms
    });

    test('reset clears base timestamp', () {
      final processor = RtpTimeProcessor(90000);

      final rtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 90000,
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );

      processor.processRtp(rtp);
      processor.reset();

      // After reset, should use new timestamp as base
      final rtp2 = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96,
        sequenceNumber: 2,
        timestamp: 180000, // Would be 2000ms normally, but 0 after reset
        ssrc: 12345,
        payload: Uint8List.fromList([0x01]),
      );

      final timeMs = processor.processRtp(rtp2);
      expect(timeMs, equals(0)); // Reset to 0
    });
  });

  group('Depacketizer', () {
    test('creates with codec', () {
      final depacketizer = Depacketizer(DepacketizerCodec.opus);
      expect(depacketizer.codec, equals(DepacketizerCodec.opus));
    });

    test('passes Opus packets through', () {
      final depacketizer = Depacketizer(DepacketizerCodec.opus);

      final rtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 111,
        sequenceNumber: 1,
        timestamp: 960,
        ssrc: 12345,
        payload: Uint8List.fromList([0x78, 0x00, 0x01, 0x02]),
      );

      final frames = depacketizer.processInput(rtp: rtp, timeMs: 20);

      expect(frames.length, equals(1));
      expect(frames[0].data, equals(rtp.payload));
      expect(frames[0].timeMs, equals(20));
    });

    test('tracks frame count', () {
      final depacketizer = Depacketizer(DepacketizerCodec.opus);

      for (var i = 0; i < 5; i++) {
        final rtp = RtpPacket(
          version: 2,
          padding: false,
          extension: false,
          marker: true,
          payloadType: 111,
          sequenceNumber: i,
          timestamp: i * 960,
          ssrc: 12345,
          payload: Uint8List.fromList([0x78, 0x00, i]),
        );
        depacketizer.processInput(rtp: rtp, timeMs: i * 20);
      }

      final stats = depacketizer.toJson();
      expect(stats['frameCount'], equals(5));
    });

    test('reset clears state', () {
      final depacketizer = Depacketizer(
        DepacketizerCodec.vp8,
        waitForKeyframe: true,
      );

      depacketizer.reset();
      // Should not throw
    });
  });

  group('TrackPipeline', () {
    test('creates with parameters', () {
      final pipeline = TrackPipeline(
        trackNumber: 1,
        codec: DepacketizerCodec.opus,
        clockRate: 48000,
        isVideo: false,
        disableNtp: true,
      );

      expect(pipeline.trackNumber, equals(1));
      expect(pipeline.isVideo, isFalse);
    });

    test('processes RTP and emits frames', () {
      final pipeline = TrackPipeline(
        trackNumber: 1,
        codec: DepacketizerCodec.opus,
        clockRate: 48000,
        isVideo: false,
        disableNtp: true,
      );

      final outputFrames = <CodecFrame>[];
      pipeline.onFrame = (frame) => outputFrames.add(frame);

      final rtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 111,
        sequenceNumber: 1,
        timestamp: 960,
        ssrc: 12345,
        payload: Uint8List.fromList([0x78, 0x00, 0x01]),
      );

      pipeline.processRtp(rtp);

      expect(outputFrames.length, equals(1));
    });

    test('handles RTCP sender reports', () {
      final pipeline = TrackPipeline(
        trackNumber: 1,
        codec: DepacketizerCodec.opus,
        clockRate: 48000,
        isVideo: false,
        disableNtp: false,
      );

      final sr = RtcpSenderReport(
        ssrc: 12345,
        ntpTimestamp: 0x0123456789ABCDEF,
        rtpTimestamp: 48000,
        packetCount: 100,
        octetCount: 5000,
      );

      // Should not throw
      pipeline.processRtcp(sr);

      final stats = pipeline.toJson();
      // NTP processor should have been updated
      expect(stats['ntpTime'], isNotNull);
      expect(stats['ntpTime']['started'], isTrue);
    });

    test('provides statistics', () {
      final pipeline = TrackPipeline(
        trackNumber: 1,
        codec: DepacketizerCodec.opus,
        clockRate: 48000,
        isVideo: false,
        disableNtp: false,
      );

      final stats = pipeline.toJson();

      expect(stats['trackNumber'], equals(1));
      expect(stats['clockRate'], equals(48000));
      expect(stats['isVideo'], isFalse);
      // With disableNtp: false, ntpTime should be present
      expect(stats.containsKey('ntpTime'), isTrue);
      expect(stats.containsKey('depacketizer'), isTrue);
    });
  });

  group('CodecFrame', () {
    test('creates with properties', () {
      final frame = CodecFrame(
        data: Uint8List.fromList([0x01, 0x02, 0x03]),
        isKeyframe: true,
        timeMs: 1000,
        rtpTimestamp: 90000,
      );

      expect(frame.data.length, equals(3));
      expect(frame.isKeyframe, isTrue);
      expect(frame.timeMs, equals(1000));
      expect(frame.rtpTimestamp, equals(90000));
    });
  });

  group('DepacketizerCodec', () {
    test('includes all supported codecs', () {
      expect(DepacketizerCodec.values, containsAll([
        DepacketizerCodec.vp8,
        DepacketizerCodec.vp9,
        DepacketizerCodec.h264,
        DepacketizerCodec.av1,
        DepacketizerCodec.opus,
      ]));
    });
  });
}
