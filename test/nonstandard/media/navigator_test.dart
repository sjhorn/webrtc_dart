import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/media/navigator.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('MediaStreamConstraints', () {
    test('hasAudio returns true for true', () {
      const constraints = MediaStreamConstraints(audio: true);
      expect(constraints.hasAudio, isTrue);
      expect(constraints.hasVideo, isFalse);
    });

    test('hasVideo returns true for true', () {
      const constraints = MediaStreamConstraints(video: true);
      expect(constraints.hasAudio, isFalse);
      expect(constraints.hasVideo, isTrue);
    });

    test('hasAudio returns true for MediaTrackConstraints', () {
      const constraints = MediaStreamConstraints(
        audio: MediaTrackConstraints(deviceId: 'mic-1'),
      );
      expect(constraints.hasAudio, isTrue);
    });

    test('hasVideo returns true for MediaTrackConstraints', () {
      const constraints = MediaStreamConstraints(
        video: MediaTrackConstraints(width: 1920, height: 1080),
      );
      expect(constraints.hasVideo, isTrue);
    });

    test('has both audio and video', () {
      const constraints = MediaStreamConstraints(
        audio: true,
        video: true,
      );
      expect(constraints.hasAudio, isTrue);
      expect(constraints.hasVideo, isTrue);
    });
  });

  group('MediaTrackConstraints', () {
    test('stores all video properties', () {
      const constraints = MediaTrackConstraints(
        deviceId: 'camera-1',
        facingMode: 'user',
        width: 1280,
        height: 720,
        frameRate: 30.0,
        aspectRatio: 16 / 9,
      );

      expect(constraints.deviceId, equals('camera-1'));
      expect(constraints.facingMode, equals('user'));
      expect(constraints.width, equals(1280));
      expect(constraints.height, equals(720));
      expect(constraints.frameRate, equals(30.0));
      expect(constraints.aspectRatio, closeTo(1.777, 0.001));
    });

    test('stores all audio properties', () {
      const constraints = MediaTrackConstraints(
        deviceId: 'mic-1',
        sampleRate: 48000,
        sampleSize: 16,
        channelCount: 2,
        echoCancellation: true,
        autoGainControl: true,
        noiseSuppression: true,
      );

      expect(constraints.deviceId, equals('mic-1'));
      expect(constraints.sampleRate, equals(48000));
      expect(constraints.sampleSize, equals(16));
      expect(constraints.channelCount, equals(2));
      expect(constraints.echoCancellation, isTrue);
      expect(constraints.autoGainControl, isTrue);
      expect(constraints.noiseSuppression, isTrue);
    });
  });

  group('MediaDevices', () {
    test('getUserMedia returns stream with video track', () async {
      final devices = MediaDevices();

      final stream = await devices.getUserMedia(
        const MediaStreamConstraints(video: true),
      );

      expect(stream.getTracks().length, equals(1));
      expect(stream.getVideoTracks().length, equals(1));
      expect(stream.getAudioTracks(), isEmpty);

      for (final t in stream.getTracks()) {
        t.stop();
      }
    });

    test('getUserMedia returns stream with audio track', () async {
      final devices = MediaDevices();

      final stream = await devices.getUserMedia(
        const MediaStreamConstraints(audio: true),
      );

      expect(stream.getTracks().length, equals(1));
      expect(stream.getAudioTracks().length, equals(1));
      expect(stream.getVideoTracks(), isEmpty);

      for (final t in stream.getTracks()) {
        t.stop();
      }
    });

    test('getUserMedia returns stream with both tracks', () async {
      final devices = MediaDevices();

      final stream = await devices.getUserMedia(
        const MediaStreamConstraints(audio: true, video: true),
      );

      expect(stream.getTracks().length, equals(2));
      expect(stream.getAudioTracks().length, equals(1));
      expect(stream.getVideoTracks().length, equals(1));

      for (final t in stream.getTracks()) {
        t.stop();
      }
    });

    test('getUserMedia throws when no media requested', () async {
      final devices = MediaDevices();

      expect(
        () => devices.getUserMedia(
          const MediaStreamConstraints(audio: false, video: false),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('pre-configured video track forwards RTP', () async {
      // Create a source track
      final sourceTrack = MediaStreamTrack(kind: MediaKind.video);

      // Create MediaDevices with pre-configured video
      final devices = MediaDevices(video: sourceTrack);

      // Get user media
      final stream = await devices.getUserMedia(
        const MediaStreamConstraints(video: true),
      );

      final userTrack = stream.getVideoTracks().first;
      final received = <(RtpPacket, RtpExtensions?)>[];

      userTrack.onReceiveRtp.listen(received.add);

      // Send RTP to source track
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

      sourceTrack.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 50));

      expect(received.length, equals(1));
      // SSRC should be different (cloned packet)
      expect(received.first.$1.ssrc, isNot(equals(packet.ssrc)));
      expect(received.first.$1.sequenceNumber, equals(1000));

      sourceTrack.stop();
      for (final t in stream.getTracks()) {
        t.stop();
      }
    });

    test('pre-configured audio track forwards RTP', () async {
      final sourceTrack = MediaStreamTrack(kind: MediaKind.audio);
      final devices = MediaDevices(audio: sourceTrack);

      final stream = await devices.getUserMedia(
        const MediaStreamConstraints(audio: true),
      );

      final userTrack = stream.getAudioTracks().first;
      final received = <(RtpPacket, RtpExtensions?)>[];

      userTrack.onReceiveRtp.listen(received.add);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 2000,
        timestamp: 54321,
        ssrc: 0xABCDEF00,
        csrcs: [],
        payload: Uint8List.fromList([5, 6, 7, 8]),
      );

      sourceTrack.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 50));

      expect(received.length, equals(1));
      expect(received.first.$1.sequenceNumber, equals(2000));

      sourceTrack.stop();
      for (final t in stream.getTracks()) {
        t.stop();
      }
    });

    test('getDisplayMedia returns same as getUserMedia', () async {
      final devices = MediaDevices();

      final stream = await devices.getDisplayMedia(
        const MediaStreamConstraints(video: true),
      );

      expect(stream.getVideoTracks().length, equals(1));

      for (final t in stream.getTracks()) {
        t.stop();
      }
    });
  });

  group('UdpMediaSource', () {
    test('has track and dispose function', () {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      var disposed = false;

      final source = UdpMediaSource(
        track: track,
        dispose: () => disposed = true,
      );

      expect(source.track, equals(track));
      expect(disposed, isFalse);

      source.dispose();
      expect(disposed, isTrue);

      track.stop();
    });
  });

  group('Navigator', () {
    test('has mediaDevices property', () {
      final nav = Navigator();
      expect(nav.mediaDevices, isNotNull);
    });

    test('accepts custom MediaDevices', () {
      final devices = MediaDevices();
      final nav = Navigator(mediaDevices: devices);
      expect(nav.mediaDevices, equals(devices));
    });
  });

  group('default navigator', () {
    test('is available globally', () {
      expect(navigator, isNotNull);
      expect(navigator.mediaDevices, isNotNull);
    });
  });
}
