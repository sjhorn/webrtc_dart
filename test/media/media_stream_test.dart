import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/media_stream.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';

void main() {
  group('MediaStream', () {
    test('construction with default ID', () {
      final stream = MediaStream();
      expect(stream.id, isNotEmpty);
      expect(stream.id, contains('stream'));
    });

    test('construction with custom ID', () {
      final stream = MediaStream(id: 'my-stream-123');
      expect(stream.id, equals('my-stream-123'));
    });

    test('construction from tracks', () {
      final audio = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final video = VideoStreamTrack(id: 'video1', label: 'Camera');

      final stream = MediaStream.fromTracks([audio, video], id: 'stream-1');

      expect(stream.id, equals('stream-1'));
      expect(stream.getTracks().length, equals(2));
    });

    test('getTracks returns all tracks', () {
      final stream = MediaStream();
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final track2 = VideoStreamTrack(id: 'video1', label: 'Video');

      stream.addTrack(track1);
      stream.addTrack(track2);

      final tracks = stream.getTracks();
      expect(tracks.length, equals(2));
      expect(tracks, contains(track1));
      expect(tracks, contains(track2));
    });

    test('getTracks returns unmodifiable list', () {
      final stream = MediaStream();
      stream.addTrack(AudioStreamTrack(id: 'audio1', label: 'Audio'));

      final tracks = stream.getTracks();
      expect(() => tracks.add(AudioStreamTrack(id: 'audio2', label: 'Audio2')),
          throwsA(isA<UnsupportedError>()));
    });

    test('getAudioTracks returns only audio tracks', () {
      final stream = MediaStream();
      final audio1 = AudioStreamTrack(id: 'audio1', label: 'Mic 1');
      final audio2 = AudioStreamTrack(id: 'audio2', label: 'Mic 2');
      final video = VideoStreamTrack(id: 'video1', label: 'Camera');

      stream.addTrack(audio1);
      stream.addTrack(video);
      stream.addTrack(audio2);

      final audioTracks = stream.getAudioTracks();
      expect(audioTracks.length, equals(2));
      expect(audioTracks, contains(audio1));
      expect(audioTracks, contains(audio2));
    });

    test('getVideoTracks returns only video tracks', () {
      final stream = MediaStream();
      final audio = AudioStreamTrack(id: 'audio1', label: 'Mic');
      final video1 = VideoStreamTrack(id: 'video1', label: 'Camera 1');
      final video2 = VideoStreamTrack(id: 'video2', label: 'Camera 2');

      stream.addTrack(video1);
      stream.addTrack(audio);
      stream.addTrack(video2);

      final videoTracks = stream.getVideoTracks();
      expect(videoTracks.length, equals(2));
      expect(videoTracks, contains(video1));
      expect(videoTracks, contains(video2));
    });

    test('getTrackById returns correct track', () {
      final stream = MediaStream();
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final track2 = VideoStreamTrack(id: 'video1', label: 'Video');

      stream.addTrack(track1);
      stream.addTrack(track2);

      expect(stream.getTrackById('audio1'), equals(track1));
      expect(stream.getTrackById('video1'), equals(track2));
    });

    test('getTrackById returns null for non-existent track', () {
      final stream = MediaStream();
      expect(stream.getTrackById('non-existent'), isNull);
    });

    test('addTrack emits onAddTrack event', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      MediaStreamTrack? addedTrack;

      stream.onAddTrack.listen((t) {
        addedTrack = t;
      });

      stream.addTrack(track);

      await Future.delayed(Duration(milliseconds: 10));

      expect(addedTrack, equals(track));
    });

    test('addTrack does not add duplicate tracks', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      var addCount = 0;

      stream.onAddTrack.listen((_) {
        addCount++;
      });

      stream.addTrack(track);
      stream.addTrack(track); // Add same track again

      await Future.delayed(Duration(milliseconds: 10));

      expect(stream.getTracks().length, equals(1));
      expect(addCount, equals(1));
    });

    test('removeTrack emits onRemoveTrack event', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      MediaStreamTrack? removedTrack;

      stream.addTrack(track);

      stream.onRemoveTrack.listen((t) {
        removedTrack = t;
      });

      stream.removeTrack(track);

      await Future.delayed(Duration(milliseconds: 10));

      expect(removedTrack, equals(track));
      expect(stream.getTracks(), isEmpty);
    });

    test('removeTrack does nothing for non-existent track', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      var removeCount = 0;

      stream.onRemoveTrack.listen((_) {
        removeCount++;
      });

      stream.removeTrack(track);

      await Future.delayed(Duration(milliseconds: 10));

      expect(removeCount, equals(0));
    });

    test('active is true when at least one track is live', () {
      final stream = MediaStream();
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final track2 = VideoStreamTrack(id: 'video1', label: 'Video');

      stream.addTrack(track1);
      stream.addTrack(track2);

      expect(stream.active, isTrue);

      track1.stop();
      expect(stream.active, isTrue); // track2 is still live

      track2.stop();
      expect(stream.active, isFalse); // all tracks ended
    });

    test('active is false when stream is empty', () {
      final stream = MediaStream();
      expect(stream.active, isFalse);
    });

    test('onActiveChange emits when active state changes', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final activeStates = <bool>[];

      stream.onActiveChange.listen((active) {
        activeStates.add(active);
      });

      stream.addTrack(track);

      await Future.delayed(Duration(milliseconds: 10));

      expect(activeStates.last, isTrue);
    });

    test('clone creates new stream with cloned tracks', () {
      final stream = MediaStream(id: 'original');
      final audio = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final video = VideoStreamTrack(id: 'video1', label: 'Video');

      stream.addTrack(audio);
      stream.addTrack(video);

      final cloned = stream.clone();

      expect(cloned.id, isNot(equals(stream.id)));
      expect(cloned.getTracks().length, equals(2));

      // Cloned tracks should have different IDs
      final clonedTracks = cloned.getTracks();
      expect(clonedTracks.any((t) => t.id == 'audio1'), isFalse);
      expect(clonedTracks.any((t) => t.id == 'video1'), isFalse);
    });

    test('dispose stops all tracks and closes controllers', () async {
      final stream = MediaStream();
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      stream.addTrack(track);

      expect(track.state, equals(MediaStreamTrackState.live));

      stream.dispose();

      expect(track.state, equals(MediaStreamTrackState.ended));
      expect(stream.getTracks(), isEmpty);
    });

    test('toString returns readable format', () {
      final stream = MediaStream(id: 'test-stream');
      stream.addTrack(AudioStreamTrack(id: 'audio1', label: 'Audio'));
      stream.addTrack(VideoStreamTrack(id: 'video1', label: 'Video'));

      final str = stream.toString();
      expect(str, contains('MediaStream'));
      expect(str, contains('test-stream'));
      expect(str, contains('audio=1'));
      expect(str, contains('video=1'));
    });
  });
}
