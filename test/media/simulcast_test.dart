import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';
import 'package:webrtc_dart/src/media/parameters.dart';
import 'package:webrtc_dart/src/media/rtp_router.dart';
import 'package:webrtc_dart/src/rtp/header_extension.dart';
import 'package:webrtc_dart/src/sdp/sdp.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

/// Helper to create RTP packet for testing
RtpPacket createTestPacket({
  int payloadType = 96,
  int sequenceNumber = 1,
  int timestamp = 0,
  int ssrc = 12345,
  bool hasExtension = false,
  Uint8List? extensionData,
}) {
  RtpExtension? extensionHeader;
  if (hasExtension && extensionData != null) {
    extensionHeader = RtpExtension(
      profile: 0xBEDE, // One-byte header
      data: extensionData,
    );
  }

  return RtpPacket(
    payloadType: payloadType,
    sequenceNumber: sequenceNumber,
    timestamp: timestamp,
    ssrc: ssrc,
    extension: hasExtension,
    extensionHeader: extensionHeader,
    payload: Uint8List(0),
  );
}

void main() {
  group('MediaStreamTrack RID', () {
    test('AudioStreamTrack with RID', () {
      final track = AudioStreamTrack(
        id: 'audio1',
        label: 'Audio',
        rid: 'high',
      );

      expect(track.rid, equals('high'));
      expect(track.kind, equals(MediaStreamTrackKind.audio));
    });

    test('VideoStreamTrack with RID', () {
      final track = VideoStreamTrack(
        id: 'video1',
        label: 'Video',
        rid: 'low',
      );

      expect(track.rid, equals('low'));
      expect(track.kind, equals(MediaStreamTrackKind.video));
    });

    test('clone preserves RID', () {
      final track = VideoStreamTrack(
        id: 'video1',
        label: 'Video',
        rid: 'mid',
      );

      final cloned = track.clone();
      expect(cloned.rid, equals('mid'));
    });
  });

  group('RtpRouter', () {
    late RtpRouter router;

    setUp(() {
      router = RtpRouter();
    });

    test('register and route by SSRC', () {
      var receivedPacket = false;
      var receivedRid = 'none';

      router.registerBySsrc(12345, (packet, rid, extensions) {
        receivedPacket = true;
        receivedRid = rid ?? 'null';
      });

      final packet = createTestPacket(ssrc: 12345);

      router.routeRtp(packet);

      expect(receivedPacket, isTrue);
      expect(receivedRid, equals('null'));
    });

    test('register and route by RID', () {
      var receivedPacket = false;
      String? receivedRid;

      // Register header extension mapping
      router.registerHeaderExtensions([
        RtpHeaderExtension(id: 1, uri: RtpExtensionUri.sdesRtpStreamId),
      ]);

      router.registerByRid('high', (packet, rid, extensions) {
        receivedPacket = true;
        receivedRid = rid;
      });

      // Build extension data with RID
      final extData = buildRtpExtensions(
        {RtpExtensionUri.sdesRtpStreamId: 'high'},
        {RtpExtensionUri.sdesRtpStreamId: 1},
      );

      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 12345,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE, // One-byte header
          data: extData,
        ),
        payload: Uint8List(0),
      );

      router.routeRtp(packet);

      expect(receivedPacket, isTrue);
      expect(receivedRid, equals('high'));
    });

    test('auto-register SSRC after RID routing', () {
      var packetCount = 0;

      router.registerHeaderExtensions([
        RtpHeaderExtension(id: 1, uri: RtpExtensionUri.sdesRtpStreamId),
      ]);

      router.registerByRid('high', (packet, rid, extensions) {
        packetCount++;
      });

      // First packet with RID extension
      final extData = buildRtpExtensions(
        {RtpExtensionUri.sdesRtpStreamId: 'high'},
        {RtpExtensionUri.sdesRtpStreamId: 1},
      );

      final packet1 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 12345,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE,
          data: extData,
        ),
        payload: Uint8List(0),
      );

      router.routeRtp(packet1);
      expect(packetCount, equals(1));

      // Second packet without RID (same SSRC should route to same handler)
      final packet2 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 2,
        timestamp: 3000,
        ssrc: 12345, // Same SSRC
        payload: Uint8List(0),
      );

      router.routeRtp(packet2);
      expect(packetCount, equals(2));
    });

    test('route multiple RIDs to different handlers', () {
      var highCount = 0;
      var lowCount = 0;

      router.registerHeaderExtensions([
        RtpHeaderExtension(id: 1, uri: RtpExtensionUri.sdesRtpStreamId),
      ]);

      router.registerByRid('high', (packet, rid, extensions) {
        highCount++;
      });

      router.registerByRid('low', (packet, rid, extensions) {
        lowCount++;
      });

      final highExtData = buildRtpExtensions(
        {RtpExtensionUri.sdesRtpStreamId: 'high'},
        {RtpExtensionUri.sdesRtpStreamId: 1},
      );

      final lowExtData = buildRtpExtensions(
        {RtpExtensionUri.sdesRtpStreamId: 'low'},
        {RtpExtensionUri.sdesRtpStreamId: 1},
      );

      router.routeRtp(RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 11111,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE,
          data: highExtData,
        ),
        payload: Uint8List(0),
      ));

      router.routeRtp(RtpPacket(
        payloadType: 96,
        sequenceNumber: 1,
        timestamp: 0,
        ssrc: 22222,
        extension: true,
        extensionHeader: RtpExtension(
          profile: 0xBEDE,
          data: lowExtData,
        ),
        payload: Uint8List(0),
      ));

      expect(highCount, equals(1));
      expect(lowCount, equals(1));
    });

    test('register track by RID and SSRC', () {
      final highTrack = VideoStreamTrack(id: 'v1', label: 'High', rid: 'high');
      final lowTrack = VideoStreamTrack(id: 'v2', label: 'Low', rid: 'low');

      router.registerTrackByRid('high', highTrack);
      router.registerTrackByRid('low', lowTrack);
      router.registerTrackBySsrc(11111, highTrack);
      router.registerTrackBySsrc(22222, lowTrack);

      expect(router.getTrackByRid('high'), equals(highTrack));
      expect(router.getTrackByRid('low'), equals(lowTrack));
      expect(router.getTrackBySsrc(11111), equals(highTrack));
      expect(router.getTrackBySsrc(22222), equals(lowTrack));
    });

    test('registeredRids and registeredSsrcs', () {
      router.registerByRid('high', (a, b, c) {});
      router.registerByRid('low', (a, b, c) {});
      router.registerBySsrc(11111, (a, b, c) {});
      router.registerBySsrc(22222, (a, b, c) {});

      expect(router.registeredRids, containsAll(['high', 'low']));
      expect(router.registeredSsrcs, containsAll([11111, 22222]));
    });

    test('clear removes all registrations', () {
      router.registerByRid('high', (a, b, c) {});
      router.registerBySsrc(11111, (a, b, c) {});
      router.registerTrackByRid(
          'high', VideoStreamTrack(id: 'v1', label: 'High'));
      router.registerTrackBySsrc(
          11111, VideoStreamTrack(id: 'v2', label: 'Low'));

      router.clear();

      expect(router.registeredRids, isEmpty);
      expect(router.registeredSsrcs, isEmpty);
      expect(router.getTrackByRid('high'), isNull);
      expect(router.getTrackBySsrc(11111), isNull);
    });
  });

  group('SimulcastLayer', () {
    test('construction', () {
      final layer = SimulcastLayer(
        rid: 'high',
        direction: SimulcastDirection.recv,
      );

      expect(layer.rid, equals('high'));
      expect(layer.direction, equals(SimulcastDirection.recv));
      expect(layer.active, isTrue);
      expect(layer.ssrc, isNull);
      expect(layer.track, isNull);
    });

    test('construction with all fields', () {
      final track = VideoStreamTrack(id: 'v1', label: 'High', rid: 'high');
      final layer = SimulcastLayer(
        rid: 'high',
        direction: SimulcastDirection.send,
        ssrc: 12345,
        track: track,
        active: false,
      );

      expect(layer.ssrc, equals(12345));
      expect(layer.track, equals(track));
      expect(layer.active, isFalse);
    });
  });

  group('SimulcastManager', () {
    late RtpRouter router;
    late SimulcastManager manager;

    setUp(() {
      router = RtpRouter();
      manager = SimulcastManager(
        router: router,
        kind: MediaStreamTrackKind.video,
      );
    });

    test('add layers from parameters', () {
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.recv,
      ));
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'low',
        direction: SimulcastDirection.recv,
      ));

      expect(manager.layers.length, equals(2));
      expect(manager.getLayer('high'), isNotNull);
      expect(manager.getLayer('low'), isNotNull);
    });

    test('activeLayers returns only active layers', () {
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.recv,
      ));
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'low',
        direction: SimulcastDirection.recv,
      ));

      manager.setLayerActive('low', false);

      final active = manager.activeLayers;
      expect(active.length, equals(1));
      expect(active.first.rid, equals('high'));
    });

    test('selectLayer deactivates others', () {
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.recv,
      ));
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'mid',
        direction: SimulcastDirection.recv,
      ));
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'low',
        direction: SimulcastDirection.recv,
      ));

      manager.selectLayer('mid');

      expect(manager.getLayer('high')!.active, isFalse);
      expect(manager.getLayer('mid')!.active, isTrue);
      expect(manager.getLayer('low')!.active, isFalse);
    });

    test('recv layers register with router', () {
      manager.addLayer(RTCRtpSimulcastParameters(
        rid: 'high',
        direction: SimulcastDirection.recv,
      ));

      expect(router.registeredRids, contains('high'));
    });
  });

  group('RTCRtpSimulcastParameters integration', () {
    test('parse from SDP and use with router', () {
      final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rid:high send
a=rid:mid send
a=rid:low send
a=simulcast:send high;mid;low
''';

      final message = SdpMessage.parse(sdp);
      final media = message.mediaDescriptions.first;

      final params = media.getSimulcastParameters();
      expect(params.length, equals(3));

      // Create router and register layers
      final router = RtpRouter();
      for (final param in params) {
        router.registerByRid(param.rid, (packet, rid, extensions) {
          // Handler
        });
      }

      expect(router.registeredRids, containsAll(['high', 'mid', 'low']));
    });

    test('parse recv simulcast from SDP', () {
      final sdp = '''
v=0
o=- 0 0 IN IP4 127.0.0.1
s=-
t=0 0
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rid:high recv
a=rid:low recv
a=simulcast:recv high;low
''';

      final message = SdpMessage.parse(sdp);
      final media = message.mediaDescriptions.first;

      final params = media.getSimulcastParameters();
      expect(params.length, equals(2));
      expect(params.every((p) => p.direction == SimulcastDirection.recv),
          isTrue);
    });
  });
}
