import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/audio/dtx.dart';

void main() {
  group('OpusTocByte', () {
    test('parses SILK narrowband config', () {
      // Config 0: SILK NB, 10ms
      final toc = OpusTocByte.parse(0x00); // 00000_0_00
      expect(toc.config, equals(0));
      expect(toc.stereo, equals(0));
      expect(toc.frameCountCode, equals(0));
      expect(toc.isSilk, isTrue);
      expect(toc.isCelt, isFalse);
      expect(toc.bandwidth, equals(OpusBandwidth.narrowband));
    });

    test('parses SILK wideband stereo config', () {
      // Config 10: SILK WB, stereo, 2 frames
      final toc = OpusTocByte.parse(0x57); // 01010_1_11
      expect(toc.config, equals(10));
      expect(toc.stereo, equals(1));
      expect(toc.frameCountCode, equals(3));
      expect(toc.isSilk, isTrue);
      expect(toc.bandwidth, equals(OpusBandwidth.wideband));
    });

    test('parses Hybrid config', () {
      // Config 12: Hybrid SWB
      final toc = OpusTocByte.parse(0x60); // 01100_0_00
      expect(toc.config, equals(12));
      expect(toc.isHybrid, isTrue);
      expect(toc.isSilk, isFalse);
      expect(toc.isCelt, isFalse);
      expect(toc.bandwidth, equals(OpusBandwidth.superwideband));
    });

    test('parses CELT fullband config', () {
      // Config 28: CELT FB
      final toc = OpusTocByte.parse(0xE0); // 11100_0_00
      expect(toc.config, equals(28));
      expect(toc.isCelt, isTrue);
      expect(toc.bandwidth, equals(OpusBandwidth.fullband));
    });

    test('parses various frame count codes', () {
      expect(OpusTocByte.parse(0x00).frameCountCode, equals(0)); // 1 frame
      expect(OpusTocByte.parse(0x01).frameCountCode, equals(1)); // 2 frames
      expect(OpusTocByte.parse(0x02).frameCountCode, equals(2)); // 2 frames CBR
      expect(OpusTocByte.parse(0x03).frameCountCode, equals(3)); // arbitrary
    });
  });

  group('OpusPacketAnalyzer', () {
    test('analyzePacket returns silence for empty packet', () {
      final result = OpusPacketAnalyzer.analyzePacket(Uint8List(0));
      expect(result, equals(OpusDtxPacketType.silence));
    });

    test('analyzePacket returns comfortNoise for 1-byte packet', () {
      final result =
          OpusPacketAnalyzer.analyzePacket(Uint8List.fromList([0xF8]));
      expect(result, equals(OpusDtxPacketType.comfortNoise));
    });

    test('analyzePacket returns comfortNoise for 2-byte packet', () {
      final result =
          OpusPacketAnalyzer.analyzePacket(Uint8List.fromList([0xF8, 0x00]));
      expect(result, equals(OpusDtxPacketType.comfortNoise));
    });

    test('analyzePacket returns comfortNoise for 3-byte packet', () {
      final result = OpusPacketAnalyzer.analyzePacket(
          Uint8List.fromList([0xF8, 0x00, 0x00]));
      expect(result, equals(OpusDtxPacketType.comfortNoise));
    });

    test('analyzePacket returns speech for normal-sized packet', () {
      final packet = Uint8List.fromList(List.filled(50, 0xAB));
      final result = OpusPacketAnalyzer.analyzePacket(packet);
      expect(result, equals(OpusDtxPacketType.speech));
    });

    test('isDtxPacket returns true for DTX packets', () {
      expect(OpusPacketAnalyzer.isDtxPacket(Uint8List(0)), isTrue);
      expect(
          OpusPacketAnalyzer.isDtxPacket(Uint8List.fromList([0xF8])), isTrue);
      expect(OpusPacketAnalyzer.isDtxPacket(Uint8List.fromList([0xF8, 0x00])),
          isTrue);
    });

    test('isDtxPacket returns false for speech packets', () {
      final packet = Uint8List.fromList(List.filled(50, 0xAB));
      expect(OpusPacketAnalyzer.isDtxPacket(packet), isFalse);
    });

    test('parseTocByte returns null for empty packet', () {
      expect(OpusPacketAnalyzer.parseTocByte(Uint8List(0)), isNull);
    });

    test('parseTocByte parses valid packet', () {
      final toc =
          OpusPacketAnalyzer.parseTocByte(Uint8List.fromList([0xE0, 0x00]));
      expect(toc, isNotNull);
      expect(toc!.config, equals(28));
    });
  });

  group('OpusDtxParameters', () {
    test('defaults are correct', () {
      const params = OpusDtxParameters();
      expect(params.useDtx, isFalse);
      expect(params.useInbandFec, isTrue);
      expect(params.stereo, isTrue);
      expect(params.cbr, isFalse);
      expect(params.ptime, equals(20));
    });

    test('fromSdpFmtp parses basic parameters', () {
      final params =
          OpusDtxParameters.fromSdpFmtp('minptime=10;useinbandfec=1');
      expect(params.minPtime, equals(10));
      expect(params.useInbandFec, isTrue);
      expect(params.useDtx, isFalse);
    });

    test('fromSdpFmtp parses DTX enabled', () {
      final params = OpusDtxParameters.fromSdpFmtp('usedtx=1;useinbandfec=1');
      expect(params.useDtx, isTrue);
      expect(params.useInbandFec, isTrue);
    });

    test('fromSdpFmtp parses all parameters', () {
      final params = OpusDtxParameters.fromSdpFmtp(
          'minptime=10;useinbandfec=1;usedtx=1;stereo=1;cbr=1;maxaveragebitrate=32000');
      expect(params.minPtime, equals(10));
      expect(params.useInbandFec, isTrue);
      expect(params.useDtx, isTrue);
      expect(params.stereo, isTrue);
      expect(params.cbr, isTrue);
      expect(params.maxAverageBitrate, equals(32000));
    });

    test('fromSdpFmtp handles case insensitivity', () {
      final params = OpusDtxParameters.fromSdpFmtp('USEDTX=1;UseInbandFec=1');
      expect(params.useDtx, isTrue);
      expect(params.useInbandFec, isTrue);
    });

    test('toSdpFmtp generates correct string with DTX', () {
      const params = OpusDtxParameters(
        useDtx: true,
        useInbandFec: true,
        minPtime: 10,
      );
      final fmtp = params.toSdpFmtp();
      expect(fmtp, contains('usedtx=1'));
      expect(fmtp, contains('useinbandfec=1'));
      expect(fmtp, contains('minptime=10'));
    });

    test('toSdpFmtp round-trips correctly', () {
      const original = OpusDtxParameters(
        useDtx: true,
        useInbandFec: true,
        stereo: true,
        minPtime: 10,
      );
      final fmtp = original.toSdpFmtp();
      final parsed = OpusDtxParameters.fromSdpFmtp(fmtp);
      expect(parsed.useDtx, equals(original.useDtx));
      expect(parsed.useInbandFec, equals(original.useInbandFec));
      expect(parsed.stereo, equals(original.stereo));
      expect(parsed.minPtime, equals(original.minPtime));
    });
  });

  group('DtxAudioFrame', () {
    test('creates speech frame', () {
      final frame = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01, 0x02, 0x03]),
        type: OpusDtxPacketType.speech,
      );
      expect(frame.isSpeech, isTrue);
      expect(frame.isSilence, isFalse);
      expect(frame.isComfortNoise, isFalse);
    });

    test('creates silence frame', () {
      final frame = DtxAudioFrame(
        timestamp: 1000,
        type: OpusDtxPacketType.silence,
      );
      expect(frame.isSilence, isTrue);
      expect(frame.isSpeech, isFalse);
    });

    test('creates comfort noise frame', () {
      final frame = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0xF8]),
        type: OpusDtxPacketType.comfortNoise,
      );
      expect(frame.isComfortNoise, isTrue);
      expect(frame.isSpeech, isFalse);
    });
  });

  group('DtxProcessor', () {
    late DtxProcessor processor;

    setUp(() {
      processor = DtxProcessor(ptime: 20, clockRate: 48000);
    });

    test('ptimeTimestampUnits is calculated correctly', () {
      // 20ms at 48000 Hz = 960 samples
      expect(processor.ptimeTimestampUnits, equals(960));
    });

    test('processFrame passes through first frame', () {
      final frame = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01, 0x02]),
        type: OpusDtxPacketType.speech,
      );
      final result = processor.processFrame(frame);
      expect(result.length, equals(1));
      expect(result[0].timestamp, equals(1000));
    });

    test('processFrame passes through consecutive frames', () {
      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 1960, // 1000 + 960
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);
      expect(result.length, equals(1));
      expect(result[0].timestamp, equals(1960));
      expect(processor.fillCount, equals(0));
    });

    test('processFrame fills gap with silence frames', () {
      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 3880, // 1000 + 3*960 = gap of 2 frames
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);

      // Should have 2 fill frames + 1 original
      expect(result.length, equals(3));
      expect(result[0].timestamp, equals(1960)); // First fill
      expect(result[0].type, equals(OpusDtxPacketType.silence));
      expect(result[1].timestamp, equals(2920)); // Second fill
      expect(result[1].type, equals(OpusDtxPacketType.silence));
      expect(result[2].timestamp, equals(3880)); // Original
      expect(processor.fillCount, equals(2));
    });

    test('processFrame respects enabled flag', () {
      processor.enabled = false;

      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 3880, // Gap
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);

      // Should not fill gap when disabled
      expect(result.length, equals(1));
      expect(result[0].timestamp, equals(3880));
      expect(processor.fillCount, equals(0));
    });

    test('processPacket creates correct frame type', () {
      // Small packet = comfort noise
      final result1 = processor.processPacket(1000, Uint8List.fromList([0xF8]));
      expect(result1[0].type, equals(OpusDtxPacketType.comfortNoise));

      // Large packet = speech
      final result2 = processor.processPacket(
          1960, Uint8List.fromList(List.filled(50, 0xAB)));
      expect(result2[0].type, equals(OpusDtxPacketType.speech));
    });

    test('reset clears state', () {
      final frame = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      processor.processFrame(frame);
      processor.reset();

      // After reset, next frame should be treated as first
      final frame2 = DtxAudioFrame(
        timestamp: 5000, // Big gap, but should not matter after reset
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );
      final result = processor.processFrame(frame2);
      expect(result.length, equals(1));
      expect(processor.fillCount, equals(0));
    });

    test('toJson returns correct statistics', () {
      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 2920, // Gap of 1 frame
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      processor.processFrame(frame2);

      final json = processor.toJson();
      expect(json['enabled'], isTrue);
      expect(json['fillCount'], equals(1));
      expect(json['clockRate'], equals(48000));
      expect(json['ptimeTimestampUnits'], equals(960));
    });

    test('handles timestamp wraparound', () {
      final frame1 = DtxAudioFrame(
        timestamp: 0xFFFFFFFF - 500, // Near max
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 0xFFFFFFFF - 500 + 960, // Wrapped around
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);

      // Should pass through without filling (consecutive timestamps)
      expect(result.length, equals(1));
      expect(processor.fillCount, equals(0));
    });

    test('does not fill for very large gaps (likely packet loss)', () {
      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      // Gap of 1000 frames - way too large, treat as discontinuity
      final frame2 = DtxAudioFrame(
        timestamp: 1000 + 960 * 200,
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);

      // Should not fill such a large gap
      expect(result.length, equals(1));
    });
  });

  group('DtxStateTracker', () {
    late DtxStateTracker tracker;

    setUp(() {
      tracker = DtxStateTracker();
    });

    test('starts not in DTX mode', () {
      expect(tracker.inDtxMode, isFalse);
      expect(tracker.dtxPeriodCount, equals(0));
    });

    test('enters DTX mode on silence frame', () {
      final silenceFrame = DtxAudioFrame(
        timestamp: 1000,
        type: OpusDtxPacketType.silence,
      );
      tracker.updateState(silenceFrame);

      expect(tracker.inDtxMode, isTrue);
      expect(tracker.dtxPeriodCount, equals(1));
    });

    test('exits DTX mode on speech frame', () {
      final silenceFrame = DtxAudioFrame(
        timestamp: 1000,
        type: OpusDtxPacketType.silence,
      );
      final speechFrame = DtxAudioFrame(
        timestamp: 2000,
        data: Uint8List.fromList([0x01, 0x02]),
        type: OpusDtxPacketType.speech,
      );

      tracker.updateState(silenceFrame);
      expect(tracker.inDtxMode, isTrue);

      tracker.updateState(speechFrame);
      expect(tracker.inDtxMode, isFalse);
    });

    test('tracks multiple DTX periods', () {
      final silence1 =
          DtxAudioFrame(timestamp: 1000, type: OpusDtxPacketType.silence);
      final speech1 = DtxAudioFrame(
        timestamp: 2000,
        data: Uint8List(10),
        type: OpusDtxPacketType.speech,
      );
      final silence2 =
          DtxAudioFrame(timestamp: 3000, type: OpusDtxPacketType.silence);
      final speech2 = DtxAudioFrame(
        timestamp: 4000,
        data: Uint8List(10),
        type: OpusDtxPacketType.speech,
      );

      tracker.updateState(silence1);
      tracker.updateState(speech1);
      tracker.updateState(silence2);
      tracker.updateState(speech2);

      expect(tracker.dtxPeriodCount, equals(2));
    });

    test('tracks DTX duration', () {
      final silence =
          DtxAudioFrame(timestamp: 1000, type: OpusDtxPacketType.silence);
      final speech = DtxAudioFrame(
        timestamp: 2000,
        data: Uint8List(10),
        type: OpusDtxPacketType.speech,
      );

      tracker.updateState(silence);
      tracker.updateState(speech);

      expect(tracker.totalDtxDuration, equals(1000)); // 2000 - 1000
    });

    test('reset clears all state', () {
      final silence =
          DtxAudioFrame(timestamp: 1000, type: OpusDtxPacketType.silence);
      tracker.updateState(silence);

      tracker.reset();

      expect(tracker.inDtxMode, isFalse);
      expect(tracker.dtxPeriodCount, equals(0));
      expect(tracker.totalDtxDuration, equals(0));
    });

    test('toJson returns correct state', () {
      final silence =
          DtxAudioFrame(timestamp: 1000, type: OpusDtxPacketType.silence);
      tracker.updateState(silence);

      final json = tracker.toJson();
      expect(json['inDtxMode'], isTrue);
      expect(json['dtxPeriodCount'], equals(1));
      expect(json['totalDtxDuration'], equals(0)); // Not exited yet
    });
  });

  group('DtxProcessor silence packet', () {
    test('creates valid Opus silence frame', () {
      final silence = DtxProcessor.createOpusSilenceFrame();
      expect(silence.length, equals(1));
      expect(silence[0], equals(0xF8)); // CELT config
    });

    test('custom silence packet is used', () {
      final customSilence = Uint8List.fromList([0x00, 0x01, 0x02]);
      final processor = DtxProcessor(silencePacket: customSilence);

      final frame1 = DtxAudioFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01]),
        type: OpusDtxPacketType.speech,
      );
      final frame2 = DtxAudioFrame(
        timestamp: 2920, // Gap
        data: Uint8List.fromList([0x02]),
        type: OpusDtxPacketType.speech,
      );

      processor.processFrame(frame1);
      final result = processor.processFrame(frame2);

      expect(result[0].data, equals(customSilence));
    });
  });

  group('OpusBandwidth', () {
    test('all values are defined', () {
      expect(OpusBandwidth.values.length, equals(5));
      expect(OpusBandwidth.values, contains(OpusBandwidth.narrowband));
      expect(OpusBandwidth.values, contains(OpusBandwidth.mediumband));
      expect(OpusBandwidth.values, contains(OpusBandwidth.wideband));
      expect(OpusBandwidth.values, contains(OpusBandwidth.superwideband));
      expect(OpusBandwidth.values, contains(OpusBandwidth.fullband));
    });
  });
}
