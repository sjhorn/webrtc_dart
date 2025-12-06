import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';

void main() {
  group('AlertLevel', () {
    test('values have correct codes', () {
      expect(AlertLevel.warning.value, equals(1));
      expect(AlertLevel.fatal.value, equals(2));
    });

    test('fromValue returns correct level', () {
      expect(AlertLevel.fromValue(1), equals(AlertLevel.warning));
      expect(AlertLevel.fromValue(2), equals(AlertLevel.fatal));
    });

    test('fromValue returns null for unknown value', () {
      expect(AlertLevel.fromValue(0), isNull);
      expect(AlertLevel.fromValue(99), isNull);
    });
  });

  group('AlertDescription', () {
    test('common values have correct codes', () {
      expect(AlertDescription.closeNotify.value, equals(0));
      expect(AlertDescription.unexpectedMessage.value, equals(10));
      expect(AlertDescription.badRecordMac.value, equals(20));
      expect(AlertDescription.handshakeFailure.value, equals(40));
      expect(AlertDescription.badCertificate.value, equals(42));
      expect(AlertDescription.certificateExpired.value, equals(45));
      expect(AlertDescription.unknownCa.value, equals(48));
      expect(AlertDescription.decryptError.value, equals(51));
    });

    test('fromValue returns correct description', () {
      expect(AlertDescription.fromValue(0), equals(AlertDescription.closeNotify));
      expect(
          AlertDescription.fromValue(40), equals(AlertDescription.handshakeFailure));
      expect(AlertDescription.fromValue(48), equals(AlertDescription.unknownCa));
    });

    test('fromValue returns null for unknown value', () {
      expect(AlertDescription.fromValue(99), isNull);
    });
  });

  group('Alert', () {
    test('construction with level and description', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.handshakeFailure));
    });

    test('getter closeNotify creates correct alert', () {
      final alert = Alert.closeNotify;

      expect(alert.level, equals(AlertLevel.warning));
      expect(alert.description, equals(AlertDescription.closeNotify));
    });

    test('getter handshakeFailure creates correct alert', () {
      final alert = Alert.handshakeFailure;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.handshakeFailure));
    });

    test('getter badCertificate creates correct alert', () {
      final alert = Alert.badCertificate;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.badCertificate));
    });

    test('getter certificateExpired creates correct alert', () {
      final alert = Alert.certificateExpired;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.certificateExpired));
    });

    test('getter unknownCa creates correct alert', () {
      final alert = Alert.unknownCa;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.unknownCa));
    });

    test('getter decryptError creates correct alert', () {
      final alert = Alert.decryptError;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.decryptError));
    });

    test('getter unexpectedMessage creates correct alert', () {
      final alert = Alert.unexpectedMessage;

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.unexpectedMessage));
    });

    test('serialize creates 2-byte output', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );

      final bytes = alert.serialize();

      expect(bytes.length, equals(2));
      expect(bytes[0], equals(2)); // fatal = 2
      expect(bytes[1], equals(40)); // handshake_failure = 40
    });

    test('parse creates valid alert', () {
      final bytes = Uint8List.fromList([2, 40]);
      final alert = Alert.parse(bytes);

      expect(alert.level, equals(AlertLevel.fatal));
      expect(alert.description, equals(AlertDescription.handshakeFailure));
    });

    test('parse throws on too short data', () {
      expect(
        () => Alert.parse(Uint8List.fromList([1])),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on unknown level', () {
      expect(
        () => Alert.parse(Uint8List.fromList([99, 40])),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on unknown description', () {
      expect(
        () => Alert.parse(Uint8List.fromList([2, 99])),
        throwsA(isA<FormatException>()),
      );
    });

    test('roundtrip serialize/parse', () {
      final original = Alert(
        level: AlertLevel.warning,
        description: AlertDescription.closeNotify,
      );

      final bytes = original.serialize();
      final parsed = Alert.parse(bytes);

      expect(parsed.level, equals(original.level));
      expect(parsed.description, equals(original.description));
    });

    test('isFatal returns true for fatal alerts', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );

      expect(alert.isFatal, isTrue);
    });

    test('isFatal returns false for warning alerts', () {
      final alert = Alert(
        level: AlertLevel.warning,
        description: AlertDescription.closeNotify,
      );

      expect(alert.isFatal, isFalse);
    });

    test('toString returns readable format', () {
      final alert = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.badCertificate,
      );

      final str = alert.toString();
      expect(str, contains('Alert'));
      expect(str, contains('fatal'));
      expect(str, contains('badCertificate'));
    });

    test('equality works correctly', () {
      final alert1 = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );
      final alert2 = Alert(
        level: AlertLevel.fatal,
        description: AlertDescription.handshakeFailure,
      );
      final alert3 = Alert(
        level: AlertLevel.warning,
        description: AlertDescription.closeNotify,
      );

      expect(alert1, equals(alert2));
      expect(alert1, isNot(equals(alert3)));
      expect(alert1.hashCode, equals(alert2.hashCode));
    });
  });
}
