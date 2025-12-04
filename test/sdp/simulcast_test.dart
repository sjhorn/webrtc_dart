import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

void main() {
  group('SDP Simulcast Parsing', () {
    group('SimulcastAttribute', () {
      test('parse send only', () {
        final attr = SimulcastAttribute.parse('send high;low');
        expect(attr.send, equals(['high', 'low']));
        expect(attr.recv, isEmpty);
      });

      test('parse recv only', () {
        final attr = SimulcastAttribute.parse('recv high;mid;low');
        expect(attr.recv, equals(['high', 'mid', 'low']));
        expect(attr.send, isEmpty);
      });

      test('parse send and recv', () {
        final attr = SimulcastAttribute.parse('send high;low recv mid');
        expect(attr.send, equals(['high', 'low']));
        expect(attr.recv, equals(['mid']));
      });

      test('parse recv then send', () {
        final attr = SimulcastAttribute.parse('recv high send low;mid');
        expect(attr.recv, equals(['high']));
        expect(attr.send, equals(['low', 'mid']));
      });

      test('serialize send only', () {
        final attr = SimulcastAttribute(send: ['high', 'low']);
        expect(attr.serialize(), equals('send high;low'));
      });

      test('serialize recv only', () {
        final attr = SimulcastAttribute(recv: ['high', 'low']);
        expect(attr.serialize(), equals('recv high;low'));
      });

      test('serialize both directions', () {
        final attr = SimulcastAttribute(
          send: ['high', 'low'],
          recv: ['mid'],
        );
        // recv comes first in serialization
        expect(attr.serialize(), equals('recv mid send high;low'));
      });

      test('round-trip', () {
        final original = SimulcastAttribute(
          send: ['high', 'low'],
          recv: ['mid'],
        );
        final serialized = original.serialize();
        final parsed = SimulcastAttribute.parse(serialized);
        expect(parsed.send, equals(original.send));
        expect(parsed.recv, equals(original.recv));
      });
    });

    group('RtpHeaderExtension', () {
      test('parse simple extmap', () {
        final ext = RtpHeaderExtension.parse(
            '1 urn:ietf:params:rtp-hdrext:sdes:mid');
        expect(ext.id, equals(1));
        expect(ext.uri, equals('urn:ietf:params:rtp-hdrext:sdes:mid'));
        expect(ext.direction, isNull);
      });

      test('parse extmap with direction', () {
        final ext = RtpHeaderExtension.parse(
            '2/sendonly urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id');
        expect(ext.id, equals(2));
        expect(ext.uri,
            equals('urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id'));
        expect(ext.direction, equals('sendonly'));
      });

      test('serialize simple', () {
        final ext = RtpHeaderExtension(
          id: 1,
          uri: 'urn:ietf:params:rtp-hdrext:sdes:mid',
        );
        expect(ext.serialize(),
            equals('1 urn:ietf:params:rtp-hdrext:sdes:mid'));
      });

      test('serialize with direction', () {
        final ext = RtpHeaderExtension(
          id: 2,
          uri: 'urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id',
          direction: 'recvonly',
        );
        expect(ext.serialize(),
            equals('2/recvonly urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id'));
      });
    });

    group('SdpMedia simulcast methods', () {
      test('getSimulcastParameters from RID attributes', () {
        final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rid:high send
a=rid:low send
a=simulcast:send high;low
''';

        final message = SdpMessage.parse(sdp);
        final media = message.mediaDescriptions.first;

        final params = media.getSimulcastParameters();
        expect(params.length, equals(2));
        expect(params[0].rid, equals('high'));
        expect(params[0].direction, equals(SimulcastDirection.send));
        expect(params[1].rid, equals('low'));
        expect(params[1].direction, equals(SimulcastDirection.send));
      });

      test('getSimulcastAttribute', () {
        final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rid:high send
a=rid:low send
a=simulcast:send high;low
''';

        final message = SdpMessage.parse(sdp);
        final media = message.mediaDescriptions.first;

        final simulcast = media.getSimulcastAttribute();
        expect(simulcast, isNotNull);
        expect(simulcast!.send, equals(['high', 'low']));
        expect(simulcast.recv, isEmpty);
      });

      test('getHeaderExtensions', () {
        final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=extmap:1 urn:ietf:params:rtp-hdrext:sdes:mid
a=extmap:2 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
''';

        final message = SdpMessage.parse(sdp);
        final media = message.mediaDescriptions.first;

        final extensions = media.getHeaderExtensions();
        expect(extensions.length, equals(3));
        expect(extensions[0].id, equals(1));
        expect(extensions[0].uri, equals('urn:ietf:params:rtp-hdrext:sdes:mid'));
        expect(extensions[1].id, equals(2));
        expect(extensions[2].id, equals(3));
      });

      test('getDirection', () {
        final sdpSendRecv = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=sendrecv
''';
        final sdpSendOnly = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=sendonly
''';
        final sdpRecvOnly = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=recvonly
''';
        final sdpInactive = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=inactive
''';

        expect(
            SdpMessage.parse(sdpSendRecv).mediaDescriptions.first.getDirection(),
            equals(MediaDirection.sendrecv));
        expect(
            SdpMessage.parse(sdpSendOnly).mediaDescriptions.first.getDirection(),
            equals(MediaDirection.sendonly));
        expect(
            SdpMessage.parse(sdpRecvOnly).mediaDescriptions.first.getDirection(),
            equals(MediaDirection.recvonly));
        expect(
            SdpMessage.parse(sdpInactive).mediaDescriptions.first.getDirection(),
            equals(MediaDirection.inactive));
      });

      test('getMid', () {
        final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=mid:0
''';

        final message = SdpMessage.parse(sdp);
        expect(message.mediaDescriptions.first.getMid(), equals('0'));
      });

      test('recv simulcast (answerer side)', () {
        final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rid:high recv
a=rid:mid recv
a=rid:low recv
a=simulcast:recv high;mid;low
''';

        final message = SdpMessage.parse(sdp);
        final media = message.mediaDescriptions.first;

        final params = media.getSimulcastParameters();
        expect(params.length, equals(3));
        expect(params.every((p) => p.direction == SimulcastDirection.recv),
            isTrue);

        final simulcast = media.getSimulcastAttribute();
        expect(simulcast!.recv, equals(['high', 'mid', 'low']));
        expect(simulcast.send, isEmpty);
      });
    });

    group('Full SDP with simulcast', () {
      test('parse Chrome simulcast offer', () {
        // Simulated Chrome simulcast offer
        final sdp = '''
v=0
o=- 4611731400430051336 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE 0
a=msid-semantic: WMS
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99
c=IN IP4 0.0.0.0
a=rtcp:9 IN IP4 0.0.0.0
a=ice-ufrag:abcd
a=ice-pwd:efghijklmnopqrstuvwxyz1234
a=ice-options:trickle
a=fingerprint:sha-256 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
a=setup:actpass
a=mid:0
a=extmap:1 urn:ietf:params:rtp-hdrext:sdes:mid
a=extmap:2 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id
a=extmap:3 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id
a=extmap:4 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01
a=sendonly
a=rtcp-mux
a=rtpmap:96 VP8/90000
a=rtcp-fb:96 goog-remb
a=rtcp-fb:96 transport-cc
a=rtcp-fb:96 ccm fir
a=rtcp-fb:96 nack
a=rtcp-fb:96 nack pli
a=rid:high send
a=rid:low send
a=simulcast:send high;low
''';

        final message = SdpMessage.parse(sdp);
        expect(message.mediaDescriptions.length, equals(1));

        final media = message.mediaDescriptions.first;
        expect(media.type, equals('video'));
        expect(media.getMid(), equals('0'));
        expect(media.getDirection(), equals(MediaDirection.sendonly));

        // Header extensions
        final extensions = media.getHeaderExtensions();
        expect(extensions.length, equals(4));
        expect(extensions[0].uri, equals('urn:ietf:params:rtp-hdrext:sdes:mid'));
        expect(extensions[1].uri,
            equals('urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id'));

        // Simulcast
        final params = media.getSimulcastParameters();
        expect(params.length, equals(2));
        expect(params[0].rid, equals('high'));
        expect(params[1].rid, equals('low'));

        final simulcast = media.getSimulcastAttribute();
        expect(simulcast, isNotNull);
        expect(simulcast!.send, equals(['high', 'low']));
      });
    });
  });
}
