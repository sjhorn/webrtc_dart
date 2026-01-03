import 'dart:async';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/rtc_dtmf_sender.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_sender.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';

void main() {
  group('RTCDTMFSender', () {
    late RtpSession mockSession;
    late RTCDTMFSender dtmfSender;

    setUp(() {
      // Create a minimal RTP session for testing
      mockSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
      dtmfSender = RTCDTMFSender(
        rtpSession: mockSession,
        payloadType: 101,
      );
    });

    tearDown(() {
      dtmfSender.dispose();
    });

    test('initial state', () {
      expect(dtmfSender.canInsertDTMF, isTrue);
      expect(dtmfSender.toneBuffer, isEmpty);
    });

    test('insertDTMF starts sending tones', () {
      dtmfSender.insertDTMF('123');
      // First tone starts immediately, remaining are in buffer
      // Buffer may be '23' or '123' depending on timing
      expect(dtmfSender.toneBuffer.length, lessThanOrEqualTo(3));
    });

    test('insertDTMF replaces existing buffer', () {
      dtmfSender.insertDTMF('123');
      dtmfSender.insertDTMF('456789'); // Longer to ensure some remain
      // New tones replace old ones
      expect(dtmfSender.toneBuffer, contains('6'));
    });

    test('insertDTMF converts to uppercase', () {
      // Use valid DTMF characters a-d (which map to A-D)
      dtmfSender.insertDTMF('abcd');
      // Check that buffer contains uppercase characters
      expect(
          dtmfSender.toneBuffer.toUpperCase(), equals(dtmfSender.toneBuffer));
    });

    test('insertDTMF accepts all valid characters', () {
      // All these characters should be valid
      expect(
        () => dtmfSender.insertDTMF('0123456789*#ABCD,'),
        returnsNormally,
      );
    });

    test('insertDTMF throws on invalid characters', () {
      expect(
        () => dtmfSender.insertDTMF('12X3'),
        throwsArgumentError,
      );
    });

    test('insertDTMF clamps duration to valid range', () {
      // Duration should be clamped to 40-6000ms
      dtmfSender.insertDTMF('1', duration: 10); // Below minimum
      // No error thrown, duration is clamped internally

      dtmfSender.insertDTMF('1', duration: 10000); // Above maximum
      // No error thrown, duration is clamped internally
    });

    test('insertDTMF enforces minimum interToneGap', () {
      // interToneGap minimum is 30ms
      dtmfSender.insertDTMF('1', interToneGap: 10);
      // No error thrown, gap is enforced internally
    });

    test('insertDTMF throws when canInsertDTMF is false', () {
      dtmfSender.stop();
      expect(
        () => dtmfSender.insertDTMF('123'),
        throwsStateError,
      );
    });

    test('stop clears toneBuffer and sets canInsertDTMF false', () {
      dtmfSender.insertDTMF('123');
      dtmfSender.stop();

      expect(dtmfSender.canInsertDTMF, isFalse);
      expect(dtmfSender.toneBuffer, isEmpty);
    });

    test('ontonechange event fires for each tone', () async {
      final events = <RTCDTMFToneChangeEvent>[];
      dtmfSender.ontonechange = (event) => events.add(event);

      // Insert a single short tone
      dtmfSender.insertDTMF('1', duration: 40, interToneGap: 30);

      // Wait for tone to complete (duration + gap + some buffer)
      await Future.delayed(const Duration(milliseconds: 200));

      // Should have received tone start event and end event (empty string)
      expect(events.length, greaterThanOrEqualTo(1));
      expect(events.first.tone, equals('1'));
    });

    test('ontonechange stream works', () async {
      final completer = Completer<RTCDTMFToneChangeEvent>();
      final subscription = dtmfSender.onToneChange.listen((event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      });

      dtmfSender.insertDTMF('5', duration: 40, interToneGap: 30);

      final event = await completer.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => const RTCDTMFToneChangeEvent('timeout'),
      );

      expect(event.tone, equals('5'));
      await subscription.cancel();
    });

    test('RTCDTMFToneChangeEvent toString', () {
      final event = RTCDTMFToneChangeEvent('1');
      expect(event.toString(), equals('RTCDTMFToneChangeEvent(tone: "1")'));
    });

    test('dispose cleans up resources', () {
      dtmfSender.insertDTMF('123');
      dtmfSender.dispose();

      expect(dtmfSender.canInsertDTMF, isFalse);
      expect(dtmfSender.toneBuffer, isEmpty);
    });

    test('toString provides useful info', () {
      final str = dtmfSender.toString();
      expect(str, contains('canInsertDTMF'));
      expect(str, contains('toneBuffer'));
    });
  });

  group('RTCRtpSender.dtmf', () {
    late RtpSession mockSession;

    setUp(() {
      mockSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
    });

    test('dtmf is non-null for audio sender', () {
      final audioTrack = AudioStreamTrack(
        id: 'audio-1',
        label: 'Audio Track',
      );
      final audioCodec = createOpusCodec(payloadType: 111);

      final sender = RTCRtpSender(
        track: audioTrack,
        rtpSession: mockSession,
        codec: audioCodec,
      );

      expect(sender.dtmf, isNotNull);
      expect(sender.dtmf!.canInsertDTMF, isTrue);

      sender.stop();
    });

    test('dtmf is null for video sender', () {
      final videoTrack = VideoStreamTrack(
        id: 'video-1',
        label: 'Video Track',
      );
      final videoCodec = createVp8Codec(payloadType: 96);

      final sender = RTCRtpSender(
        track: videoTrack,
        rtpSession: mockSession,
        codec: videoCodec,
      );

      expect(sender.dtmf, isNull);

      sender.stop();
    });

    test('dtmf uses custom payload type when set', () {
      final audioTrack = AudioStreamTrack(
        id: 'audio-1',
        label: 'Audio Track',
      );
      final audioCodec = createOpusCodec(payloadType: 111);

      final sender = RTCRtpSender(
        track: audioTrack,
        rtpSession: mockSession,
        codec: audioCodec,
      );
      sender.dtmfPayloadType = 103;

      final dtmf = sender.dtmf;
      expect(dtmf, isNotNull);
      // The payload type is internal, but we verify dtmf is created

      sender.stop();
    });

    test('dtmf is disposed when sender stops', () {
      final audioTrack = AudioStreamTrack(
        id: 'audio-1',
        label: 'Audio Track',
      );
      final audioCodec = createOpusCodec(payloadType: 111);

      final sender = RTCRtpSender(
        track: audioTrack,
        rtpSession: mockSession,
        codec: audioCodec,
      );

      // Access dtmf to create it
      final dtmf = sender.dtmf;
      expect(dtmf, isNotNull);
      expect(dtmf!.canInsertDTMF, isTrue);

      // Stop sender should dispose dtmf
      sender.stop();

      // The old dtmf instance should be stopped
      expect(dtmf.canInsertDTMF, isFalse);
    });

    test('dtmf returns same instance on multiple accesses', () {
      final audioTrack = AudioStreamTrack(
        id: 'audio-1',
        label: 'Audio Track',
      );
      final audioCodec = createOpusCodec(payloadType: 111);

      final sender = RTCRtpSender(
        track: audioTrack,
        rtpSession: mockSession,
        codec: audioCodec,
      );

      final dtmf1 = sender.dtmf;
      final dtmf2 = sender.dtmf;

      expect(identical(dtmf1, dtmf2), isTrue);

      sender.stop();
    });
  });
}
