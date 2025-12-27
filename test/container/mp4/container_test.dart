import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/mp4/container.dart';

void main() {
  group('Mp4Container', () {
    test('creates with video only', () {
      final container = Mp4Container(hasAudio: false, hasVideo: true);

      expect(container.hasVideo, isTrue);
      expect(container.hasAudio, isFalse);
      expect(container.videoTrack, isNull);
      expect(container.audioTrack, isNull);
      expect(container.tracksReady, isFalse);
    });

    test('creates with audio only', () {
      final container = Mp4Container(hasAudio: true, hasVideo: false);

      expect(container.hasAudio, isTrue);
      expect(container.hasVideo, isFalse);
    });

    test('creates with both tracks', () {
      final container = Mp4Container(hasAudio: true, hasVideo: true);

      expect(container.hasAudio, isTrue);
      expect(container.hasVideo, isTrue);
    });

    test('initVideoTrack assigns track ID', () {
      final container = Mp4Container(hasAudio: false, hasVideo: true);

      container.initVideoTrack(VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 1920,
        codedHeight: 1080,
        description: Uint8List.fromList([
          0x01,
          0x42,
          0xE0,
          0x1E,
          0xFF,
          0xE1,
          0x00,
          0x10,
          0x67,
          0x42,
          0xE0,
          0x1E,
          0xDA,
          0x01,
          0x40,
          0x16,
          0xEC,
          0x04,
          0x40,
          0x00,
          0x00,
          0x03,
          0x00,
          0x40,
          0x01,
          0x00,
          0x04,
          0x68,
          0xCE,
          0x3C,
          0x80,
        ]),
      ));

      expect(container.videoTrack, equals(1));
      expect(container.tracksReady, isTrue);
    });

    test('initAudioTrack assigns track ID', () {
      final container = Mp4Container(hasAudio: true, hasVideo: false);

      container.initAudioTrack(AudioDecoderConfig(
        codec: 'opus',
        numberOfChannels: 2,
        sampleRate: 48000,
      ));

      expect(container.audioTrack, equals(1));
      expect(container.tracksReady, isTrue);
    });

    test('tracksReady false until all expected tracks initialized', () {
      final container = Mp4Container(hasAudio: true, hasVideo: true);

      expect(container.tracksReady, isFalse);

      container.initVideoTrack(VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 1920,
        codedHeight: 1080,
      ));

      expect(container.tracksReady, isFalse); // Still waiting for audio

      container.initAudioTrack(AudioDecoderConfig(
        codec: 'opus',
        numberOfChannels: 2,
        sampleRate: 48000,
      ));

      expect(container.tracksReady, isTrue);
    });

    test('emits init segment when all tracks ready', () async {
      final container = Mp4Container(hasAudio: false, hasVideo: true);
      final outputs = <Mp4Data>[];

      container.onData.listen(outputs.add);

      container.initVideoTrack(VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 640,
        codedHeight: 480,
        description: Uint8List.fromList([
          0x01,
          0x42,
          0xE0,
          0x1E,
          0xFF,
          0xE1,
          0x00,
          0x04,
          0x67,
          0x42,
          0xE0,
          0x1E,
          0x01,
          0x00,
          0x04,
          0x68,
          0xCE,
          0x3C,
          0x80,
        ]),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      expect(outputs.length, equals(1));
      expect(outputs.first.type, equals(Mp4DataType.init));
      expect(outputs.first.kind, equals('video'));
    });

    test('addVideoChunk emits data after tracks ready', () async {
      final container = Mp4Container(hasAudio: false, hasVideo: true);
      final outputs = <Mp4Data>[];

      container.onData.listen(outputs.add);

      container.initVideoTrack(VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 640,
        codedHeight: 480,
        description: Uint8List.fromList([
          0x01,
          0x42,
          0xE0,
          0x1E,
          0xFF,
          0xE1,
          0x00,
          0x04,
          0x67,
          0x42,
          0xE0,
          0x1E,
          0x01,
          0x00,
          0x04,
          0x68,
          0xCE,
          0x3C,
          0x80,
        ]),
      ));

      // Add key frame
      container.addVideoChunk(EncodedChunk(
        byteLength: 100,
        duration: 33333, // ~30fps
        timestamp: 0,
        type: 'key',
        data: Uint8List.fromList([0, 0, 0, 5, 0x65, 1, 2, 3, 4]),
      ));

      // Add second frame to flush first
      container.addVideoChunk(EncodedChunk(
        byteLength: 50,
        duration: 33333,
        timestamp: 33333,
        type: 'delta',
        data: Uint8List.fromList([0, 0, 0, 4, 0x41, 5, 6, 7]),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      // Should have init + key frame
      expect(outputs.length, greaterThanOrEqualTo(2));
      expect(outputs[0].type, equals(Mp4DataType.init));
      expect(outputs[1].type, equals(Mp4DataType.key));
    });

    test('buffers frames before tracks ready', () async {
      final container = Mp4Container(hasAudio: false, hasVideo: true);
      final outputs = <Mp4Data>[];

      container.onData.listen(outputs.add);

      // Add frames before initializing track
      container.addVideoChunk(EncodedChunk(
        byteLength: 100,
        duration: 33333,
        timestamp: 0,
        type: 'key',
        data: Uint8List(100),
      ));

      await Future.delayed(Duration(milliseconds: 10));

      // No output yet
      expect(outputs, isEmpty);

      // Now initialize track
      container.initVideoTrack(VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 640,
        codedHeight: 480,
      ));

      await Future.delayed(Duration(milliseconds: 10));

      // Should have init segment now
      expect(outputs.length, equals(1));
      expect(outputs.first.type, equals(Mp4DataType.init));
    });
  });

  group('Mp4DataType', () {
    test('has expected values', () {
      expect(Mp4DataType.values.length, equals(3));
      expect(Mp4DataType.init, isNotNull);
      expect(Mp4DataType.delta, isNotNull);
      expect(Mp4DataType.key, isNotNull);
    });
  });

  group('Mp4Codec', () {
    test('has expected values', () {
      expect(Mp4Codec.values.length, equals(3));
      expect(Mp4Codec.avc1, isNotNull);
      expect(Mp4Codec.opus, isNotNull);
      expect(Mp4Codec.hev1, isNotNull);
    });
  });

  group('Mp4Data', () {
    test('stores properties correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      final mp4Data = Mp4Data(
        type: Mp4DataType.key,
        timestamp: 12345,
        duration: 33333,
        data: data,
        kind: 'video',
      );

      expect(mp4Data.type, equals(Mp4DataType.key));
      expect(mp4Data.timestamp, equals(12345));
      expect(mp4Data.duration, equals(33333));
      expect(mp4Data.data, equals(data));
      expect(mp4Data.kind, equals('video'));
    });
  });

  group('AudioDecoderConfig', () {
    test('stores properties correctly', () {
      final config = AudioDecoderConfig(
        codec: 'opus',
        numberOfChannels: 2,
        sampleRate: 48000,
        description: Uint8List.fromList([1, 2, 3]),
      );

      expect(config.codec, equals('opus'));
      expect(config.numberOfChannels, equals(2));
      expect(config.sampleRate, equals(48000));
      expect(config.description, equals([1, 2, 3]));
    });

    test('description is optional', () {
      final config = AudioDecoderConfig(
        codec: 'opus',
        numberOfChannels: 1,
        sampleRate: 44100,
      );

      expect(config.description, isNull);
    });
  });

  group('VideoDecoderConfig', () {
    test('stores properties correctly', () {
      final config = VideoDecoderConfig(
        codec: 'avc1.42E01E',
        codedWidth: 1920,
        codedHeight: 1080,
        description: Uint8List.fromList([0x01, 0x42, 0xE0]),
        displayAspectWidth: 16,
        displayAspectHeight: 9,
      );

      expect(config.codec, equals('avc1.42E01E'));
      expect(config.codedWidth, equals(1920));
      expect(config.codedHeight, equals(1080));
      expect(config.description, equals([0x01, 0x42, 0xE0]));
      expect(config.displayAspectWidth, equals(16));
      expect(config.displayAspectHeight, equals(9));
    });

    test('optional properties can be null', () {
      final config = VideoDecoderConfig(codec: 'avc1.42E01E');

      expect(config.codedWidth, isNull);
      expect(config.codedHeight, isNull);
      expect(config.description, isNull);
      expect(config.displayAspectWidth, isNull);
      expect(config.displayAspectHeight, isNull);
    });
  });

  group('EncodedChunk', () {
    test('stores properties correctly', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      final chunk = EncodedChunk(
        byteLength: 5,
        duration: 33333,
        timestamp: 100000,
        type: 'key',
        data: data,
      );

      expect(chunk.byteLength, equals(5));
      expect(chunk.duration, equals(33333));
      expect(chunk.timestamp, equals(100000));
      expect(chunk.type, equals('key'));
      expect(chunk.data, equals(data));
    });

    test('duration is optional', () {
      final chunk = EncodedChunk(
        byteLength: 10,
        timestamp: 0,
        type: 'delta',
        data: Uint8List(10),
      );

      expect(chunk.duration, isNull);
    });
  });

  group('SpsParser', () {
    test('parses Baseline Profile SPS', () {
      // Baseline Profile SPS: 640x480, profile 66 (Baseline), level 30
      // NAL header (0x67) + profile_idc (0x42=66) + constraint (0x80) + level (0x1E=30)
      final sps = Uint8List.fromList([
        0x67, 0x42, 0x80, 0x1E, // NAL + profile + constraint + level
        0x95, 0xA8, 0x28, 0x0F, 0x68, 0x40, // Exp-Golomb encoded params
      ]);

      final info = SpsParser.parse(sps);

      expect(info.profileIdc, equals(66)); // Baseline
      expect(info.levelIdc, equals(30)); // Level 3.0
      expect(info.chromaFormatIdc, equals(1)); // 4:2:0 default
      expect(info.bitDepthLuma, equals(8));
      expect(info.bitDepthChroma, equals(8));
    });

    test('parses High Profile SPS with chroma/bit depth', () {
      // High Profile SPS with 4:2:0 chroma, 8-bit
      // Profile 100 (High), Level 31
      final sps = Uint8List.fromList([
        0x67, 0x64, 0x00, 0x1F, // NAL + profile 100 + constraint + level 31
        0xAC, 0xD9, 0x40, 0x50, 0x05, 0xBB, 0x01, 0x10,
        0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03,
        0x03, 0xC0, 0xF1, 0x83, 0x19, 0x60,
      ]);

      final info = SpsParser.parse(sps);

      expect(info.profileIdc, equals(100)); // High
      expect(info.levelIdc, equals(31)); // Level 3.1
      // High Profile should parse chroma_format_idc
      expect(info.chromaFormatIdc, greaterThanOrEqualTo(1));
      expect(info.bitDepthLuma, equals(8));
      expect(info.bitDepthChroma, equals(8));
    });

    test('extracts dimensions from SPS', () {
      // Baseline Profile 640x480 SPS
      // pic_width_in_mbs_minus1 = 39 (640/16-1)
      // pic_height_in_map_units_minus1 = 29 (480/16-1)
      final sps = Uint8List.fromList([
        0x67, 0x42, 0xC0, 0x1E, // NAL + Baseline profile
        0xD9, 0x00, 0xA0, 0x27, 0xE5, 0xC0, 0x44, 0x00,
        0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00,
        0xC8, 0x3C, 0x60, 0xC6, 0x58,
      ]);

      final info = SpsParser.parse(sps);

      // Dimensions should be positive and reasonable
      // Note: actual dimensions may differ from MB-aligned due to cropping
      expect(info.width, greaterThan(0));
      expect(info.height, greaterThan(0));
      expect(info.width, lessThanOrEqualTo(4096)); // Reasonable max
      expect(info.height, lessThanOrEqualTo(4096));
    });

    test('SpsInfo toString includes all fields', () {
      final info = SpsInfo(
        profileIdc: 100,
        levelIdc: 31,
        chromaFormatIdc: 1,
        bitDepthLuma: 8,
        bitDepthChroma: 8,
        width: 1920,
        height: 1080,
      );

      final str = info.toString();

      expect(str, contains('profile=100'));
      expect(str, contains('level=31'));
      expect(str, contains('chroma=1'));
      expect(str, contains('1920x1080'));
    });
  });

  group('H264Utils', () {
    test('createAvccFromSpsPps creates basic avcC for Baseline', () {
      // Baseline Profile SPS/PPS
      final sps = Uint8List.fromList([
        0x67, 0x42, 0xC0, 0x1E, 0xD9, 0x00, 0xA0, 0x27,
      ]);
      final pps = Uint8List.fromList([0x68, 0xCE, 0x3C, 0x80]);

      final avcc = H264Utils.createAvccFromSpsPps(sps, pps);

      // Basic avcC structure:
      // configurationVersion (1) + AVCProfileIndication + profile_compat + level
      // + lengthSizeMinusOne + numSPS + spsLen + sps + numPPS + ppsLen + pps
      expect(avcc[0], equals(1)); // configurationVersion
      expect(avcc[1], equals(0x42)); // profile (Baseline = 66)
      expect(avcc[2], equals(0xC0)); // profile_compatibility
      expect(avcc[3], equals(0x1E)); // level
      expect(avcc[4], equals(0xFF)); // lengthSizeMinusOne = 3

      // No extra fields for Baseline Profile
      final expectedLen = 1 + 4 + 1 + 2 + sps.length + 1 + 2 + pps.length;
      expect(avcc.length, equals(expectedLen));
    });

    test('createAvccFromSpsPps adds extra fields for High Profile', () {
      // High Profile SPS (profile_idc = 100)
      final sps = Uint8List.fromList([
        0x67, 0x64, 0x00, 0x1F, // NAL + High Profile (100) + constraint + level
        0xAC, 0xD9, 0x40, 0x50, 0x05, 0xBB, 0x01, 0x10,
        0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x03,
        0x03, 0xC0, 0xF1, 0x83, 0x19, 0x60,
      ]);
      final pps = Uint8List.fromList([0x68, 0xCE, 0x3C, 0x80]);

      final avcc = H264Utils.createAvccFromSpsPps(sps, pps);

      expect(avcc[0], equals(1)); // configurationVersion
      expect(avcc[1], equals(0x64)); // profile (High = 100)

      // High Profile should have 4 extra bytes at the end
      final baseLen = 1 + 4 + 1 + 2 + sps.length + 1 + 2 + pps.length;
      expect(avcc.length, equals(baseLen + 4)); // +4 for extra fields

      // Check extra field format (last 4 bytes)
      final extraStart = baseLen;
      expect(avcc[extraStart] & 0xFC, equals(0xFC)); // reserved bits + chroma
      expect(avcc[extraStart + 1] & 0xF8, equals(0xF8)); // reserved + bit_depth_luma
      expect(avcc[extraStart + 2] & 0xF8, equals(0xF8)); // reserved + bit_depth_chroma
      expect(avcc[extraStart + 3], equals(0)); // numSpsExt
    });

    test('annexBToAvcc converts start codes to length prefixes', () {
      // Annex B format: start code + NAL data
      final annexB = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x01, // 4-byte start code
        0x67, 0x42, 0xC0, 0x1E, // SPS NAL
        0x00, 0x00, 0x01, // 3-byte start code
        0x68, 0xCE, 0x3C, 0x80, // PPS NAL
      ]);

      final avcc = H264Utils.annexBToAvcc(annexB);

      // AVCC format: 4-byte length + NAL data
      // First NAL: length=4, data=[0x67, 0x42, 0xC0, 0x1E]
      expect(avcc[0], equals(0));
      expect(avcc[1], equals(0));
      expect(avcc[2], equals(0));
      expect(avcc[3], equals(4)); // length
      expect(avcc[4], equals(0x67)); // NAL type

      // Second NAL: length=4, data=[0x68, 0xCE, 0x3C, 0x80]
      expect(avcc[8], equals(0));
      expect(avcc[9], equals(0));
      expect(avcc[10], equals(0));
      expect(avcc[11], equals(4)); // length
      expect(avcc[12], equals(0x68)); // NAL type
    });

    test('isHighProfile returns true for High Profile variants', () {
      // Test via createAvccFromSpsPps behavior
      // High Profile (100) should produce longer output
      final highSps = Uint8List.fromList([
        0x67, 0x64, 0x00, 0x1F, // High Profile
        0xAC, 0xD9, 0x40, 0x50, 0x05, 0xBB,
      ]);
      final baselineSps = Uint8List.fromList([
        0x67, 0x42, 0x00, 0x1F, // Baseline Profile
        0xAC, 0xD9, 0x40, 0x50, 0x05, 0xBB,
      ]);
      final pps = Uint8List.fromList([0x68, 0xCE, 0x3C, 0x80]);

      final highAvcc = H264Utils.createAvccFromSpsPps(highSps, pps);
      final baselineAvcc = H264Utils.createAvccFromSpsPps(baselineSps, pps);

      // High Profile should be 4 bytes longer (extra fields)
      expect(highAvcc.length, equals(baselineAvcc.length + 4));
    });
  });
}
