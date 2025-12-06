import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello_done.dart';

void main() {
  group('ServerHelloDone', () {
    test('can be constructed', () {
      const done = ServerHelloDone();
      expect(done, isNotNull);
    });

    test('serialize returns empty bytes', () {
      const done = ServerHelloDone();
      final bytes = done.serialize();

      expect(bytes.length, equals(0));
    });

    test('parse accepts empty bytes', () {
      final done = ServerHelloDone.parse(Uint8List(0));

      expect(done, isA<ServerHelloDone>());
    });

    test('parse throws on non-empty bytes', () {
      expect(
        () => ServerHelloDone.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
    });

    test('roundtrip serialize/parse', () {
      const original = ServerHelloDone();
      final bytes = original.serialize();
      final parsed = ServerHelloDone.parse(bytes);

      expect(parsed, isA<ServerHelloDone>());
    });

    test('toString returns readable format', () {
      const done = ServerHelloDone();
      expect(done.toString(), equals('ServerHelloDone()'));
    });

    test('equality works correctly', () {
      const done1 = ServerHelloDone();
      const done2 = ServerHelloDone();

      expect(done1, equals(done2));
      expect(done1.hashCode, equals(done2.hashCode));
    });

    test('const instances are identical', () {
      const done1 = ServerHelloDone();
      const done2 = ServerHelloDone();

      expect(identical(done1, done2), isTrue);
    });
  });
}
