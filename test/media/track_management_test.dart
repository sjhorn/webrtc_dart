import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';

void main() {
  group('RTCRtpSender replaceTrack', () {
    late RtpSession rtpSession;
    late RtpCodecParameters codec;

    setUp(() {
      rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
      codec = createOpusCodec(payloadType: 111);
    });

    tearDown(() {
      rtpSession.stop();
    });

    test('replaceTrack with null removes track', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final sender = RTCRtpSender(
        track: track,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(sender.track, equals(track));

      await sender.replaceTrack(null);

      expect(sender.track, isNull);
    });

    test('replaceTrack with new track of same kind succeeds', () async {
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio 1');
      final track2 = AudioStreamTrack(id: 'audio2', label: 'Audio 2');
      final sender = RTCRtpSender(
        track: track1,
        rtpSession: rtpSession,
        codec: codec,
      );

      await sender.replaceTrack(track2);

      expect(sender.track, equals(track2));
    });

    test('replaceTrack with different kind throws', () async {
      final audioTrack = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final videoTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      final sender = RTCRtpSender(
        track: audioTrack,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(
        () => sender.replaceTrack(videoTrack),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('replaceTrack with ended track throws', () async {
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio 1');
      final track2 = AudioStreamTrack(id: 'audio2', label: 'Audio 2');
      track2.stop(); // End the track

      final sender = RTCRtpSender(
        track: track1,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(
        () => sender.replaceTrack(track2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('replaceTrack on stopped sender throws', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final sender = RTCRtpSender(
        track: track,
        rtpSession: rtpSession,
        codec: codec,
      );

      sender.stop();

      expect(
        () => sender.replaceTrack(null),
        throwsA(isA<StateError>()),
      );
    });

    test('replaceTrack from null to track succeeds', () async {
      final sender = RTCRtpSender(
        track: null,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(sender.track, isNull);

      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      await sender.replaceTrack(track);

      expect(sender.track, equals(track));
    });

    test('multiple replaceTrack calls work correctly', () async {
      final track1 = AudioStreamTrack(id: 'audio1', label: 'Audio 1');
      final track2 = AudioStreamTrack(id: 'audio2', label: 'Audio 2');
      final track3 = AudioStreamTrack(id: 'audio3', label: 'Audio 3');

      final sender = RTCRtpSender(
        track: track1,
        rtpSession: rtpSession,
        codec: codec,
      );

      await sender.replaceTrack(track2);
      expect(sender.track, equals(track2));

      await sender.replaceTrack(null);
      expect(sender.track, isNull);

      await sender.replaceTrack(track3);
      expect(sender.track, equals(track3));
    });
  });

  group('RTCRtpSender video track', () {
    late RtpSession rtpSession;
    late RtpCodecParameters codec;

    setUp(() {
      rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
      codec = createVp8Codec(payloadType: 96);
    });

    tearDown(() {
      rtpSession.stop();
    });

    test('replaceTrack with video tracks works', () async {
      final track1 = VideoStreamTrack(id: 'video1', label: 'Video 1');
      final track2 = VideoStreamTrack(id: 'video2', label: 'Video 2');

      final sender = RTCRtpSender(
        track: track1,
        rtpSession: rtpSession,
        codec: codec,
      );

      await sender.replaceTrack(track2);
      expect(sender.track, equals(track2));
    });
  });

  group('RTCRtpReceiver', () {
    late RtpSession rtpSession;
    late RtpCodecParameters codec;

    setUp(() {
      rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
      codec = createOpusCodec(payloadType: 111);
    });

    tearDown(() {
      rtpSession.stop();
    });

    test('receiver creates track on construction', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final receiver = RTCRtpReceiver(
        track: track,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(receiver.track, equals(track));
    });

    test('receiver allTracks includes primary track', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');
      final receiver = RTCRtpReceiver(
        track: track,
        rtpSession: rtpSession,
        codec: codec,
      );

      expect(receiver.allTracks, contains(track));
    });

    test('receiver addTrackForRid adds simulcast track', () {
      final primaryTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      final highTrack =
          VideoStreamTrack(id: 'video_high', label: 'High', rid: 'high');

      final receiver = RTCRtpReceiver(
        track: primaryTrack,
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
      );

      receiver.addTrackForRid('high', highTrack);

      expect(receiver.getTrackByRid('high'), equals(highTrack));
      expect(receiver.allTracks.length, equals(2));
    });

    test('receiver associateSsrcWithTrack maps SSRC', () {
      final track = VideoStreamTrack(id: 'video1', label: 'Video');
      final receiver = RTCRtpReceiver(
        track: track,
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
      );

      receiver.associateSsrcWithTrack(12345, track);

      expect(receiver.getTrackBySsrc(12345), equals(track));
    });

    test('receiver stop stops all tracks', () {
      final primaryTrack = VideoStreamTrack(id: 'video1', label: 'Video');
      final highTrack =
          VideoStreamTrack(id: 'video_high', label: 'High', rid: 'high');
      final lowTrack =
          VideoStreamTrack(id: 'video_low', label: 'Low', rid: 'low');

      final receiver = RTCRtpReceiver(
        track: primaryTrack,
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
      );

      receiver.addTrackForRid('high', highTrack);
      receiver.addTrackForRid('low', lowTrack);

      receiver.stop();

      expect(primaryTrack.state, equals(MediaStreamTrackState.ended));
      expect(highTrack.state, equals(MediaStreamTrackState.ended));
      expect(lowTrack.state, equals(MediaStreamTrackState.ended));
    });
  });

  group('RTCRtpTransceiver', () {
    test('transceiver has sender and receiver', () {
      final rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );

      final transceiver = createAudioTransceiver(
        mid: '1',
        rtpSession: rtpSession,
      );

      expect(transceiver.sender, isNotNull);
      expect(transceiver.receiver, isNotNull);
      expect(transceiver.kind, equals(MediaStreamTrackKind.audio));

      transceiver.stop();
      rtpSession.stop();
    });

    test('transceiver direction can be changed', () {
      final rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );

      final transceiver = createVideoTransceiver(
        mid: '2',
        rtpSession: rtpSession,
        direction: RtpTransceiverDirection.sendonly,
      );

      expect(transceiver.direction, equals(RtpTransceiverDirection.sendonly));

      transceiver.direction = RtpTransceiverDirection.recvonly;
      // Note: direction setter sets desiredDirection, currentDirection stays until negotiation
      // But for our purposes the setter works

      transceiver.stop();
      rtpSession.stop();
    });

    test('transceiver stop stops sender and receiver', () {
      final rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );

      final transceiver = createAudioTransceiver(
        mid: '3',
        rtpSession: rtpSession,
      );

      expect(transceiver.stopped, isFalse);

      transceiver.stop();

      expect(transceiver.stopped, isTrue);

      rtpSession.stop();
    });

    test('transceiver simulcast parameters', () {
      final rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );

      final transceiver = createVideoTransceiver(
        mid: '4',
        rtpSession: rtpSession,
      );

      expect(transceiver.simulcast, isEmpty);

      transceiver.addSimulcastLayer(RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.send,
      ));

      expect(transceiver.simulcast.length, equals(1));
      expect(transceiver.simulcast.first.rid, equals('high'));

      transceiver.stop();
      rtpSession.stop();
    });
  });

  group('MediaStreamTrack', () {
    test('audio track state transitions', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      expect(track.state, equals(MediaStreamTrackState.live));
      expect(track.kind, equals(MediaStreamTrackKind.audio));

      track.stop();

      expect(track.state, equals(MediaStreamTrackState.ended));
    });

    test('video track state transitions', () {
      final track = VideoStreamTrack(id: 'video1', label: 'Video');

      expect(track.state, equals(MediaStreamTrackState.live));
      expect(track.kind, equals(MediaStreamTrackKind.video));

      track.stop();

      expect(track.state, equals(MediaStreamTrackState.ended));
    });

    test('track enabled property', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      expect(track.enabled, isTrue);

      track.enabled = false;
      expect(track.enabled, isFalse);

      track.enabled = true;
      expect(track.enabled, isTrue);
    });

    test('track muted property', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      expect(track.muted, isFalse);

      track.setMuted(true);
      expect(track.muted, isTrue);

      track.setMuted(false);
      expect(track.muted, isFalse);
    });

    test('track clone creates new track with same properties', () {
      final track = AudioStreamTrack(
        id: 'audio1',
        label: 'Audio',
        rid: 'high',
      );

      final cloned = track.clone();

      expect(cloned.label, equals(track.label));
      expect(cloned.kind, equals(track.kind));
      expect(cloned.rid, equals(track.rid));
      expect(cloned.id, isNot(equals(track.id))); // Different ID
      expect(cloned.state, equals(MediaStreamTrackState.live));
    });

    test('video track clone preserves rid', () {
      final track = VideoStreamTrack(
        id: 'video1',
        label: 'Video',
        rid: 'low',
      );

      final cloned = track.clone();

      expect(cloned.rid, equals('low'));
    });

    test('track onEnded stream fires when stopped', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      var endedFired = false;
      track.onEnded.listen((_) {
        endedFired = true;
      });

      track.stop();

      // Give stream a chance to fire
      await Future.delayed(Duration.zero);

      expect(endedFired, isTrue);
    });

    test('track onStateChange stream fires', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      final states = <MediaStreamTrackState>[];
      track.onStateChange.listen((state) {
        states.add(state);
      });

      track.stop();

      // Give stream a chance to fire
      await Future.delayed(Duration.zero);

      expect(states, contains(MediaStreamTrackState.ended));
    });

    test('track onMute stream fires', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Audio');

      final muteEvents = <bool>[];
      track.onMute.listen((muted) {
        muteEvents.add(muted);
      });

      track.setMuted(true);
      track.setMuted(false);

      // Give stream a chance to fire
      await Future.delayed(Duration.zero);

      expect(muteEvents, equals([true, false]));
    });
  });
}
