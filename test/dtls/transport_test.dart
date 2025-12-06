import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart';

void main() {
  group('StreamDtlsTransport', () {
    test('construction creates open transport', () {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      expect(transport.isOpen, isTrue);
    });

    test('send calls sendCallback', () async {
      Uint8List? sentData;
      final transport = StreamDtlsTransport(
        sendCallback: (data) {
          sentData = data;
        },
      );

      final testData = Uint8List.fromList([1, 2, 3, 4]);
      await transport.send(testData);

      expect(sentData, equals(testData));
    });

    test('send throws when transport is closed', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      await transport.close();

      expect(
        () => transport.send(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('receive adds data to stream', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      final receivedData = <Uint8List>[];
      transport.onData.listen((data) {
        receivedData.add(data);
      });

      final testData1 = Uint8List.fromList([1, 2, 3]);
      final testData2 = Uint8List.fromList([4, 5, 6]);

      transport.receive(testData1);
      transport.receive(testData2);

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData.length, equals(2));
      expect(receivedData[0], equals(testData1));
      expect(receivedData[1], equals(testData2));
    });

    test('receive does nothing when transport is closed', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      final receivedData = <Uint8List>[];
      transport.onData.listen((data) {
        receivedData.add(data);
      });

      await transport.close();
      transport.receive(Uint8List.fromList([1, 2, 3]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData, isEmpty);
    });

    test('close sets isOpen to false', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      expect(transport.isOpen, isTrue);

      await transport.close();

      expect(transport.isOpen, isFalse);
    });

    test('close is idempotent', () async {
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
      );

      await transport.close();
      await transport.close(); // Should not throw

      expect(transport.isOpen, isFalse);
    });

    test('can use custom receive controller', () async {
      final controller = StreamController<Uint8List>.broadcast();
      final transport = StreamDtlsTransport(
        sendCallback: (_) {},
        receiveController: controller,
      );

      final receivedData = <Uint8List>[];
      transport.onData.listen((data) {
        receivedData.add(data);
      });

      // Add data directly to controller
      controller.add(Uint8List.fromList([7, 8, 9]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData.length, equals(1));
      expect(receivedData[0], equals(Uint8List.fromList([7, 8, 9])));

      await transport.close();
    });
  });

  group('UdpDtlsTransport', () {
    test('construction creates open transport', () {
      final transport = UdpDtlsTransport(
        sendCallback: (_, __, ___) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      expect(transport.isOpen, isTrue);
      expect(transport.remoteAddress, equals('192.168.1.1'));
      expect(transport.remotePort, equals(5000));
    });

    test('send calls sendCallback with correct address and port', () async {
      String? sentAddress;
      int? sentPort;
      Uint8List? sentData;

      final transport = UdpDtlsTransport(
        sendCallback: (data, address, port) async {
          sentData = data;
          sentAddress = address;
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
        sendCallback: (_, __, ___) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      await transport.close();

      expect(
        () => transport.send(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('receive adds data to stream', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (_, __, ___) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      final receivedData = <Uint8List>[];
      transport.onData.listen((data) {
        receivedData.add(data);
      });

      transport.receive(Uint8List.fromList([10, 20, 30]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData.length, equals(1));
      expect(receivedData[0], equals(Uint8List.fromList([10, 20, 30])));
    });

    test('receive does nothing when transport is closed', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (_, __, ___) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      final receivedData = <Uint8List>[];
      transport.onData.listen((data) {
        receivedData.add(data);
      });

      await transport.close();
      transport.receive(Uint8List.fromList([1, 2, 3]));

      await Future.delayed(Duration(milliseconds: 10));

      expect(receivedData, isEmpty);
    });

    test('close is idempotent', () async {
      final transport = UdpDtlsTransport(
        sendCallback: (_, __, ___) async {},
        remoteAddress: '192.168.1.1',
        remotePort: 5000,
      );

      await transport.close();
      await transport.close();

      expect(transport.isOpen, isFalse);
    });
  });
}
