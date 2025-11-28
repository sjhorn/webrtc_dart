import 'package:test/test.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';

void main() {
  group('RtpCodecParameters', () {
    test('creates Opus codec with defaults', () {
      final opus = createOpusCodec();

      expect(opus.mimeType, 'audio/opus');
      expect(opus.clockRate, 48000);
      expect(opus.channels, 2);
      expect(opus.isAudio, isTrue);
      expect(opus.isVideo, isFalse);
      expect(opus.codecName, 'opus');
    });

    test('creates Opus codec with custom parameters', () {
      final opus = createOpusCodec(
        payloadType: 111,
        clockRate: 24000,
        channels: 1,
      );

      expect(opus.payloadType, 111);
      expect(opus.clockRate, 24000);
      expect(opus.channels, 1);
    });

    test('creates PCMU codec', () {
      final pcmu = createPcmuCodec();

      expect(pcmu.mimeType, 'audio/PCMU');
      expect(pcmu.clockRate, 8000);
      expect(pcmu.channels, 1);
      expect(pcmu.payloadType, 0); // Static payload type
      expect(pcmu.isAudio, isTrue);
    });

    test('creates VP8 codec with RTCP feedback', () {
      final vp8 = createVp8Codec();

      expect(vp8.mimeType, 'video/VP8');
      expect(vp8.clockRate, 90000);
      expect(vp8.isVideo, isTrue);
      expect(vp8.isAudio, isFalse);
      expect(vp8.rtcpFeedback.length, 3);
      expect(vp8.codecName, 'VP8');
    });

    test('creates VP9 codec', () {
      final vp9 = createVp9Codec(payloadType: 96);

      expect(vp9.mimeType, 'video/VP9');
      expect(vp9.clockRate, 90000);
      expect(vp9.payloadType, 96);
    });

    test('creates H.264 codec with parameters', () {
      final h264 = createH264Codec();

      expect(h264.mimeType, 'video/H264');
      expect(h264.clockRate, 90000);
      expect(h264.parameters, contains('profile-level-id=42e01f'));
      expect(h264.parameters, contains('packetization-mode=1'));
    });

    test('supported audio codecs list', () {
      expect(supportedAudioCodecs.length, 2);
      expect(supportedAudioCodecs[0].mimeType, 'audio/opus');
      expect(supportedAudioCodecs[1].mimeType, 'audio/PCMU');
    });

    test('supported video codecs list', () {
      expect(supportedVideoCodecs.length, 3);
      expect(supportedVideoCodecs.map((c) => c.codecName),
          containsAll(['VP8', 'VP9', 'H264']));
    });

    test('supported codecs list contains all', () {
      expect(supportedCodecs.length, 5); // 2 audio + 3 video
    });
  });

  group('RtcpFeedback', () {
    test('creates NACK feedback', () {
      expect(RtcpFeedbackTypes.nack.type, 'nack');
      expect(RtcpFeedbackTypes.nack.parameter, isNull);
      expect(RtcpFeedbackTypes.nack.toString(), 'nack');
    });

    test('creates PLI feedback', () {
      expect(RtcpFeedbackTypes.pli.type, 'nack');
      expect(RtcpFeedbackTypes.pli.parameter, 'pli');
      expect(RtcpFeedbackTypes.pli.toString(), 'nack pli');
    });

    test('creates REMB feedback', () {
      expect(RtcpFeedbackTypes.remb.type, 'goog-remb');
    });

    test('creates transport CC feedback', () {
      expect(RtcpFeedbackTypes.transportCC.type, 'transport-cc');
    });

    test('custom feedback with parameter', () {
      final feedback = RtcpFeedback(type: 'custom', parameter: 'param');

      expect(feedback.toString(), 'custom param');
    });
  });
}
