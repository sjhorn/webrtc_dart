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
          0x01, 0x42, 0xE0, 0x1E, 0xFF, 0xE1, 0x00, 0x10,
          0x67, 0x42, 0xE0, 0x1E, 0xDA, 0x01, 0x40, 0x16,
          0xEC, 0x04, 0x40, 0x00, 0x00, 0x03, 0x00, 0x40,
          0x01, 0x00, 0x04, 0x68, 0xCE, 0x3C, 0x80,
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
          0x01, 0x42, 0xE0, 0x1E, 0xFF, 0xE1, 0x00, 0x04,
          0x67, 0x42, 0xE0, 0x1E, 0x01, 0x00, 0x04,
          0x68, 0xCE, 0x3C, 0x80,
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
          0x01, 0x42, 0xE0, 0x1E, 0xFF, 0xE1, 0x00, 0x04,
          0x67, 0x42, 0xE0, 0x1E, 0x01, 0x00, 0x04,
          0x68, 0xCE, 0x3C, 0x80,
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
}
