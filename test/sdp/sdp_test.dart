import 'package:test/test.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';

void main() {
  group('SDP Parsing', () {
    test('parses basic SDP', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
''';

      final message = SdpMessage.parse(sdp);

      expect(message.version, 0);
      expect(message.origin.sessionId, '123456');
      expect(message.sessionName, 'Test Session');
      expect(message.timing.length, 1);
    });

    test('parses SDP with media', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
''';

      final message = SdpMessage.parse(sdp);

      expect(message.mediaDescriptions.length, 1);
      expect(message.mediaDescriptions[0].type, 'audio');
      expect(message.mediaDescriptions[0].port, 9);
      expect(message.mediaDescriptions[0].protocol, 'UDP/TLS/RTP/SAVPF');
      expect(message.mediaDescriptions[0].formats, ['111']);
      expect(message.mediaDescriptions[0].attributes.length, 1);
    });

    test('parses SDP with multiple media sections', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
a=sctp-port:5000
''';

      final message = SdpMessage.parse(sdp);

      expect(message.mediaDescriptions.length, 2);
      expect(message.mediaDescriptions[0].type, 'audio');
      expect(message.mediaDescriptions[1].type, 'application');
      expect(message.mediaDescriptions[1].formats, ['webrtc-datachannel']);
    });

    test('parses attributes correctly', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
a=group:BUNDLE 0 1
a=ice-options:trickle
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
a=sendrecv
''';

      final message = SdpMessage.parse(sdp);

      expect(message.attributes.length, 2);
      expect(message.attributes[0].key, 'group');
      expect(message.attributes[0].value, 'BUNDLE 0 1');
      expect(message.attributes[1].key, 'ice-options');
      expect(message.attributes[1].value, 'trickle');

      expect(message.mediaDescriptions[0].attributes.length, 2);
      expect(message.mediaDescriptions[0].attributes[0].key, 'rtpmap');
      expect(message.mediaDescriptions[0].attributes[1].key, 'sendrecv');
      expect(message.mediaDescriptions[0].attributes[1].value, null);
    });

    test('parses connection information', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
c=IN IP4 192.168.1.1
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
c=IN IP4 10.0.0.1
''';

      final message = SdpMessage.parse(sdp);

      expect(message.connection, isNotNull);
      expect(message.connection!.connectionAddress, '192.168.1.1');
      expect(message.mediaDescriptions[0].connection, isNotNull);
      expect(message.mediaDescriptions[0].connection!.connectionAddress,
          '10.0.0.1');
    });
  });

  group('SDP Serialization', () {
    test('serializes basic SDP', () {
      final message = SdpMessage(
        version: 0,
        origin: SdpOrigin(
          username: '-',
          sessionId: '123456',
          sessionVersion: '789012',
          unicastAddress: '127.0.0.1',
        ),
        sessionName: 'Test Session',
        timing: [SdpTiming(startTime: 0, stopTime: 0)],
      );

      final sdp = message.serialize();

      expect(sdp, contains('v=0'));
      expect(sdp, contains('o=- 123456 789012 IN IP4 127.0.0.1'));
      expect(sdp, contains('s=Test Session'));
      expect(sdp, contains('t=0 0'));
    });

    test('serializes SDP with media', () {
      final message = SdpMessage(
        version: 0,
        origin: SdpOrigin(
          username: '-',
          sessionId: '123456',
          sessionVersion: '789012',
          unicastAddress: '127.0.0.1',
        ),
        sessionName: 'Test Session',
        timing: [SdpTiming(startTime: 0, stopTime: 0)],
        mediaDescriptions: [
          SdpMedia(
            type: 'audio',
            port: 9,
            protocol: 'UDP/TLS/RTP/SAVPF',
            formats: ['111'],
            attributes: [
              SdpAttribute(key: 'rtpmap', value: '111 opus/48000/2'),
            ],
          ),
        ],
      );

      final sdp = message.serialize();

      expect(sdp, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111'));
      expect(sdp, contains('a=rtpmap:111 opus/48000/2'));
    });

    test('round-trips SDP', () {
      const original = '''v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
a=sctp-port:5000
''';

      final message = SdpMessage.parse(original);
      final serialized = message.serialize();
      final reparsed = SdpMessage.parse(serialized);

      expect(reparsed.version, message.version);
      expect(reparsed.sessionName, message.sessionName);
      expect(
          reparsed.mediaDescriptions.length, message.mediaDescriptions.length);
      expect(reparsed.mediaDescriptions[0].type,
          message.mediaDescriptions[0].type);
      expect(reparsed.mediaDescriptions[1].type,
          message.mediaDescriptions[1].type);
    });
  });

  group('SDP Attributes', () {
    test('gets attribute value', () {
      final media = SdpMedia(
        type: 'audio',
        port: 9,
        protocol: 'UDP/TLS/RTP/SAVPF',
        formats: ['111'],
        attributes: [
          SdpAttribute(key: 'rtpmap', value: '111 opus/48000/2'),
          SdpAttribute(key: 'sendrecv'),
          SdpAttribute(key: 'rtpmap', value: '112 PCMU/8000'),
        ],
      );

      expect(media.getAttributeValue('rtpmap'), '111 opus/48000/2');
      expect(media.getAttributeValue('sendrecv'), null);
      expect(media.getAttributeValue('unknown'), null);
    });

    test('gets all attributes with key', () {
      final media = SdpMedia(
        type: 'audio',
        port: 9,
        protocol: 'UDP/TLS/RTP/SAVPF',
        formats: ['111', '112'],
        attributes: [
          SdpAttribute(key: 'rtpmap', value: '111 opus/48000/2'),
          SdpAttribute(key: 'sendrecv'),
          SdpAttribute(key: 'rtpmap', value: '112 PCMU/8000'),
        ],
      );

      final rtpmaps = media.getAttributes('rtpmap');
      expect(rtpmaps.length, 2);
      expect(rtpmaps[0].value, '111 opus/48000/2');
      expect(rtpmaps[1].value, '112 PCMU/8000');
    });
  });

  group('ICE-lite detection', () {
    test('detects session-level ice-lite', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
a=ice-lite
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
''';

      final message = SdpMessage.parse(sdp);
      expect(message.isIceLite, isTrue);
      expect(message.hasAttribute('ice-lite'), isTrue);
    });

    test('detects media-level ice-lite', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
a=ice-lite
''';

      final message = SdpMessage.parse(sdp);
      expect(message.isIceLite, isTrue);
      expect(message.mediaDescriptions[0].hasAttribute('ice-lite'), isTrue);
    });

    test('returns false when no ice-lite', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
m=audio 9 UDP/TLS/RTP/SAVPF 111
a=rtpmap:111 opus/48000/2
''';

      final message = SdpMessage.parse(sdp);
      expect(message.isIceLite, isFalse);
    });

    test('session-level getAttributeValue works', () {
      const sdp = '''
v=0
o=- 123456 789012 IN IP4 127.0.0.1
s=Test Session
t=0 0
a=group:BUNDLE 0
a=ice-options:trickle
m=audio 9 UDP/TLS/RTP/SAVPF 111
''';

      final message = SdpMessage.parse(sdp);
      expect(message.getAttributeValue('group'), 'BUNDLE 0');
      expect(message.getAttributeValue('ice-options'), 'trickle');
      expect(message.getAttributeValue('nonexistent'), isNull);
    });
  });
}
