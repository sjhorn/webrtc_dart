import 'package:test/test.dart';
import 'package:webrtc_dart/src/sctp/const.dart';

void main() {
  group('SctpChunkType', () {
    test('values have correct codes', () {
      expect(SctpChunkType.data.value, equals(0));
      expect(SctpChunkType.init.value, equals(1));
      expect(SctpChunkType.initAck.value, equals(2));
      expect(SctpChunkType.sack.value, equals(3));
      expect(SctpChunkType.heartbeat.value, equals(4));
      expect(SctpChunkType.heartbeatAck.value, equals(5));
      expect(SctpChunkType.abort.value, equals(6));
      expect(SctpChunkType.shutdown.value, equals(7));
      expect(SctpChunkType.shutdownAck.value, equals(8));
      expect(SctpChunkType.error.value, equals(9));
      expect(SctpChunkType.cookieEcho.value, equals(10));
      expect(SctpChunkType.cookieAck.value, equals(11));
      expect(SctpChunkType.shutdownComplete.value, equals(12));
      expect(SctpChunkType.forwardTsn.value, equals(192));
      expect(SctpChunkType.reconfig.value, equals(130));
    });

    test('fromValue returns correct type', () {
      expect(SctpChunkType.fromValue(0), equals(SctpChunkType.data));
      expect(SctpChunkType.fromValue(1), equals(SctpChunkType.init));
      expect(SctpChunkType.fromValue(3), equals(SctpChunkType.sack));
      expect(SctpChunkType.fromValue(192), equals(SctpChunkType.forwardTsn));
    });

    test('fromValue returns null for unknown value', () {
      expect(SctpChunkType.fromValue(99), isNull);
      expect(SctpChunkType.fromValue(255), isNull);
    });
  });

  group('SctpCauseCode', () {
    test('values have correct codes', () {
      expect(SctpCauseCode.invalidStreamIdentifier.value, equals(1));
      expect(SctpCauseCode.missingMandatoryParameter.value, equals(2));
      expect(SctpCauseCode.staleCookieError.value, equals(3));
      expect(SctpCauseCode.outOfResource.value, equals(4));
      expect(SctpCauseCode.userInitiatedAbort.value, equals(12));
      expect(SctpCauseCode.protocolViolation.value, equals(13));
    });

    test('fromValue returns correct code', () {
      expect(SctpCauseCode.fromValue(1),
          equals(SctpCauseCode.invalidStreamIdentifier));
      expect(SctpCauseCode.fromValue(12),
          equals(SctpCauseCode.userInitiatedAbort));
    });

    test('fromValue returns null for unknown value', () {
      expect(SctpCauseCode.fromValue(0), isNull);
      expect(SctpCauseCode.fromValue(99), isNull);
    });
  });

  group('SctpPpid', () {
    test('values have correct codes', () {
      expect(SctpPpid.dcep.value, equals(50));
      expect(SctpPpid.webrtcString.value, equals(51));
      expect(SctpPpid.webrtcBinary.value, equals(53));
      expect(SctpPpid.webrtcStringEmpty.value, equals(56));
      expect(SctpPpid.webrtcBinaryEmpty.value, equals(57));
    });

    test('fromValue returns correct PPID', () {
      expect(SctpPpid.fromValue(50), equals(SctpPpid.dcep));
      expect(SctpPpid.fromValue(51), equals(SctpPpid.webrtcString));
      expect(SctpPpid.fromValue(53), equals(SctpPpid.webrtcBinary));
    });

    test('fromValue returns null for unknown value', () {
      expect(SctpPpid.fromValue(0), isNull);
      expect(SctpPpid.fromValue(52), isNull);
    });
  });

  group('SctpConstants', () {
    test('header sizes are correct', () {
      expect(SctpConstants.headerSize, equals(12));
      expect(SctpConstants.chunkHeaderSize, equals(4));
    });

    test('default values are correct', () {
      expect(SctpConstants.defaultMtu, equals(1200));
      expect(SctpConstants.dtlsPort, equals(5000));
      expect(SctpConstants.maxStreamId, equals(65535));
    });

    test('timeout values are correct', () {
      expect(SctpConstants.rtoInitial, equals(3000));
      expect(SctpConstants.rtoMin, equals(1000));
      expect(SctpConstants.rtoMax, equals(60000));
      expect(SctpConstants.sackTimeout, equals(200));
    });

    test('chunk sizes are correct', () {
      expect(SctpConstants.initChunkMinSize, equals(16));
      expect(SctpConstants.sackChunkMinSize, equals(12));
      expect(SctpConstants.dataChunkMinSize, equals(16));
    });

    test('window sizes are correct', () {
      expect(SctpConstants.defaultRwnd, equals(131072));
      expect(SctpConstants.defaultAdvertisedRwnd, equals(131072));
    });

    test('retransmission limits are correct', () {
      expect(SctpConstants.maxInitRetransmits, equals(8));
      expect(SctpConstants.maxPathRetransmits, equals(5));
      expect(SctpConstants.maxAssocRetransmits, equals(10));
    });

    test('RTO calculation constants are correct', () {
      expect(SctpConstants.rtoAlpha, equals(0.125));
      expect(SctpConstants.rtoBeta, equals(0.25));
    });
  });

  group('SctpDataChunkFlags', () {
    test('flags have correct values', () {
      expect(SctpDataChunkFlags.endFragment, equals(0x01));
      expect(SctpDataChunkFlags.beginningFragment, equals(0x02));
      expect(SctpDataChunkFlags.unordered, equals(0x04));
      expect(SctpDataChunkFlags.immediate, equals(0x08));
    });

    test('flags can be combined', () {
      final flags = SctpDataChunkFlags.beginningFragment |
          SctpDataChunkFlags.endFragment;
      expect(flags, equals(0x03));

      final allFlags = SctpDataChunkFlags.beginningFragment |
          SctpDataChunkFlags.endFragment |
          SctpDataChunkFlags.unordered |
          SctpDataChunkFlags.immediate;
      expect(allFlags, equals(0x0F));
    });
  });

  group('SctpParameterType', () {
    test('values have correct codes', () {
      expect(SctpParameterType.heartbeatInfo.value, equals(1));
      expect(SctpParameterType.ipv4Address.value, equals(5));
      expect(SctpParameterType.ipv6Address.value, equals(6));
      expect(SctpParameterType.stateCookie.value, equals(7));
      expect(SctpParameterType.forwardTsnSupported.value, equals(0xC000));
    });

    test('fromValue returns correct type', () {
      expect(
          SctpParameterType.fromValue(1), equals(SctpParameterType.heartbeatInfo));
      expect(
          SctpParameterType.fromValue(7), equals(SctpParameterType.stateCookie));
      expect(SctpParameterType.fromValue(0xC000),
          equals(SctpParameterType.forwardTsnSupported));
    });

    test('fromValue returns null for unknown value', () {
      expect(SctpParameterType.fromValue(0), isNull);
      expect(SctpParameterType.fromValue(99), isNull);
    });
  });
}
