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

  group('RTCRtpSimulcastParameters', () {
    test('fromSdpRid throws for invalid format', () {
      expect(
        () => RTCRtpSimulcastParameters.fromSdpRid('invalid'),
        throwsA(isA<FormatException>()),
      );
    });

    test('toString includes rid and direction', () {
      final param = RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.send,
      );
      final str = param.toString();
      expect(str, contains('high'));
      expect(str, contains('send'));
    });

    test('hashCode is consistent', () {
      final a = RTCRtpSimulcastParameters(rid: 'h', direction: SimulcastDirection.send);
      final b = RTCRtpSimulcastParameters(rid: 'h', direction: SimulcastDirection.send);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('RTCRtpRtxParameters', () {
    test('construction', () {
      final rtx = RTCRtpRtxParameters(ssrc: 12345);
      expect(rtx.ssrc, equals(12345));
    });
  });

  group('RTCRtpCodingParameters', () {
    test('construction with required values', () {
      final coding = RTCRtpCodingParameters(
        ssrc: 11111,
        payloadType: 96,
      );
      expect(coding.ssrc, equals(11111));
      expect(coding.payloadType, equals(96));
      expect(coding.rtx, isNull);
      expect(coding.rid, isNull);
    });

    test('construction with all values', () {
      final coding = RTCRtpCodingParameters(
        ssrc: 11111,
        payloadType: 96,
        rtx: RTCRtpRtxParameters(ssrc: 22222),
        rid: 'high',
        maxBitrate: 2000000,
        scaleResolutionDownBy: 2.0,
      );
      expect(coding.ssrc, equals(11111));
      expect(coding.rtx?.ssrc, equals(22222));
      expect(coding.rid, equals('high'));
      expect(coding.maxBitrate, equals(2000000));
      expect(coding.scaleResolutionDownBy, equals(2.0));
    });
  });

  group('RTCRtpHeaderExtensionParameters', () {
    test('construction', () {
      final ext = RTCRtpHeaderExtensionParameters(
        id: 5,
        uri: 'urn:ietf:params:rtp-hdrext:sdes:mid',
      );
      expect(ext.id, equals(5));
      expect(ext.uri, equals('urn:ietf:params:rtp-hdrext:sdes:mid'));
    });
  });

  group('RTCRtcpParameters', () {
    test('construction with defaults', () {
      final rtcp = RTCRtcpParameters();
      expect(rtcp.cname, isNull);
      expect(rtcp.mux, isFalse);
      expect(rtcp.ssrc, isNull);
    });

    test('construction with all values', () {
      final rtcp = RTCRtcpParameters(
        cname: 'test-cname',
        mux: true,
        ssrc: 12345,
      );
      expect(rtcp.cname, equals('test-cname'));
      expect(rtcp.mux, isTrue);
      expect(rtcp.ssrc, equals(12345));
    });
  });

  group('RTCRtpParameters', () {
    test('construction with defaults', () {
      final params = RTCRtpParameters();
      expect(params.codecs, isEmpty);
      expect(params.headerExtensions, isEmpty);
      expect(params.muxId, isNull);
    });

    test('construction with values', () {
      final params = RTCRtpParameters(
        codecs: [
          RTCRtpCodecParameters(
            payloadType: 96,
            mimeType: 'video/VP8',
            clockRate: 90000,
          ),
        ],
        headerExtensions: [
          RTCRtpHeaderExtensionParameters(id: 1, uri: 'test'),
        ],
        muxId: 'mid-1',
        rtpStreamId: 'stream-1',
        repairedRtpStreamId: 'repair-1',
        rtcp: RTCRtcpParameters(mux: true),
      );
      expect(params.codecs.length, equals(1));
      expect(params.headerExtensions.length, equals(1));
      expect(params.muxId, equals('mid-1'));
      expect(params.rtpStreamId, equals('stream-1'));
      expect(params.repairedRtpStreamId, equals('repair-1'));
      expect(params.rtcp?.mux, isTrue);
    });
  });

  group('RTCRtpReceiveParameters', () {
    test('construction with encodings', () {
      final params = RTCRtpReceiveParameters(
        encodings: [
          RTCRtpCodingParameters(ssrc: 11111, payloadType: 96),
        ],
      );
      expect(params.encodings.length, equals(1));
      expect(params.encodings[0].ssrc, equals(11111));
    });
  });

  group('RTCRtpEncodingParameters', () {
    test('construction with defaults', () {
      final enc = RTCRtpEncodingParameters();
      expect(enc.rid, isNull);
      expect(enc.active, isTrue);
      expect(enc.ssrc, isNull);
      expect(enc.priority, equals(1));
      expect(enc.networkPriority, equals(NetworkPriority.low));
    });

    test('construction with all values', () {
      final enc = RTCRtpEncodingParameters(
        rid: 'high',
        active: false,
        ssrc: 12345,
        rtxSsrc: 54321,
        maxBitrate: 2000000,
        maxFramerate: 30.0,
        scaleResolutionDownBy: 1.0,
        scalabilityMode: 'L1T2',
        priority: 5,
        networkPriority: NetworkPriority.high,
      );
      expect(enc.rid, equals('high'));
      expect(enc.active, isFalse);
      expect(enc.ssrc, equals(12345));
      expect(enc.rtxSsrc, equals(54321));
      expect(enc.maxBitrate, equals(2000000));
      expect(enc.maxFramerate, equals(30.0));
      expect(enc.scaleResolutionDownBy, equals(1.0));
      expect(enc.scalabilityMode, equals('L1T2'));
      expect(enc.priority, equals(5));
      expect(enc.networkPriority, equals(NetworkPriority.high));
    });

    test('copyWith creates modified copy', () {
      final original = RTCRtpEncodingParameters(
        rid: 'high',
        active: true,
        ssrc: 12345,
      );
      final copy = original.copyWith(
        active: false,
        maxBitrate: 1000000,
      );

      expect(copy.rid, equals('high'));
      expect(copy.active, isFalse);
      expect(copy.ssrc, equals(12345));
      expect(copy.maxBitrate, equals(1000000));
    });

    test('equality', () {
      final a = RTCRtpEncodingParameters(rid: 'high', active: true, ssrc: 123);
      final b = RTCRtpEncodingParameters(rid: 'high', active: true, ssrc: 123);
      final c = RTCRtpEncodingParameters(rid: 'low', active: true, ssrc: 123);

      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('hashCode is consistent', () {
      final a = RTCRtpEncodingParameters(rid: 'high');
      final b = RTCRtpEncodingParameters(rid: 'high');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes key info', () {
      final enc = RTCRtpEncodingParameters(
        rid: 'high',
        active: true,
        ssrc: 12345,
      );
      final str = enc.toString();
      expect(str, contains('high'));
      expect(str, contains('active: true'));
      expect(str, contains('12345'));
    });
  });

  group('NetworkPriority', () {
    test('enum values', () {
      expect(NetworkPriority.values, contains(NetworkPriority.veryLow));
      expect(NetworkPriority.values, contains(NetworkPriority.low));
      expect(NetworkPriority.values, contains(NetworkPriority.medium));
      expect(NetworkPriority.values, contains(NetworkPriority.high));
    });
  });

  group('DegradationPreference', () {
    test('enum values', () {
      expect(DegradationPreference.values, contains(DegradationPreference.maintainFramerate));
      expect(DegradationPreference.values, contains(DegradationPreference.maintainResolution));
      expect(DegradationPreference.values, contains(DegradationPreference.balanced));
    });
  });

  group('MediaDirection', () {
    test('enum values', () {
      expect(MediaDirection.values, contains(MediaDirection.sendrecv));
      expect(MediaDirection.values, contains(MediaDirection.sendonly));
      expect(MediaDirection.values, contains(MediaDirection.recvonly));
      expect(MediaDirection.values, contains(MediaDirection.inactive));
    });
  });

  group('RTCRtpSendParameters', () {
    test('construction with required values', () {
      final params = RTCRtpSendParameters(
        transactionId: 'tx-123',
        encodings: [RTCRtpEncodingParameters(rid: 'high')],
      );
      expect(params.transactionId, equals('tx-123'));
      expect(params.encodings.length, equals(1));
      expect(params.degradationPreference, equals(DegradationPreference.balanced));
    });

    test('construction with all values', () {
      final params = RTCRtpSendParameters(
        transactionId: 'tx-123',
        encodings: [
          RTCRtpEncodingParameters(rid: 'high'),
          RTCRtpEncodingParameters(rid: 'low'),
        ],
        degradationPreference: DegradationPreference.maintainFramerate,
        codecs: [
          RTCRtpCodecParameters(
            payloadType: 96,
            mimeType: 'video/VP8',
            clockRate: 90000,
          ),
        ],
        muxId: 'mid-1',
      );
      expect(params.transactionId, equals('tx-123'));
      expect(params.encodings.length, equals(2));
      expect(params.degradationPreference, equals(DegradationPreference.maintainFramerate));
      expect(params.codecs.length, equals(1));
      expect(params.muxId, equals('mid-1'));
    });

    test('copyWith preserves transactionId', () {
      final original = RTCRtpSendParameters(
        transactionId: 'tx-123',
        encodings: [RTCRtpEncodingParameters(rid: 'high')],
      );
      final copy = original.copyWith(
        degradationPreference: DegradationPreference.maintainResolution,
      );

      expect(copy.transactionId, equals('tx-123'));
      expect(copy.degradationPreference, equals(DegradationPreference.maintainResolution));
    });

    test('copyWith updates specified values', () {
      final original = RTCRtpSendParameters(
        transactionId: 'tx-123',
        encodings: [RTCRtpEncodingParameters(rid: 'high')],
        muxId: 'mid-1',
      );
      final newEncodings = [RTCRtpEncodingParameters(rid: 'low')];
      final copy = original.copyWith(encodings: newEncodings);

      expect(copy.encodings.length, equals(1));
      expect(copy.encodings[0].rid, equals('low'));
      expect(copy.muxId, equals('mid-1'));
    });

    test('toString includes transactionId', () {
      final params = RTCRtpSendParameters(
        transactionId: 'tx-123',
        encodings: [RTCRtpEncodingParameters(rid: 'high')],
      );
      final str = params.toString();
      expect(str, contains('tx-123'));
      expect(str, contains('encodings: 1'));
    });
  });
}
