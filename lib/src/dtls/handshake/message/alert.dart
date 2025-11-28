import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// Alert message
/// RFC 5246 Section 7.2
///
/// enum { warning(1), fatal(2) } AlertLevel;
///
/// struct {
///   AlertLevel level;
///   AlertDescription description;
/// } Alert;
class Alert {
  final AlertLevel level;
  final AlertDescription description;

  const Alert({
    required this.level,
    required this.description,
  });

  /// Create a fatal alert
  factory Alert.fatal(AlertDescription description) {
    return Alert(
      level: AlertLevel.fatal,
      description: description,
    );
  }

  /// Create a warning alert
  factory Alert.warning(AlertDescription description) {
    return Alert(
      level: AlertLevel.warning,
      description: description,
    );
  }

  /// Common alerts
  static Alert get closeNotify => Alert.warning(AlertDescription.closeNotify);
  static Alert get unexpectedMessage => Alert.fatal(AlertDescription.unexpectedMessage);
  static Alert get badRecordMac => Alert.fatal(AlertDescription.badRecordMac);
  static Alert get decryptionFailed => Alert.fatal(AlertDescription.decryptionFailed);
  static Alert get recordOverflow => Alert.fatal(AlertDescription.recordOverflow);
  static Alert get decompressFailed => Alert.fatal(AlertDescription.decompressFailed);
  static Alert get handshakeFailure => Alert.fatal(AlertDescription.handshakeFailure);
  static Alert get badCertificate => Alert.fatal(AlertDescription.badCertificate);
  static Alert get unsupportedCertificate => Alert.fatal(AlertDescription.unsupportedCertificate);
  static Alert get certificateRevoked => Alert.fatal(AlertDescription.certificateRevoked);
  static Alert get certificateExpired => Alert.fatal(AlertDescription.certificateExpired);
  static Alert get certificateUnknown => Alert.fatal(AlertDescription.certificateUnknown);
  static Alert get illegalParameter => Alert.fatal(AlertDescription.illegalParameter);
  static Alert get unknownCa => Alert.fatal(AlertDescription.unknownCa);
  static Alert get accessDenied => Alert.fatal(AlertDescription.accessDenied);
  static Alert get decodeError => Alert.fatal(AlertDescription.decodeError);
  static Alert get decryptError => Alert.fatal(AlertDescription.decryptError);
  static Alert get protocolVersion => Alert.fatal(AlertDescription.protocolVersion);
  static Alert get insufficientSecurity => Alert.fatal(AlertDescription.insufficientSecurity);
  static Alert get internalError => Alert.fatal(AlertDescription.internalError);
  static Alert get userCanceled => Alert.warning(AlertDescription.userCanceled);
  static Alert get noRenegotiation => Alert.warning(AlertDescription.noRenegotiation);
  static Alert get unsupportedExtension => Alert.fatal(AlertDescription.unsupportedExtension);

  /// Check if this is a fatal alert
  bool get isFatal => level == AlertLevel.fatal;

  /// Check if this is a warning alert
  bool get isWarning => level == AlertLevel.warning;

  /// Serialize to bytes
  Uint8List serialize() {
    final result = Uint8List(2);
    result[0] = level.value;
    result[1] = description.value;
    return result;
  }

  /// Parse from bytes
  static Alert parse(Uint8List data) {
    if (data.length < 2) {
      throw FormatException('Alert too short: ${data.length} bytes');
    }

    final levelValue = data[0];
    final descValue = data[1];

    final level = AlertLevel.fromValue(levelValue);
    final description = AlertDescription.fromValue(descValue);

    if (level == null) {
      throw FormatException('Unknown alert level: $levelValue');
    }

    if (description == null) {
      throw FormatException('Unknown alert description: $descValue');
    }

    return Alert(
      level: level,
      description: description,
    );
  }

  @override
  String toString() {
    return 'Alert(level=$level, description=$description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Alert) return false;
    return level == other.level && description == other.description;
  }

  @override
  int get hashCode => Object.hash(level, description);
}
