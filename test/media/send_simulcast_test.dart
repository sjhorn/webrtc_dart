import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/rtc_rtp_transceiver.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/rtp/rtp_session.dart';
import 'package:webrtc_dart/src/codec/codec_parameters.dart';

void main() {
  group('RTCRtpEncodingParameters', () {
    test('creates with default values', () {
      final encoding = RTCRtpEncodingParameters();

      expect(encoding.rid, isNull);
      expect(encoding.active, isTrue);
      expect(encoding.ssrc, isNull);
      expect(encoding.maxBitrate, isNull);
      expect(encoding.scaleResolutionDownBy, isNull);
      expect(encoding.priority, equals(1));
      expect(encoding.networkPriority, equals(NetworkPriority.low));
    });

    test('creates with custom values', () {
      final encoding = RTCRtpEncodingParameters(
        rid: 'high',
        active: true,
        ssrc: 12345,
        maxBitrate: 2500000,
        maxFramerate: 30.0,
        scaleResolutionDownBy: 1.0,
        scalabilityMode: 'L1T2',
        priority: 2,
        networkPriority: NetworkPriority.high,
      );

      expect(encoding.rid, equals('high'));
      expect(encoding.active, isTrue);
      expect(encoding.ssrc, equals(12345));
      expect(encoding.maxBitrate, equals(2500000));
      expect(encoding.maxFramerate, equals(30.0));
      expect(encoding.scaleResolutionDownBy, equals(1.0));
      expect(encoding.scalabilityMode, equals('L1T2'));
      expect(encoding.priority, equals(2));
      expect(encoding.networkPriority, equals(NetworkPriority.high));
    });

    test('copyWith creates modified copy', () {
      final original = RTCRtpEncodingParameters(
        rid: 'high',
        active: true,
        maxBitrate: 2500000,
      );

      final modified = original.copyWith(
        active: false,
        maxBitrate: 1000000,
      );

      // Original unchanged
      expect(original.active, isTrue);
      expect(original.maxBitrate, equals(2500000));

      // Modified has changes
      expect(modified.rid, equals('high')); // preserved
      expect(modified.active, isFalse);
      expect(modified.maxBitrate, equals(1000000));
    });

    test('equality works correctly', () {
      final enc1 = RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000);
      final enc2 = RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000);
      final enc3 = RTCRtpEncodingParameters(rid: 'low', maxBitrate: 500000);

      expect(enc1, equals(enc2));
      expect(enc1, isNot(equals(enc3)));
    });

    test('toString provides useful info', () {
      final encoding = RTCRtpEncodingParameters(
        rid: 'mid',
        ssrc: 99999,
        maxBitrate: 1000000,
        scaleResolutionDownBy: 2.0,
      );

      final str = encoding.toString();
      expect(str, contains('mid'));
      expect(str, contains('99999'));
      expect(str, contains('1000000'));
      expect(str, contains('2.0'));
    });
  });

  group('RTCRtpSendParameters', () {
    test('creates with encodings', () {
      final params = RTCRtpSendParameters(
        transactionId: 'tx_123',
        encodings: [
          RTCRtpEncodingParameters(rid: 'high'),
          RTCRtpEncodingParameters(rid: 'low'),
        ],
      );

      expect(params.transactionId, equals('tx_123'));
      expect(params.encodings.length, equals(2));
      expect(params.encodings[0].rid, equals('high'));
      expect(params.encodings[1].rid, equals('low'));
      expect(
          params.degradationPreference, equals(DegradationPreference.balanced));
    });

    test('copyWith preserves transactionId', () {
      final original = RTCRtpSendParameters(
        transactionId: 'tx_456',
        encodings: [RTCRtpEncodingParameters(rid: 'test')],
      );

      final modified = original.copyWith(
        degradationPreference: DegradationPreference.maintainFramerate,
      );

      expect(modified.transactionId, equals('tx_456'));
      expect(modified.degradationPreference,
          equals(DegradationPreference.maintainFramerate));
    });
  });

  group('RtpSender simulcast', () {
    late RtpSession rtpSession;

    setUp(() {
      rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
    });

    test('creates with default single encoding', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
      );

      expect(sender.encodings.length, equals(1));
      expect(sender.isSimulcast, isFalse);
      expect(sender.encodings[0].ssrc, isNotNull);
      expect(sender.encodings[0].rtxSsrc, isNotNull);
    });

    test('creates with multiple simulcast encodings', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000),
          RTCRtpEncodingParameters(
              rid: 'mid', maxBitrate: 500000, scaleResolutionDownBy: 2.0),
          RTCRtpEncodingParameters(
              rid: 'low', maxBitrate: 150000, scaleResolutionDownBy: 4.0),
        ],
      );

      expect(sender.encodings.length, equals(3));
      expect(sender.isSimulcast, isTrue);

      expect(sender.encodings[0].rid, equals('high'));
      expect(sender.encodings[0].maxBitrate, equals(2500000));
      expect(sender.encodings[0].ssrc, isNotNull);

      expect(sender.encodings[1].rid, equals('mid'));
      expect(sender.encodings[1].scaleResolutionDownBy, equals(2.0));

      expect(sender.encodings[2].rid, equals('low'));
      expect(sender.encodings[2].scaleResolutionDownBy, equals(4.0));
    });

    test('getParameters returns current encodings', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
          RTCRtpEncodingParameters(rid: 'low'),
        ],
      );

      final params = sender.getParameters();

      expect(params.transactionId, isNotEmpty);
      expect(params.encodings.length, equals(2));
      expect(params.encodings[0].rid, equals('high'));
      expect(params.encodings[1].rid, equals('low'));
      expect(params.codecs.length, equals(1));
      expect(params.codecs[0].mimeType, equals('video/VP8'));
    });

    test('setParameters updates mutable properties', () async {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(
              rid: 'high', active: true, maxBitrate: 2500000),
          RTCRtpEncodingParameters(
              rid: 'low', active: true, maxBitrate: 500000),
        ],
      );

      final params = sender.getParameters();

      // Modify encodings
      params.encodings[0].active = false;
      params.encodings[1].maxBitrate = 300000;

      await sender.setParameters(params);

      expect(sender.encodings[0].active, isFalse);
      expect(sender.encodings[1].maxBitrate, equals(300000));
    });

    test('setParameters rejects invalid transaction ID', () async {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
      );

      final params = sender.getParameters();

      // Create params with wrong transaction ID
      final wrongParams = RTCRtpSendParameters(
        transactionId: 'wrong_id',
        encodings: params.encodings,
      );

      expect(
        () => sender.setParameters(wrongParams),
        throwsA(isA<StateError>()),
      );
    });

    test('setParameters rejects changed encoding count', () async {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
        ],
      );

      final params = sender.getParameters();

      // Try to add another encoding
      final wrongParams = RTCRtpSendParameters(
        transactionId: params.transactionId,
        encodings: [
          params.encodings[0],
          RTCRtpEncodingParameters(rid: 'new'),
        ],
      );

      expect(
        () => sender.setParameters(wrongParams),
        throwsA(isA<StateError>()),
      );
    });

    test('setParameters rejects changed RID', () async {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
        ],
      );

      final params = sender.getParameters();

      // Try to change RID
      final wrongParams = RTCRtpSendParameters(
        transactionId: params.transactionId,
        encodings: [
          RTCRtpEncodingParameters(
              rid: 'changed', active: params.encodings[0].active),
        ],
      );

      expect(
        () => sender.setParameters(wrongParams),
        throwsA(isA<StateError>()),
      );
    });

    test('getEncodingByRid returns correct encoding', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000),
          RTCRtpEncodingParameters(rid: 'mid', maxBitrate: 500000),
          RTCRtpEncodingParameters(rid: 'low', maxBitrate: 150000),
        ],
      );

      final mid = sender.getEncodingByRid('mid');
      expect(mid, isNotNull);
      expect(mid!.maxBitrate, equals(500000));

      final notFound = sender.getEncodingByRid('nonexistent');
      expect(notFound, isNull);
    });

    test('setEncodingActive toggles encoding', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: true),
          RTCRtpEncodingParameters(rid: 'low', active: true),
        ],
      );

      expect(sender.activeEncodings.length, equals(2));

      sender.setEncodingActive('high', false);

      expect(sender.activeEncodings.length, equals(1));
      expect(sender.activeEncodings[0].rid, equals('low'));
    });

    test('activeEncodings returns only active ones', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: true),
          RTCRtpEncodingParameters(rid: 'mid', active: false),
          RTCRtpEncodingParameters(rid: 'low', active: true),
        ],
      );

      final active = sender.activeEncodings;
      expect(active.length, equals(2));
      expect(active[0].rid, equals('high'));
      expect(active[1].rid, equals('low'));
    });

    test('each encoding gets unique SSRC', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
          RTCRtpEncodingParameters(rid: 'mid'),
          RTCRtpEncodingParameters(rid: 'low'),
        ],
      );

      final ssrcs = sender.encodings.map((e) => e.ssrc).toSet();
      final rtxSsrcs = sender.encodings.map((e) => e.rtxSsrc).toSet();

      // All SSRCs should be unique
      expect(ssrcs.length, equals(3));
      expect(rtxSsrcs.length, equals(3));

      // SSRCs and RTX SSRCs should be different
      expect(ssrcs.intersection(rtxSsrcs), isEmpty);
    });

    test('toString shows encoding info', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
          RTCRtpEncodingParameters(rid: 'low'),
        ],
      );

      final str = sender.toString();
      expect(str, contains('high'));
      expect(str, contains('low'));
    });

    test('selectLayer enables only one layer', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: true),
          RTCRtpEncodingParameters(rid: 'mid', active: true),
          RTCRtpEncodingParameters(rid: 'low', active: true),
        ],
      );

      expect(sender.activeEncodings.length, equals(3));

      final found = sender.selectLayer('mid');
      expect(found, isTrue);
      expect(sender.activeEncodings.length, equals(1));
      expect(sender.activeEncodings[0].rid, equals('mid'));
    });

    test('selectLayer returns false for unknown RID', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'),
        ],
      );

      final found = sender.selectLayer('nonexistent');
      expect(found, isFalse);
    });

    test('enableAllLayers enables all layers', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: false),
          RTCRtpEncodingParameters(rid: 'mid', active: false),
          RTCRtpEncodingParameters(rid: 'low', active: false),
        ],
      );

      expect(sender.activeEncodings.length, equals(0));

      sender.enableAllLayers();

      expect(sender.activeEncodings.length, equals(3));
    });

    test('disableAllLayers disables all layers', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: true),
          RTCRtpEncodingParameters(rid: 'mid', active: true),
          RTCRtpEncodingParameters(rid: 'low', active: true),
        ],
      );

      expect(sender.activeEncodings.length, equals(3));

      sender.disableAllLayers();

      expect(sender.activeEncodings.length, equals(0));
    });

    test('selectLayersByMaxBitrate enables appropriate layers', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(
              rid: 'high', maxBitrate: 2500000, active: true),
          RTCRtpEncodingParameters(
              rid: 'mid', maxBitrate: 500000, active: true),
          RTCRtpEncodingParameters(
              rid: 'low', maxBitrate: 150000, active: true),
        ],
      );

      // Enable only layers <= 500kbps
      final enabled = sender.selectLayersByMaxBitrate(500000);

      expect(enabled, equals(2));
      expect(sender.getEncodingByRid('high')!.active, isFalse);
      expect(sender.getEncodingByRid('mid')!.active, isTrue);
      expect(sender.getEncodingByRid('low')!.active, isTrue);
    });

    test('selectLayersByMaxBitrate handles null maxBitrate', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'), // no maxBitrate
          RTCRtpEncodingParameters(rid: 'low', maxBitrate: 150000),
        ],
      );

      final enabled = sender.selectLayersByMaxBitrate(200000);

      // Both enabled - null maxBitrate is treated as "no limit"
      expect(enabled, equals(2));
    });

    test('selectLayersByMinScale enables lower resolution layers', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(
              rid: 'high', scaleResolutionDownBy: 1.0, active: true),
          RTCRtpEncodingParameters(
              rid: 'mid', scaleResolutionDownBy: 2.0, active: true),
          RTCRtpEncodingParameters(
              rid: 'low', scaleResolutionDownBy: 4.0, active: true),
        ],
      );

      // Enable only half-resolution or lower (scale >= 2.0)
      final enabled = sender.selectLayersByMinScale(2.0);

      expect(enabled, equals(2));
      expect(sender.getEncodingByRid('high')!.active, isFalse);
      expect(sender.getEncodingByRid('mid')!.active, isTrue);
      expect(sender.getEncodingByRid('low')!.active, isTrue);
    });

    test('selectLayersByMinScale handles null scaleResolutionDownBy', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high'), // no scale = 1.0
          RTCRtpEncodingParameters(rid: 'low', scaleResolutionDownBy: 4.0),
        ],
      );

      final enabled = sender.selectLayersByMinScale(2.0);

      // Only low enabled (scale 4.0 >= 2.0), high disabled (default 1.0 < 2.0)
      expect(enabled, equals(1));
      expect(sender.getEncodingByRid('high')!.active, isFalse);
      expect(sender.getEncodingByRid('low')!.active, isTrue);
    });

    test('layerStates returns correct map', () {
      final sender = RtpSender(
        rtpSession: rtpSession,
        codec: createVp8Codec(payloadType: 96),
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', active: true),
          RTCRtpEncodingParameters(rid: 'mid', active: false),
          RTCRtpEncodingParameters(rid: 'low', active: true),
        ],
      );

      final states = sender.layerStates;

      expect(states['high'], isTrue);
      expect(states['mid'], isFalse);
      expect(states['low'], isTrue);
      expect(states.length, equals(3));
    });
  });

  group('createVideoTransceiver with simulcast', () {
    late RtpSession rtpSession;

    setUp(() {
      rtpSession = RtpSession(
        localSsrc: 12345,
        onSendRtp: (_) async {},
        onSendRtcp: (_) async {},
      );
    });

    test('creates transceiver with simulcast encodings', () {
      final track = VideoStreamTrack(id: 'test_video', label: 'Test');

      final transceiver = createVideoTransceiver(
        mid: '1',
        rtpSession: rtpSession,
        sendTrack: track,
        sendEncodings: [
          RTCRtpEncodingParameters(rid: 'high', maxBitrate: 2500000),
          RTCRtpEncodingParameters(
              rid: 'mid', maxBitrate: 500000, scaleResolutionDownBy: 2.0),
          RTCRtpEncodingParameters(
              rid: 'low', maxBitrate: 150000, scaleResolutionDownBy: 4.0),
        ],
      );

      expect(transceiver.sender.isSimulcast, isTrue);
      expect(transceiver.sender.encodings.length, equals(3));
      expect(transceiver.sender.mid, equals('1'));
    });

    test('creates transceiver without simulcast', () {
      final transceiver = createVideoTransceiver(
        mid: '0',
        rtpSession: rtpSession,
      );

      expect(transceiver.sender.isSimulcast, isFalse);
      expect(transceiver.sender.encodings.length, equals(1));
    });
  });

  group('DegradationPreference', () {
    test('has all expected values', () {
      expect(DegradationPreference.values.length, equals(3));
      expect(DegradationPreference.values,
          contains(DegradationPreference.maintainFramerate));
      expect(DegradationPreference.values,
          contains(DegradationPreference.maintainResolution));
      expect(DegradationPreference.values,
          contains(DegradationPreference.balanced));
    });
  });

  group('NetworkPriority', () {
    test('has all expected values', () {
      expect(NetworkPriority.values.length, equals(4));
      expect(NetworkPriority.values, contains(NetworkPriority.veryLow));
      expect(NetworkPriority.values, contains(NetworkPriority.low));
      expect(NetworkPriority.values, contains(NetworkPriority.medium));
      expect(NetworkPriority.values, contains(NetworkPriority.high));
    });
  });
}
