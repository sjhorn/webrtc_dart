import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

void main() {
  group('ExtendedMasterSecretExtension', () {
    test('constructor creates extension', () {
      final ext = ExtendedMasterSecretExtension();
      expect(ext, isNotNull);
    });

    test('type returns extendedMasterSecret', () {
      final ext = ExtendedMasterSecretExtension();
      expect(ext.type, equals(ExtensionType.extendedMasterSecret));
    });

    test('serializeData returns empty bytes', () {
      final ext = ExtendedMasterSecretExtension();
      final data = ext.serializeData();
      expect(data.length, equals(0));
    });

    test('parse with empty data succeeds', () {
      final ext = ExtendedMasterSecretExtension.parse(Uint8List(0));
      expect(ext, isA<ExtendedMasterSecretExtension>());
    });

    test('parse with non-empty data throws', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        () => ExtendedMasterSecretExtension.parse(data),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('no data'),
        )),
      );
    });

    test('toString returns readable format', () {
      final ext = ExtendedMasterSecretExtension();
      final str = ext.toString();
      expect(str, contains('ExtendedMasterSecretExtension'));
    });

    test('roundtrip serialize/parse', () {
      final original = ExtendedMasterSecretExtension();
      final data = original.serializeData();
      final parsed = ExtendedMasterSecretExtension.parse(data);
      expect(parsed.type, equals(original.type));
    });
  });
}
