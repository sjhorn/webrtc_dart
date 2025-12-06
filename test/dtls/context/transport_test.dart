import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart';

void main() {
  group('StreamDtlsTransport', () {
    test('construction creates open transport', () {
      final sentData = <Uint8List>[];
      final transport = StreamDtlsTransport(
        sendCallback: (data) => sentData.add(data),
      );

      expect(transport.isOpen, isTrue);
    });

    test('send invokes callback', () async {
      final sentData = <Uint8List>[];
      final transport = StreamDtlsTransport(
        sendCallback: (data) => sentData.add(data),
      );

      final testData = Uint8List.fromList([1, 2, 3, 4]);
      await transport.send(testData);

      expect(sentData.length, equals(1));
      expect(sentData[0], equals(testData));
    });

    test('send throws when transport is closed', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
      );

      await transport.close();

      expect(
        () async => await transport.send(Uint8List(4)),
        throwsA(isA<StateError>()),
      );
    });

    test('receive delivers data to onData stream', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
      );

      final received = <Uint8List>[];
      transport.onData.listen((data) => received.add(data));

      final testData = Uint8List.fromList([5, 6, 7, 8]);
      transport.receive(testData);

      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received[0], equals(testData));
    });

    test('receive ignores data when transport is closed', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
      );

      final received = <Uint8List>[];
      transport.onData.listen((data) => received.add(data));

      await transport.close();

      // This should be ignored
      transport.receive(Uint8List.fromList([1, 2, 3]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(received.isEmpty, isTrue);
    });

    test('close marks transport as not open', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
      );

      expect(transport.isOpen, isTrue);

      await transport.close();

      expect(transport.isOpen, isFalse);
    });

    test('close is idempotent', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
      );

      await transport.close();
      await transport.close(); // Should not throw

      expect(transport.isOpen, isFalse);
    });

    test('can use custom receive controller', () async {
      final customController = StreamController<Uint8List>.broadcast();
      final transport = StreamDtlsTransport(
        sendCallback: (data) {},
        receiveController: customController,
      );

      final received = <Uint8List>[];
      transport.onData.listen((data) => received.add(data));

      // Inject data via the custom controller
      customController.add(Uint8List.fromList([9, 10, 11]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));

      await transport.close();
    });
  });

  group('UdpDtlsTransport', () {
    test('construction creates open transport', () {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      expect(transport.isOpen, isTrue);
      expect(transport.remoteAddress, equals('192.168.1.1'));
      expect(transport.remotePort, equals(5000));
    });

    test('send invokes callback with remote address', () async {
      String? sentAddress;
      int? sentPort;
      Uint8List? sentData;

      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {
          sentData = data;
          sentAddress = addr;
          sentPort = port;
        },
        remoteAddress: '10.0.0.1',
        remotePort: 12345,
      );

      final testData = Uint8List.fromList([1, 2, 3, 4]);
      await transport.send(testData);

      expect(sentData, equals(testData));
      expect(sentAddress, equals('10.0.0.1'));
      expect(sentPort, equals(12345));
    });

    test('send throws when transport is closed', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '127.0.0.1',
        remotePort: 8080,
      );

      await transport.close();

      expect(
        () async => await transport.send(Uint8List(4)),
        throwsA(isA<StateError>()),
      );
    });

    test('receive delivers data to onData stream', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '127.0.0.1',
        remotePort: 8080,
      );

      final received = <Uint8List>[];
      transport.onData.listen((data) => received.add(data));

      final testData = Uint8List.fromList([5, 6, 7, 8]);
      transport.receive(testData);

      await Future.delayed(Duration(milliseconds: 10));

      expect(received.length, equals(1));
      expect(received[0], equals(testData));
    });

    test('receive ignores data when transport is closed', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '127.0.0.1',
        remotePort: 8080,
      );

      final received = <Uint8List>[];
      transport.onData.listen((data) => received.add(data));

      await transport.close();

      transport.receive(Uint8List.fromList([1, 2, 3]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(received.isEmpty, isTrue);
    });

    test('close marks transport as not open', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '127.0.0.1',
        remotePort: 8080,
      );

      expect(transport.isOpen, isTrue);

      await transport.close();

      expect(transport.isOpen, isFalse);
    });

    test('close is idempotent', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (data, addr, port) async {},
        remoteAddress: '127.0.0.1',
        remotePort: 8080,
      );

      await transport.close();
      await transport.close();

      expect(transport.isOpen, isFalse);
    });
  });
}
