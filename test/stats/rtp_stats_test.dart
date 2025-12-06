import 'package:test/test.dart';
import 'package:webrtc_dart/src/stats/rtc_stats.dart';
import 'package:webrtc_dart/src/stats/rtp_stats.dart';

void main() {
  group('RTCInboundRtpStreamStats', () {
    test('construction with required fields', () {
      final stats = RTCInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'inbound-1',
        ssrc: 12345678,
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.001,
        bytesReceived: 50000,
      );

      expect(stats.type, equals(RTCStatsType.inboundRtp));
      expect(stats.ssrc, equals(12345678));
      expect(stats.packetsReceived, equals(100));
      expect(stats.packetsLost, equals(5));
      expect(stats.jitter, equals(0.001));
      expect(stats.bytesReceived, equals(50000));
    });

    test('construction with all optional fields', () {
      final stats = RTCInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'inbound-1',
        ssrc: 12345678,
        codecId: 'codec-1',
        kind: 'video',
        transportId: 'transport-1',
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.001,
        bytesReceived: 50000,
        trackIdentifier: 'track-1',
        receiverId: 'receiver-1',
        remoteId: 'remote-1',
        framesReceived: 300,
        framesDecoded: 295,
        framesDropped: 2,
        keyFramesDecoded: 10,
        headerBytesReceived: 2000,
        nackCount: 3,
        firCount: 1,
        pliCount: 2,
      );

      expect(stats.codecId, equals('codec-1'));
      expect(stats.kind, equals('video'));
      expect(stats.transportId, equals('transport-1'));
      expect(stats.trackIdentifier, equals('track-1'));
      expect(stats.framesReceived, equals(300));
      expect(stats.framesDecoded, equals(295));
      expect(stats.framesDropped, equals(2));
      expect(stats.keyFramesDecoded, equals(10));
      expect(stats.nackCount, equals(3));
      expect(stats.firCount, equals(1));
      expect(stats.pliCount, equals(2));
    });

    test('toJson includes all fields', () {
      final stats = RTCInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'inbound-1',
        ssrc: 12345678,
        codecId: 'codec-1',
        kind: 'audio',
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.001,
        bytesReceived: 50000,
        totalSamplesReceived: 48000,
        lastPacketReceivedTimestamp: 1234567891.0,
      );

      final json = stats.toJson();

      expect(json['id'], equals('inbound-1'));
      expect(json['type'], equals('inbound-rtp'));
      expect(json['ssrc'], equals(12345678));
      expect(json['codecId'], equals('codec-1'));
      expect(json['kind'], equals('audio'));
      expect(json['packetsReceived'], equals(100));
      expect(json['packetsLost'], equals(5));
      expect(json['jitter'], equals(0.001));
      expect(json['bytesReceived'], equals(50000));
      expect(json['totalSamplesReceived'], equals(48000));
    });
  });

  group('RTCOutboundRtpStreamStats', () {
    test('construction with required fields', () {
      final stats = RTCOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'outbound-1',
        ssrc: 87654321,
        packetsSent: 200,
        bytesSent: 100000,
      );

      expect(stats.type, equals(RTCStatsType.outboundRtp));
      expect(stats.ssrc, equals(87654321));
      expect(stats.packetsSent, equals(200));
      expect(stats.bytesSent, equals(100000));
    });

    test('construction with all optional fields', () {
      final stats = RTCOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'outbound-1',
        ssrc: 87654321,
        codecId: 'codec-1',
        kind: 'video',
        transportId: 'transport-1',
        packetsSent: 200,
        bytesSent: 100000,
        trackId: 'track-1',
        senderId: 'sender-1',
        remoteId: 'remote-1',
        mediaSourceId: 'source-1',
        framesSent: 300,
        framesEncoded: 300,
        keyFramesEncoded: 10,
        headerBytesSent: 4000,
        retransmittedPacketsSent: 5,
        retransmittedBytesSent: 2500,
        encoderImplementation: 'libvpx',
        nackCount: 3,
        firCount: 1,
        pliCount: 2,
        qualityLimitationReason: 'bandwidth',
        qualityLimitationDurations: {'none': 10.0, 'bandwidth': 5.0},
        totalEncodeTime: 15.0,
        totalPacketSendDelay: 0.5,
        averageRtcpInterval: 1.0,
      );

      expect(stats.trackId, equals('track-1'));
      expect(stats.senderId, equals('sender-1'));
      expect(stats.framesSent, equals(300));
      expect(stats.framesEncoded, equals(300));
      expect(stats.keyFramesEncoded, equals(10));
      expect(stats.retransmittedPacketsSent, equals(5));
      expect(stats.encoderImplementation, equals('libvpx'));
      expect(stats.qualityLimitationReason, equals('bandwidth'));
      expect(stats.qualityLimitationDurations!['bandwidth'], equals(5.0));
    });

    test('toJson includes all fields', () {
      final stats = RTCOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'outbound-1',
        ssrc: 87654321,
        packetsSent: 200,
        bytesSent: 100000,
        framesSent: 300,
        encoderImplementation: 'openh264',
      );

      final json = stats.toJson();

      expect(json['id'], equals('outbound-1'));
      expect(json['type'], equals('outbound-rtp'));
      expect(json['ssrc'], equals(87654321));
      expect(json['packetsSent'], equals(200));
      expect(json['bytesSent'], equals(100000));
      expect(json['framesSent'], equals(300));
      expect(json['encoderImplementation'], equals('openh264'));
    });
  });

  group('RTCRemoteInboundRtpStreamStats', () {
    test('construction with required fields', () {
      final stats = RTCRemoteInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-inbound-1',
        ssrc: 12345678,
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.002,
      );

      expect(stats.type, equals(RTCStatsType.remoteInboundRtp));
      expect(stats.ssrc, equals(12345678));
      expect(stats.packetsReceived, equals(100));
      expect(stats.packetsLost, equals(5));
      expect(stats.jitter, equals(0.002));
    });

    test('construction with RTT fields', () {
      final stats = RTCRemoteInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-inbound-1',
        ssrc: 12345678,
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.002,
        localId: 'outbound-1',
        roundTripTime: 0.025,
        totalRoundTripTime: 2.5,
        fractionLost: 0.05,
        roundTripTimeMeasurements: 100,
      );

      expect(stats.localId, equals('outbound-1'));
      expect(stats.roundTripTime, equals(0.025));
      expect(stats.totalRoundTripTime, equals(2.5));
      expect(stats.fractionLost, equals(0.05));
      expect(stats.roundTripTimeMeasurements, equals(100));
    });

    test('toJson includes all fields', () {
      final stats = RTCRemoteInboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-inbound-1',
        ssrc: 12345678,
        packetsReceived: 100,
        packetsLost: 5,
        jitter: 0.002,
        roundTripTime: 0.025,
      );

      final json = stats.toJson();

      expect(json['id'], equals('remote-inbound-1'));
      expect(json['type'], equals('remote-inbound-rtp'));
      expect(json['roundTripTime'], equals(0.025));
    });
  });

  group('RTCRemoteOutboundRtpStreamStats', () {
    test('construction with required fields', () {
      final stats = RTCRemoteOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-outbound-1',
        ssrc: 87654321,
        packetsSent: 200,
        bytesSent: 100000,
      );

      expect(stats.type, equals(RTCStatsType.remoteOutboundRtp));
      expect(stats.ssrc, equals(87654321));
      expect(stats.packetsSent, equals(200));
      expect(stats.bytesSent, equals(100000));
    });

    test('construction with all optional fields', () {
      final stats = RTCRemoteOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-outbound-1',
        ssrc: 87654321,
        packetsSent: 200,
        bytesSent: 100000,
        localId: 'inbound-1',
        remoteTimestamp: 1234567889.0,
        reportsSent: 50,
        roundTripTime: 0.030,
        totalRoundTripTime: 3.0,
        roundTripTimeMeasurements: 100,
      );

      expect(stats.localId, equals('inbound-1'));
      expect(stats.remoteTimestamp, equals(1234567889.0));
      expect(stats.reportsSent, equals(50));
      expect(stats.roundTripTime, equals(0.030));
    });

    test('toJson includes all fields', () {
      final stats = RTCRemoteOutboundRtpStreamStats(
        timestamp: 1234567890.0,
        id: 'remote-outbound-1',
        ssrc: 87654321,
        packetsSent: 200,
        bytesSent: 100000,
        remoteTimestamp: 1234567889.0,
      );

      final json = stats.toJson();

      expect(json['id'], equals('remote-outbound-1'));
      expect(json['type'], equals('remote-outbound-rtp'));
      expect(json['remoteTimestamp'], equals(1234567889.0));
    });
  });

  group('RTCMediaSourceStats', () {
    test('construction for video source', () {
      final stats = RTCMediaSourceStats(
        timestamp: 1234567890.0,
        id: 'source-1',
        trackIdentifier: 'track-1',
        kind: 'video',
        width: 1920,
        height: 1080,
        framesPerSecond: 30.0,
        frames: 1800,
      );

      expect(stats.type, equals(RTCStatsType.mediaSource));
      expect(stats.trackIdentifier, equals('track-1'));
      expect(stats.kind, equals('video'));
      expect(stats.width, equals(1920));
      expect(stats.height, equals(1080));
      expect(stats.framesPerSecond, equals(30.0));
      expect(stats.frames, equals(1800));
    });

    test('construction for audio source', () {
      final stats = RTCMediaSourceStats(
        timestamp: 1234567890.0,
        id: 'source-1',
        trackIdentifier: 'track-1',
        kind: 'audio',
        audioLevel: 0.5,
        totalAudioEnergy: 100.0,
        totalSamplesDuration: 60.0,
      );

      expect(stats.kind, equals('audio'));
      expect(stats.audioLevel, equals(0.5));
      expect(stats.totalAudioEnergy, equals(100.0));
      expect(stats.totalSamplesDuration, equals(60.0));
    });

    test('toJson includes all fields', () {
      final stats = RTCMediaSourceStats(
        timestamp: 1234567890.0,
        id: 'source-1',
        trackIdentifier: 'track-1',
        kind: 'video',
        width: 640,
        height: 480,
      );

      final json = stats.toJson();

      expect(json['id'], equals('source-1'));
      expect(json['type'], equals('media-source'));
      expect(json['trackIdentifier'], equals('track-1'));
      expect(json['kind'], equals('video'));
      expect(json['width'], equals(640));
      expect(json['height'], equals(480));
    });
  });

  group('RTCCodecStats', () {
    test('construction with required fields', () {
      final stats = RTCCodecStats(
        timestamp: 1234567890.0,
        id: 'codec-1',
        payloadType: 96,
        transportId: 'transport-1',
        mimeType: 'video/VP8',
      );

      expect(stats.type, equals(RTCStatsType.codec));
      expect(stats.payloadType, equals(96));
      expect(stats.transportId, equals('transport-1'));
      expect(stats.mimeType, equals('video/VP8'));
    });

    test('construction with all fields', () {
      final stats = RTCCodecStats(
        timestamp: 1234567890.0,
        id: 'codec-1',
        payloadType: 111,
        transportId: 'transport-1',
        mimeType: 'audio/opus',
        clockRate: 48000,
        channels: 2,
        sdpFmtpLine: 'minptime=10;useinbandfec=1',
      );

      expect(stats.clockRate, equals(48000));
      expect(stats.channels, equals(2));
      expect(stats.sdpFmtpLine, equals('minptime=10;useinbandfec=1'));
    });

    test('toJson includes all fields', () {
      final stats = RTCCodecStats(
        timestamp: 1234567890.0,
        id: 'codec-1',
        payloadType: 96,
        transportId: 'transport-1',
        mimeType: 'video/H264',
        clockRate: 90000,
        sdpFmtpLine: 'level-asymmetry-allowed=1;packetization-mode=1',
      );

      final json = stats.toJson();

      expect(json['id'], equals('codec-1'));
      expect(json['type'], equals('codec'));
      expect(json['payloadType'], equals(96));
      expect(json['transportId'], equals('transport-1'));
      expect(json['mimeType'], equals('video/H264'));
      expect(json['clockRate'], equals(90000));
    });
  });

  group('RTCStatsReport with RTP stats', () {
    test('can contain all RTP stats types', () {
      final report = RTCStatsReport([
        RTCInboundRtpStreamStats(
          timestamp: 1234567890.0,
          id: 'inbound-1',
          ssrc: 12345678,
          packetsReceived: 100,
          packetsLost: 5,
          jitter: 0.001,
          bytesReceived: 50000,
        ),
        RTCOutboundRtpStreamStats(
          timestamp: 1234567890.0,
          id: 'outbound-1',
          ssrc: 87654321,
          packetsSent: 200,
          bytesSent: 100000,
        ),
        RTCRemoteInboundRtpStreamStats(
          timestamp: 1234567890.0,
          id: 'remote-inbound-1',
          ssrc: 12345678,
          packetsReceived: 100,
          packetsLost: 5,
          jitter: 0.002,
        ),
        RTCRemoteOutboundRtpStreamStats(
          timestamp: 1234567890.0,
          id: 'remote-outbound-1',
          ssrc: 87654321,
          packetsSent: 200,
          bytesSent: 100000,
        ),
        RTCMediaSourceStats(
          timestamp: 1234567890.0,
          id: 'source-1',
          trackIdentifier: 'track-1',
          kind: 'video',
        ),
        RTCCodecStats(
          timestamp: 1234567890.0,
          id: 'codec-1',
          payloadType: 96,
          transportId: 'transport-1',
          mimeType: 'video/VP8',
        ),
      ]);

      expect(report.length, equals(6));
      expect(report['inbound-1'], isA<RTCInboundRtpStreamStats>());
      expect(report['outbound-1'], isA<RTCOutboundRtpStreamStats>());
      expect(report['remote-inbound-1'], isA<RTCRemoteInboundRtpStreamStats>());
      expect(
          report['remote-outbound-1'], isA<RTCRemoteOutboundRtpStreamStats>());
      expect(report['source-1'], isA<RTCMediaSourceStats>());
      expect(report['codec-1'], isA<RTCCodecStats>());
    });
  });
}
