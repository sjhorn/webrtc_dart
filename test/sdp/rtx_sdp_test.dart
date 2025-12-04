/// RTX SDP Tests
///
/// Tests for parsing and generating RTX-related SDP attributes.
library;

import 'package:test/test.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/sdp/rtx_sdp.dart';

void main() {
  group('RtpMapInfo', () {
    test('parses simple rtpmap', () {
      final info = SdpMediaRtxExtension.parseRtpMap('96 VP8/90000');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(96));
      expect(info.codecName, equals('VP8'));
      expect(info.clockRate, equals(90000));
      expect(info.channels, isNull);
    });

    test('parses rtpmap with channels', () {
      final info = SdpMediaRtxExtension.parseRtpMap('111 opus/48000/2');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(111));
      expect(info.codecName, equals('opus'));
      expect(info.clockRate, equals(48000));
      expect(info.channels, equals(2));
    });

    test('parses rtx rtpmap', () {
      final info = SdpMediaRtxExtension.parseRtpMap('97 rtx/90000');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(97));
      expect(info.codecName, equals('rtx'));
      expect(info.clockRate, equals(90000));
      expect(info.isRtx, isTrue);
    });

    test('returns null for invalid rtpmap', () {
      expect(SdpMediaRtxExtension.parseRtpMap('invalid'), isNull);
      expect(SdpMediaRtxExtension.parseRtpMap('abc VP8/90000'), isNull);
    });

    test('serializes rtpmap', () {
      final info = RtpMapInfo(
        payloadType: 96,
        codecName: 'VP8',
        clockRate: 90000,
      );
      expect(info.serialize(), equals('96 VP8/90000'));
    });

    test('serializes rtpmap with channels', () {
      final info = RtpMapInfo(
        payloadType: 111,
        codecName: 'opus',
        clockRate: 48000,
        channels: 2,
      );
      expect(info.serialize(), equals('111 opus/48000/2'));
    });
  });

  group('FmtpInfo', () {
    test('parses fmtp with apt', () {
      final info = SdpMediaRtxExtension.parseFmtp('97 apt=96');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(97));
      expect(info.parameters['apt'], equals('96'));
      expect(info.apt, equals(96));
    });

    test('parses fmtp with multiple parameters', () {
      final info = SdpMediaRtxExtension.parseFmtp(
          '96 profile-level-id=42e01f;level-asymmetry-allowed=1');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(96));
      expect(info.parameters['profile-level-id'], equals('42e01f'));
      expect(info.parameters['level-asymmetry-allowed'], equals('1'));
    });

    test('parses fmtp with space-separated parameters', () {
      final info = SdpMediaRtxExtension.parseFmtp('111 minptime=10 useinbandfec=1');
      expect(info, isNotNull);
      expect(info!.payloadType, equals(111));
      expect(info.parameters['minptime'], equals('10'));
      expect(info.parameters['useinbandfec'], equals('1'));
    });

    test('returns null for invalid fmtp', () {
      expect(SdpMediaRtxExtension.parseFmtp('invalid'), isNull);
    });

    test('serializes fmtp', () {
      final info = FmtpInfo(
        payloadType: 97,
        parameters: {'apt': '96'},
      );
      expect(info.serialize(), equals('97 apt=96'));
    });
  });

  group('SsrcGroup', () {
    test('parses FID ssrc-group', () {
      final group = SsrcGroup.parse('FID 12345678 87654321');
      expect(group.semantics, equals('FID'));
      expect(group.ssrcs, equals([12345678, 87654321]));
    });

    test('parses SIM ssrc-group', () {
      final group = SsrcGroup.parse('SIM 111 222 333');
      expect(group.semantics, equals('SIM'));
      expect(group.ssrcs, equals([111, 222, 333]));
    });

    test('throws on invalid ssrc-group', () {
      expect(() => SsrcGroup.parse('FID'), throwsFormatException);
    });

    test('serializes ssrc-group', () {
      final group = SsrcGroup(semantics: 'FID', ssrcs: [12345678, 87654321]);
      expect(group.serialize(), equals('FID 12345678 87654321'));
    });
  });

  group('SdpMedia RTX parsing', () {
    test('extracts rtpmap entries', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'rtpmap', value: '96 VP8/90000'),
        SdpAttribute(key: 'rtpmap', value: '97 rtx/90000'),
      ]);

      final rtpMaps = media.getRtpMaps();
      expect(rtpMaps.length, equals(2));
      expect(rtpMaps[0].codecName, equals('VP8'));
      expect(rtpMaps[1].codecName, equals('rtx'));
    });

    test('extracts fmtp entries', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'fmtp', value: '97 apt=96'),
        SdpAttribute(key: 'fmtp', value: '96 max-fr=30'),
      ]);

      final fmtps = media.getFmtps();
      expect(fmtps.length, equals(2));
      expect(fmtps[0].payloadType, equals(97));
      expect(fmtps[0].apt, equals(96));
    });

    test('extracts ssrc-group entries', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'ssrc-group', value: 'FID 12345678 87654321'),
      ]);

      final groups = media.getSsrcGroups();
      expect(groups.length, equals(1));
      expect(groups[0].semantics, equals('FID'));
      expect(groups[0].ssrcs, equals([12345678, 87654321]));
    });

    test('extracts ssrc info', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'ssrc', value: '12345678 cname:test@example.com'),
        SdpAttribute(key: 'ssrc', value: '12345678 msid:stream track'),
        SdpAttribute(key: 'ssrc', value: '87654321 cname:test@example.com'),
      ]);

      final ssrcs = media.getSsrcInfos();
      expect(ssrcs.length, equals(2));

      final ssrc1 = ssrcs.firstWhere((s) => s.ssrc == 12345678);
      expect(ssrc1.cname, equals('test@example.com'));
      expect(ssrc1.msid, equals('stream track'));

      final ssrc2 = ssrcs.firstWhere((s) => s.ssrc == 87654321);
      expect(ssrc2.cname, equals('test@example.com'));
    });

    test('gets RTX codec mapping', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'rtpmap', value: '96 VP8/90000'),
        SdpAttribute(key: 'rtpmap', value: '97 rtx/90000'),
        SdpAttribute(key: 'fmtp', value: '97 apt=96'),
      ]);

      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs.length, equals(1));
      expect(rtxCodecs[96], isNotNull);
      expect(rtxCodecs[96]!.rtxPayloadType, equals(97));
      expect(rtxCodecs[96]!.associatedPayloadType, equals(96));
    });

    test('gets RTX SSRC mapping from FID group', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'ssrc-group', value: 'FID 12345678 87654321'),
      ]);

      final mapping = media.getRtxSsrcMapping();
      expect(mapping.length, equals(1));
      expect(mapping[12345678], equals(87654321));
    });

    test('handles multiple RTX codecs', () {
      final media = _createVideoMedia([
        SdpAttribute(key: 'rtpmap', value: '96 VP8/90000'),
        SdpAttribute(key: 'rtpmap', value: '97 rtx/90000'),
        SdpAttribute(key: 'rtpmap', value: '98 VP9/90000'),
        SdpAttribute(key: 'rtpmap', value: '99 rtx/90000'),
        SdpAttribute(key: 'fmtp', value: '97 apt=96'),
        SdpAttribute(key: 'fmtp', value: '99 apt=98'),
      ]);

      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs.length, equals(2));
      expect(rtxCodecs[96]!.rtxPayloadType, equals(97));
      expect(rtxCodecs[98]!.rtxPayloadType, equals(99));
    });
  });

  group('RtxSdpBuilder', () {
    test('creates rtpmap for RTX', () {
      final attr = RtxSdpBuilder.createRtxRtpMap(97);
      expect(attr.key, equals('rtpmap'));
      expect(attr.value, equals('97 rtx/90000'));
    });

    test('creates rtpmap for RTX with custom clock rate', () {
      final attr = RtxSdpBuilder.createRtxRtpMap(97, clockRate: 48000);
      expect(attr.value, equals('97 rtx/48000'));
    });

    test('creates fmtp for RTX with apt', () {
      final attr = RtxSdpBuilder.createRtxFmtp(97, 96);
      expect(attr.key, equals('fmtp'));
      expect(attr.value, equals('97 apt=96'));
    });

    test('creates ssrc-group FID', () {
      final attr = RtxSdpBuilder.createSsrcGroupFid(12345678, 87654321);
      expect(attr.key, equals('ssrc-group'));
      expect(attr.value, equals('FID 12345678 87654321'));
    });

    test('creates ssrc cname', () {
      final attr = RtxSdpBuilder.createSsrcCname(12345678, 'test@example.com');
      expect(attr.key, equals('ssrc'));
      expect(attr.value, equals('12345678 cname:test@example.com'));
    });

    test('creates ssrc msid', () {
      final attr = RtxSdpBuilder.createSsrcMsid(12345678, 'stream-id', 'track-id');
      expect(attr.key, equals('ssrc'));
      expect(attr.value, equals('12345678 msid:stream-id track-id'));
    });

    test('generates all RTX attributes', () {
      final attrs = RtxSdpBuilder.generateRtxAttributes(
        originalPayloadType: 96,
        rtxPayloadType: 97,
        originalSsrc: 12345678,
        rtxSsrc: 87654321,
        cname: 'test@example.com',
      );

      expect(attrs.length, equals(4));

      // rtpmap
      expect(attrs[0].key, equals('rtpmap'));
      expect(attrs[0].value, equals('97 rtx/90000'));

      // fmtp
      expect(attrs[1].key, equals('fmtp'));
      expect(attrs[1].value, equals('97 apt=96'));

      // ssrc-group
      expect(attrs[2].key, equals('ssrc-group'));
      expect(attrs[2].value, equals('FID 12345678 87654321'));

      // ssrc cname
      expect(attrs[3].key, equals('ssrc'));
      expect(attrs[3].value, equals('87654321 cname:test@example.com'));
    });

    test('generates RTX attributes with msid', () {
      final attrs = RtxSdpBuilder.generateRtxAttributes(
        originalPayloadType: 96,
        rtxPayloadType: 97,
        originalSsrc: 12345678,
        rtxSsrc: 87654321,
        cname: 'test@example.com',
        streamId: 'my-stream',
        trackId: 'my-track',
      );

      expect(attrs.length, equals(5));
      expect(attrs[4].key, equals('ssrc'));
      expect(attrs[4].value, equals('87654321 msid:my-stream my-track'));
    });
  });

  group('Real SDP parsing', () {
    test('parses Chrome-style video SDP with RTX', () {
      const sdp = '''
v=0
o=- 123456789 2 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96 97
c=IN IP4 0.0.0.0
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=fmtp:97 apt=96
a=ssrc-group:FID 12345678 87654321
a=ssrc:12345678 cname:user@example.com
a=ssrc:87654321 cname:user@example.com
a=mid:0
''';

      final message = SdpMessage.parse(sdp);
      expect(message.mediaDescriptions.length, equals(1));

      final media = message.mediaDescriptions[0];
      expect(media.type, equals('video'));

      // Check RTX codec
      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs.length, equals(1));
      expect(rtxCodecs[96]!.rtxPayloadType, equals(97));

      // Check SSRC mapping
      final ssrcMapping = media.getRtxSsrcMapping();
      expect(ssrcMapping[12345678], equals(87654321));

      // Check SSRC info
      final ssrcs = media.getSsrcInfos();
      expect(ssrcs.length, equals(2));
      expect(ssrcs.every((s) => s.cname == 'user@example.com'), isTrue);
    });

    test('parses SDP with multiple codecs and RTX', () {
      const sdp = '''
v=0
o=- 123456789 2 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99 100 101
c=IN IP4 0.0.0.0
a=rtpmap:96 VP8/90000
a=rtpmap:97 rtx/90000
a=rtpmap:98 VP9/90000
a=rtpmap:99 rtx/90000
a=rtpmap:100 H264/90000
a=rtpmap:101 rtx/90000
a=fmtp:97 apt=96
a=fmtp:99 apt=98
a=fmtp:101 apt=100
a=fmtp:100 profile-level-id=42e01f
a=mid:0
''';

      final message = SdpMessage.parse(sdp);
      final media = message.mediaDescriptions[0];

      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs.length, equals(3));
      expect(rtxCodecs[96]!.rtxPayloadType, equals(97));  // VP8 -> RTX
      expect(rtxCodecs[98]!.rtxPayloadType, equals(99));  // VP9 -> RTX
      expect(rtxCodecs[100]!.rtxPayloadType, equals(101)); // H264 -> RTX
    });

    test('handles SDP without RTX', () {
      const sdp = '''
v=0
o=- 123456789 2 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
c=IN IP4 0.0.0.0
a=rtpmap:96 VP8/90000
a=ssrc:12345678 cname:user@example.com
a=mid:0
''';

      final message = SdpMessage.parse(sdp);
      final media = message.mediaDescriptions[0];

      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs.isEmpty, isTrue);

      final ssrcMapping = media.getRtxSsrcMapping();
      expect(ssrcMapping.isEmpty, isTrue);
    });
  });

  group('RTX SDP generation and round-trip', () {
    test('generates and parses RTX SDP', () {
      // Generate RTX attributes
      final attrs = RtxSdpBuilder.generateRtxAttributes(
        originalPayloadType: 96,
        rtxPayloadType: 97,
        originalSsrc: 12345678,
        rtxSsrc: 87654321,
        cname: 'test@example.com',
      );

      // Create media with RTX
      final media = SdpMedia(
        type: 'video',
        port: 9,
        protocol: 'UDP/TLS/RTP/SAVPF',
        formats: ['96', '97'],
        attributes: [
          SdpAttribute(key: 'rtpmap', value: '96 VP8/90000'),
          SdpAttribute(key: 'ssrc', value: '12345678 cname:test@example.com'),
          ...attrs,
        ],
      );

      // Verify we can parse what we generated
      final rtxCodecs = media.getRtxCodecs();
      expect(rtxCodecs[96]!.rtxPayloadType, equals(97));

      final ssrcMapping = media.getRtxSsrcMapping();
      expect(ssrcMapping[12345678], equals(87654321));
    });
  });
}

/// Helper to create a video SdpMedia with given attributes
SdpMedia _createVideoMedia(List<SdpAttribute> attributes) {
  return SdpMedia(
    type: 'video',
    port: 9,
    protocol: 'UDP/TLS/RTP/SAVPF',
    formats: ['96', '97'],
    attributes: attributes,
  );
}
