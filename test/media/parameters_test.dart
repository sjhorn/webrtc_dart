import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/parameters.dart';

void main() {
  group('RTCRtpSimulcastParameters', () {
    test('parse send direction', () {
      final param = RTCRtpSimulcastParameters.fromSdpRid('high send');
      expect(param.rid, equals('high'));
      expect(param.direction, equals(SimulcastDirection.send));
    });

    test('parse recv direction', () {
      final param = RTCRtpSimulcastParameters.fromSdpRid('low recv');
      expect(param.rid, equals('low'));
      expect(param.direction, equals(SimulcastDirection.recv));
    });

    test('serialize to SDP', () {
      final param = RTCRtpSimulcastParameters(
        rid: 'mid',
        direction: SimulcastDirection.send,
      );
      expect(param.toSdpRid(), equals('mid send'));
    });

    test('round-trip', () {
      final original = RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.recv,
      );
      final sdp = original.toSdpRid();
      final parsed = RTCRtpSimulcastParameters.fromSdpRid(sdp);
      expect(parsed, equals(original));
    });

    test('equality', () {
      final a = RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.send,
      );
      final b = RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.send,
      );
      final c = RTCRtpSimulcastParameters(
        rid: 'low',
        direction: SimulcastDirection.send,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('RTCRtpCodecParameters', () {
    test('get name from mimeType', () {
      final codec = RTCRtpCodecParameters(
        payloadType: 96,
        mimeType: 'video/VP8',
        clockRate: 90000,
      );
      expect(codec.name, equals('VP8'));
      expect(codec.contentType, equals('video'));
    });

    test('str representation', () {
      final codec = RTCRtpCodecParameters(
        payloadType: 111,
        mimeType: 'audio/opus',
        clockRate: 48000,
        channels: 2,
      );
      expect(codec.str, equals('opus/48000/2'));
    });

    test('str without channels', () {
      final codec = RTCRtpCodecParameters(
        payloadType: 96,
        mimeType: 'video/H264',
        clockRate: 90000,
      );
      expect(codec.str, equals('H264/90000'));
    });
  });

  group('RTCRtcpFeedback', () {
    test('equality with parameter', () {
      final a = RTCRtcpFeedback(type: 'nack', parameter: 'pli');
      final b = RTCRtcpFeedback(type: 'nack', parameter: 'pli');
      expect(a, equals(b));
    });

    test('equality without parameter', () {
      final a = RTCRtcpFeedback(type: 'nack');
      final b = RTCRtcpFeedback(type: 'nack');
      expect(a, equals(b));
    });
  });
}
