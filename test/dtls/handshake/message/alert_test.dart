import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

void main() {
  group('Alert', () {
    test('constructor creates Alert', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.handshakeFailure));
    });

    test('fatal factory creates fatal alert', () {
      final alert = Alert.fatal(AlertDescription.badCertificate);

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.badCertificate));
    });

    test('warning factory creates warning alert', () {
      final alert = Alert.warning(AlertDescription.closeNotify);

      expect(alert.level, equals(AlertLevel.warning));
      expect(alert.description, equals(AlertDescription.closeNotify));
    });

    group('static alert getters', () {
      test('closeNotify is warning', () {
        final alert = Alert.closeNotify;
        expect(alert.level, equals(AlertLevel.warning));
        expect(alert.description, equals(AlertDescription.closeNotify));
      });

      test('unexpectedMessage is fatal', () {
        final alert = Alert.unexpectedMessage;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.unexpectedMessage));
      });

      test('badRecordMac is fatal', () {
        final alert = Alert.badRecordMac;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.badRecordMac));
      });

      test('decryptionFailed is fatal', () {
        final alert = Alert.decryptionFailed;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.decryptionFailed));
      });

      test('recordOverflow is fatal', () {
        final alert = Alert.recordOverflow;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.recordOverflow));
      });

      test('decompressFailed is fatal', () {
        final alert = Alert.decompressFailed;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.decompressFailed));
      });

      test('handshakeFailure is fatal', () {
        final alert = Alert.handshakeFailure;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.handshakeFailure));
      });

      test('badCertificate is fatal', () {
        final alert = Alert.badCertificate;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.badCertificate));
      });

      test('unsupportedCertificate is fatal', () {
        final alert = Alert.unsupportedCertificate;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(
            alert.description, equals(AlertDescription.unsupportedCertificate));
      });

      test('certificateRevoked is fatal', () {
        final alert = Alert.certificateRevoked;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.certificateRevoked));
      });

      test('certificateExpired is fatal', () {
        final alert = Alert.certificateExpired;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.certificateExpired));
      });

      test('certificateUnknown is fatal', () {
        final alert = Alert.certificateUnknown;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.certificateUnknown));
      });

      test('illegalParameter is fatal', () {
        final alert = Alert.illegalParameter;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.illegalParameter));
      });

      test('unknownCa is fatal', () {
        final alert = Alert.unknownCa;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.unknownCa));
      });

      test('accessDenied is fatal', () {
        final alert = Alert.accessDenied;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.accessDenied));
      });

      test('decodeError is fatal', () {
        final alert = Alert.decodeError;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.decodeError));
      });

      test('decryptError is fatal', () {
        final alert = Alert.decryptError;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.decryptError));
      });

      test('protocolVersion is fatal', () {
        final alert = Alert.protocolVersion;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.protocolVersion));
      });

      test('insufficientSecurity is fatal', () {
        final alert = Alert.insufficientSecurity;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(
            alert.description, equals(AlertDescription.insufficientSecurity));
      });

      test('internalError is fatal', () {
        final alert = Alert.internalError;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(alert.description, equals(AlertDescription.internalError));
      });

      test('userCanceled is warning', () {
        final alert = Alert.userCanceled;
        expect(alert.level, equals(AlertLevel.warning));
        expect(alert.description, equals(AlertDescription.userCanceled));
      });

      test('noRenegotiation is warning', () {
        final alert = Alert.noRenegotiation;
        expect(alert.level, equals(AlertLevel.warning));
        expect(alert.description, equals(AlertDescription.noRenegotiation));
      });

      test('unsupportedExtension is fatal', () {
        final alert = Alert.unsupportedExtension;
        expect(alert.level, equals(AlertLevel.fatal));
        expect(
            alert.description, equals(AlertDescription.unsupportedExtension));
      });
    });

    test('isFatal returns true for fatal alerts', () {
      final fatal = Alert.fatal(AlertDescription.handshakeFailure);
      final warning = Alert.warning(AlertDescription.closeNotify);

      expect(fatal.isFatal, isTrue);
      expect(warning.isFatal, isFalse);
    });

    test('isWarning returns true for warning alerts', () {
      final fatal = Alert.fatal(AlertDescription.handshakeFailure);
      final warning = Alert.warning(AlertDescription.closeNotify);

      expect(warning.isWarning, isTrue);
      expect(fatal.isWarning, isFalse);
    });

    test('serialize produces 2-byte output', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );

      final bytes = alert.serialize();

      expect(bytes.length, equals(2));
      expect(bytes[0], equals(AlertLevel.fatal.value));
      expect(bytes[1], equals(AlertDescription.handshakeFailure.value));
    });

    test('parse creates Alert from bytes', () {
      final data = Uint8List.fromList([
        AlertLevel.warning.value,
        AlertDescription.closeNotify.value,
      ]);

      final alert = Alert.parse(data);

      expect(alert.level, equals(AlertLevel.warning));
      expect(alert.description, equals(AlertDescription.closeNotify));
    });

    test('parse throws on short data', () {
      final shortData = Uint8List(1);

      expect(
        () => Alert.parse(shortData),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('too short'),
        )),
      );
    });

    test('parse throws on unknown level', () {
      final data = Uint8List.fromList([99, AlertDescription.closeNotify.value]);

      expect(
        () => Alert.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unknown alert level'),
        )),
      );
    });

    test('parse throws on unknown description', () {
      final data = Uint8List.fromList([AlertLevel.fatal.value, 199]);

      expect(
        () => Alert.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unknown alert description'),
        )),
      );
    });

    test('roundtrip serialize/parse', () {
      final original = Alert.handshakeFailure;

      final bytes = original.serialize();
      final parsed = Alert.parse(bytes);

      expect(parsed.level, equals(original.level));
      expect(parsed.description, equals(original.description));
    });

    test('toString returns readable format', () {
      final alert = Alert.handshakeFailure;

      final str = alert.toString();
      expect(str, contains('Alert'));
      expect(str, contains('level'));
      expect(str, contains('description'));
    });

    test('equality compares level and description', () {
      final alert1 = Alert.fatal(AlertDescription.handshakeFailure);
      final alert2 = Alert.fatal(AlertDescription.handshakeFailure);
      final alert3 = Alert.warning(AlertDescription.closeNotify);

      expect(alert1 == alert2, isTrue);
      expect(alert1 == alert3, isFalse);
    });

    test('equality returns true for identical instance', () {
      final alert = Alert.handshakeFailure;
      expect(alert == alert, isTrue);
    });

    test('hashCode is consistent', () {
      final alert1 = Alert.fatal(AlertDescription.handshakeFailure);
      final alert2 = Alert.fatal(AlertDescription.handshakeFailure);

      expect(alert1.hashCode, equals(alert2.hashCode));
    });
  });
}
