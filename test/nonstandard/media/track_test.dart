import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('MediaStreamTrack', () {
    test('creates local audio track', () {
      final track = MediaStreamTrack(kind: MediaKind.audio);

      expect(track.uuid, isNotEmpty);
      expect(track.uuid.length, equals(36)); // UUID format
      expect(track.kind, equals(MediaKind.audio));
      expect(track.remote, isFalse);
      expect(track.label, contains('local'));
      expect(track.label, contains('audio'));
      expect(track.enabled, isTrue);
      expect(track.stopped, isFalse);
      expect(track.muted, isTrue); // No data received yet
    });

    test('creates local video track', () {
      final track = MediaStreamTrack(kind: MediaKind.video);

      expect(track.kind, equals(MediaKind.video));
      expect(track.label, contains('video'));
    });

    test('creates remote track', () {
      final track = MediaStreamTrack(kind: MediaKind.audio, remote: true);

      expect(track.remote, isTrue);
      expect(track.label, contains('remote'));
    });

    test('writeRtp emits RTP packets for local track', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      final received = <(RtpPacket, RtpExtensions?)>[];

      track.onReceiveRtp.listen(received.add);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1000,
        timestamp: 12345,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      track.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received.first.$1.sequenceNumber, equals(1000));
      expect(track.muted, isFalse); // Received data

      track.stop();
    });

    test('writeRtp accepts raw bytes', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      final received = <(RtpPacket, RtpExtensions?)>[];

      track.onReceiveRtp.listen(received.add);

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

      track.writeRtp(packet.serialize());
      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received.first.$1.sequenceNumber, equals(2000));

      track.stop();
    });

    test('writeRtp overrides payload type when codec is set', () async {
      final track = MediaStreamTrack(
        kind: MediaKind.audio,
        codec: RtpCodecParameters(
          mimeType: 'audio/opus',
          payloadType: 120,
          clockRate: 48000,
        ),
      );
      final received = <(RtpPacket, RtpExtensions?)>[];

      track.onReceiveRtp.listen(received.add);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 96, // Different from codec's payloadType
        sequenceNumber: 1000,
        timestamp: 12345,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List.fromList([1, 2, 3]),
      );

      track.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(received.first.$1.payloadType, equals(120)); // Overridden

      track.stop();
    });

    test('writeRtp throws for remote track', () {
      final track = MediaStreamTrack(kind: MediaKind.audio, remote: true);

      expect(
        () => track.writeRtp(Uint8List(10)),
        throwsA(isA<StateError>()),
      );

      track.stop();
    });

    test('writeRtp ignores after stopped', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      final received = <(RtpPacket, RtpExtensions?)>[];

      track.onReceiveRtp.listen(received.add);
      track.stop();

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 1000,
        timestamp: 12345,
        ssrc: 0x12345678,
        csrcs: [],
        payload: Uint8List(10),
      );

      track.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(received, isEmpty);
    });

    test('stop emits ended event', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      var endedCalled = false;

      track.onEnded.listen((_) => endedCalled = true);
      track.stop();

      await Future.delayed(Duration(milliseconds: 10));

      expect(endedCalled, isTrue);
      expect(track.stopped, isTrue);
      expect(track.muted, isTrue);
    });

    test('clone creates new track with same kind', () {
      final track = MediaStreamTrack(
        kind: MediaKind.video,
        streamId: 'stream-1',
        rid: 'high',
        codec: RtpCodecParameters(
          mimeType: 'video/VP8',
          payloadType: 96,
          clockRate: 90000,
        ),
      );

      final cloned = track.clone();

      expect(cloned.kind, equals(track.kind));
      expect(cloned.streamId, equals(track.streamId));
      expect(cloned.rid, equals(track.rid));
      expect(cloned.codec, equals(track.codec));
      expect(cloned.uuid, isNot(equals(track.uuid))); // New UUID
      expect(cloned.id, isNot(equals(track.id))); // New ID
      expect(cloned.ssrc, isNull); // SSRC not copied

      track.stop();
      cloned.stop();
    });

    test('receiveRtp for remote tracks', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio, remote: true);
      final received = <(RtpPacket, RtpExtensions?)>[];

      track.onReceiveRtp.listen(received.add);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: false,
        payloadType: 111,
        sequenceNumber: 3000,
        timestamp: 99999,
        ssrc: 0x11111111,
        csrcs: [],
        payload: Uint8List.fromList([9, 8, 7]),
      );

      track.receiveRtp(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received.first.$1.sequenceNumber, equals(3000));

      track.stop();
    });

    test('updates headerInfo on RTP receive', () async {
      final track = MediaStreamTrack(kind: MediaKind.audio);

      expect(track.headerInfo, isNull);

      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 111,
        sequenceNumber: 5000,
        timestamp: 77777,
        ssrc: 0x22222222,
        csrcs: [],
        payload: Uint8List(10),
      );

      track.writeRtp(packet);
      await Future.delayed(Duration(milliseconds: 10));

      expect(track.headerInfo, isNotNull);
      expect(track.headerInfo!.sequenceNumber, equals(5000));
      expect(track.headerInfo!.timestamp, equals(77777));
      expect(track.headerInfo!.ssrc, equals(0x22222222));
      expect(track.headerInfo!.marker, isTrue);

      track.stop();
    });

    test('notifySourceChanged emits on stream', () async {
      final track = MediaStreamTrack(kind: MediaKind.video);
      final changes = <RtpHeaderInfo>[];

      track.onSourceChanged.listen(changes.add);

      final header = RtpHeaderInfo(
        sequenceNumber: 100,
        timestamp: 200,
        ssrc: 0x33333333,
        payloadType: 96,
        marker: false,
      );

      track.notifySourceChanged(header);
      await Future.delayed(Duration(milliseconds: 10));

      expect(changes.length, equals(1));
      expect(changes.first.ssrc, equals(0x33333333));

      track.stop();
    });

    test('toString includes label and id', () {
      final track = MediaStreamTrack(kind: MediaKind.audio, id: 'track-123');

      final str = track.toString();
      expect(str, contains('MediaStreamTrack'));
      expect(str, contains('local audio'));
      expect(str, contains('track-123'));

      track.stop();
    });
  });

  group('MediaStream', () {
    test('creates with unique ID', () {
      final stream = MediaStream();

      expect(stream.id, isNotEmpty);
      expect(stream.id.length, equals(36));
    });

    test('creates with provided tracks', () {
      final audioTrack = MediaStreamTrack(kind: MediaKind.audio);
      final videoTrack = MediaStreamTrack(kind: MediaKind.video);

      final stream = MediaStream([audioTrack, videoTrack]);

      expect(stream.getTracks().length, equals(2));
      expect(audioTrack.streamId, equals(stream.id));
      expect(videoTrack.streamId, equals(stream.id));

      audioTrack.stop();
      videoTrack.stop();
    });

    test('creates with specific ID', () {
      final stream = MediaStream.withId('my-stream-id');

      expect(stream.id, equals('my-stream-id'));
    });

    test('addTrack sets streamId', () {
      final stream = MediaStream();
      final track = MediaStreamTrack(kind: MediaKind.audio);

      stream.addTrack(track);

      expect(track.streamId, equals(stream.id));
      expect(stream.getTracks().length, equals(1));

      track.stop();
    });

    test('removeTrack removes from stream', () {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      final stream = MediaStream([track]);

      final removed = stream.removeTrack(track);

      expect(removed, isTrue);
      expect(stream.getTracks(), isEmpty);

      track.stop();
    });

    test('getAudioTracks returns only audio', () {
      final audio1 = MediaStreamTrack(kind: MediaKind.audio);
      final audio2 = MediaStreamTrack(kind: MediaKind.audio);
      final video = MediaStreamTrack(kind: MediaKind.video);

      final stream = MediaStream([audio1, video, audio2]);

      expect(stream.getAudioTracks().length, equals(2));

      audio1.stop();
      audio2.stop();
      video.stop();
    });

    test('getVideoTracks returns only video', () {
      final audio = MediaStreamTrack(kind: MediaKind.audio);
      final video1 = MediaStreamTrack(kind: MediaKind.video);
      final video2 = MediaStreamTrack(kind: MediaKind.video);

      final stream = MediaStream([audio, video1, video2]);

      expect(stream.getVideoTracks().length, equals(2));

      audio.stop();
      video1.stop();
      video2.stop();
    });

    test('getTrackById finds track', () {
      final track = MediaStreamTrack(kind: MediaKind.audio, id: 'my-track');
      final stream = MediaStream([track]);

      expect(stream.getTrackById('my-track'), equals(track));
      expect(stream.getTrackById('nonexistent'), isNull);

      track.stop();
    });

    test('clone creates new stream with cloned tracks', () {
      final audio = MediaStreamTrack(kind: MediaKind.audio);
      final video = MediaStreamTrack(kind: MediaKind.video);
      final stream = MediaStream([audio, video]);

      final cloned = stream.clone();

      expect(cloned.id, isNot(equals(stream.id)));
      expect(cloned.getTracks().length, equals(2));
      expect(cloned.getTracks()[0].uuid, isNot(equals(audio.uuid)));
      expect(cloned.getTracks()[1].uuid, isNot(equals(video.uuid)));

      audio.stop();
      video.stop();
      for (final t in cloned.getTracks()) {
        t.stop();
      }
    });

    test('active returns true when has non-stopped tracks', () {
      final track = MediaStreamTrack(kind: MediaKind.audio);
      final stream = MediaStream([track]);

      expect(stream.active, isTrue);

      track.stop();
      expect(stream.active, isFalse);
    });

    test('toString includes id and track count', () {
      final stream = MediaStream([
        MediaStreamTrack(kind: MediaKind.audio),
        MediaStreamTrack(kind: MediaKind.video),
      ]);

      final str = stream.toString();
      expect(str, contains('MediaStream'));
      expect(str, contains('tracks: 2'));

      for (final t in stream.getTracks()) {
        t.stop();
      }
    });
  });

  group('RtpCodecParameters', () {
    test('stores parameters correctly', () {
      final codec = RtpCodecParameters(
        mimeType: 'video/H264',
        payloadType: 102,
        clockRate: 90000,
        channels: null,
        parameters: {'profile-level-id': '42e01f'},
      );

      expect(codec.mimeType, equals('video/H264'));
      expect(codec.payloadType, equals(102));
      expect(codec.clockRate, equals(90000));
      expect(codec.channels, isNull);
      expect(codec.parameters['profile-level-id'], equals('42e01f'));
    });

    test('defaults parameters to empty map', () {
      final codec = RtpCodecParameters(
        mimeType: 'audio/opus',
        payloadType: 111,
        clockRate: 48000,
      );

      expect(codec.parameters, isEmpty);
    });
  });

  group('RtpHeaderInfo', () {
    test('fromPacket extracts fields correctly', () {
      final packet = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        marker: true,
        payloadType: 96,
        sequenceNumber: 12345,
        timestamp: 67890,
        ssrc: 0xAABBCCDD,
        csrcs: [],
        payload: Uint8List(10),
      );

      final info = RtpHeaderInfo.fromPacket(packet);

      expect(info.sequenceNumber, equals(12345));
      expect(info.timestamp, equals(67890));
      expect(info.ssrc, equals(0xAABBCCDD));
      expect(info.payloadType, equals(96));
      expect(info.marker, isTrue);
    });
  });
}
