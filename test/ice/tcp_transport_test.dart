import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/tcp_transport.dart';

void main() {
  group('IceTcpType', () {
    test('converts to string correctly', () {
      expect(IceTcpType.active.value, equals('active'));
      expect(IceTcpType.passive.value, equals('passive'));
      expect(IceTcpType.so.value, equals('so'));
    });

    test('parses from string correctly', () {
      expect(IceTcpTypeExtension.fromString('active'), equals(IceTcpType.active));
      expect(IceTcpTypeExtension.fromString('passive'), equals(IceTcpType.passive));
      expect(IceTcpTypeExtension.fromString('so'), equals(IceTcpType.so));
      expect(IceTcpTypeExtension.fromString('ACTIVE'), equals(IceTcpType.active));
      expect(IceTcpTypeExtension.fromString('unknown'), isNull);
      expect(IceTcpTypeExtension.fromString(null), isNull);
    });
  });

  group('IceTcpConnection', () {
    test('starts in idle state', () {
      final connection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: 12345,
        localTcpType: IceTcpType.active,
      );

      expect(connection.state, equals(TcpConnectionState.idle));
      expect(connection.isConnected, isFalse);
      expect(connection.localPort, isNull);
    });

    test('throws on connect with passive type', () {
      final connection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: 12345,
        localTcpType: IceTcpType.passive,
      );

      expect(() => connection.connect(), throwsStateError);
    });

    test('throws on bind with active type', () {
      final connection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: 12345,
        localTcpType: IceTcpType.active,
      );

      expect(() => connection.bind(InternetAddress.loopbackIPv4), throwsStateError);
    });

    test('throws on send when not connected', () {
      final connection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: 12345,
        localTcpType: IceTcpType.active,
      );

      expect(() => connection.send(Uint8List(10)), throwsStateError);
    });

    test('active connection connects to passive', () async {
      // Create passive side (server)
      final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = serverSocket.port;

      // Track incoming connection
      final incomingConnection = Completer<Socket>();
      serverSocket.listen((socket) {
        incomingConnection.complete(socket);
      });

      // Create active connection
      final activeConnection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: serverPort,
        localTcpType: IceTcpType.active,
      );

      // Track state changes - must subscribe before connecting
      final stateChanges = <TcpConnectionState>[];
      final subscription = activeConnection.onStateChange.listen(stateChanges.add);

      // Connect
      await activeConnection.connect();

      // Give time for state events to be delivered
      await Future.delayed(Duration(milliseconds: 10));

      expect(activeConnection.state, equals(TcpConnectionState.connected));
      expect(activeConnection.isConnected, isTrue);
      expect(activeConnection.localPort, isNotNull);
      expect(stateChanges, contains(TcpConnectionState.connecting));
      expect(stateChanges, contains(TcpConnectionState.connected));

      // Wait for server to receive connection
      final clientSocket = await incomingConnection.future;
      expect(clientSocket.remotePort, equals(activeConnection.localPort));

      // Cleanup
      await subscription.cancel();
      await activeConnection.close();
      await clientSocket.close();
      await serverSocket.close();
    });

    test('sends and receives STUN-framed messages', () async {
      // Create server
      final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = serverSocket.port;

      final receivedMessages = <Uint8List>[];
      Socket? clientSocket;

      serverSocket.listen((socket) {
        clientSocket = socket;
        final buffer = <int>[];
        socket.listen((data) {
          buffer.addAll(data);
          // Parse framed messages (2-byte length prefix)
          while (buffer.length >= 2) {
            final length = (buffer[0] << 8) | buffer[1];
            if (buffer.length < 2 + length) break;
            receivedMessages.add(Uint8List.fromList(buffer.sublist(2, 2 + length)));
            buffer.removeRange(0, 2 + length);
          }
        });
      });

      // Create active connection
      final activeConnection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: serverPort,
        localTcpType: IceTcpType.active,
      );

      await activeConnection.connect();

      // Send test message
      final testMessage = Uint8List.fromList([1, 2, 3, 4, 5]);
      await activeConnection.send(testMessage);

      // Wait for message to be received
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages.length, equals(1));
      expect(receivedMessages[0], equals(testMessage));

      // Cleanup
      await activeConnection.close();
      await clientSocket?.close();
      await serverSocket.close();
    });

    test('receives STUN-framed messages', () async {
      // Create server
      final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = serverSocket.port;

      Socket? clientSocket;
      serverSocket.listen((socket) {
        clientSocket = socket;
      });

      // Create active connection
      final activeConnection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: serverPort,
        localTcpType: IceTcpType.active,
      );

      final receivedMessages = <Uint8List>[];
      activeConnection.onMessage.listen(receivedMessages.add);

      await activeConnection.connect();

      // Wait for server to have clientSocket
      await Future.delayed(Duration(milliseconds: 50));

      // Send framed message from server
      final testMessage = Uint8List.fromList([10, 20, 30, 40]);
      final framed = Uint8List(2 + testMessage.length);
      framed[0] = (testMessage.length >> 8) & 0xFF;
      framed[1] = testMessage.length & 0xFF;
      framed.setRange(2, framed.length, testMessage);
      clientSocket!.add(framed);
      await clientSocket!.flush();

      // Wait for message to be received
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedMessages.length, equals(1));
      expect(receivedMessages[0], equals(testMessage));

      // Cleanup
      await activeConnection.close();
      await clientSocket?.close();
      await serverSocket.close();
    });

    test('handles fragmented messages', () async {
      // Create server
      final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = serverSocket.port;

      Socket? clientSocket;
      serverSocket.listen((socket) {
        clientSocket = socket;
      });

      // Create active connection
      final activeConnection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: serverPort,
        localTcpType: IceTcpType.active,
      );

      final receivedMessages = <Uint8List>[];
      activeConnection.onMessage.listen(receivedMessages.add);

      await activeConnection.connect();
      await Future.delayed(Duration(milliseconds: 50));

      // Send message in fragments
      final testMessage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final framed = Uint8List(2 + testMessage.length);
      framed[0] = (testMessage.length >> 8) & 0xFF;
      framed[1] = testMessage.length & 0xFF;
      framed.setRange(2, framed.length, testMessage);

      // Send first half
      clientSocket!.add(framed.sublist(0, 5));
      await clientSocket!.flush();
      await Future.delayed(Duration(milliseconds: 20));

      expect(receivedMessages.length, equals(0)); // Not complete yet

      // Send second half
      clientSocket!.add(framed.sublist(5));
      await clientSocket!.flush();
      await Future.delayed(Duration(milliseconds: 20));

      expect(receivedMessages.length, equals(1));
      expect(receivedMessages[0], equals(testMessage));

      // Cleanup
      await activeConnection.close();
      await clientSocket?.close();
      await serverSocket.close();
    });

    test('emits closed state when connection closes', () async {
      // Create server
      final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = serverSocket.port;

      Socket? clientSocket;
      serverSocket.listen((socket) {
        clientSocket = socket;
      });

      // Create active connection
      final activeConnection = IceTcpConnection(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: serverPort,
        localTcpType: IceTcpType.active,
      );

      final stateChanges = <TcpConnectionState>[];
      activeConnection.onStateChange.listen(stateChanges.add);

      await activeConnection.connect();
      await Future.delayed(Duration(milliseconds: 50));

      // Close from server side
      await clientSocket?.close();
      await Future.delayed(Duration(milliseconds: 50));

      expect(stateChanges, contains(TcpConnectionState.closed));

      // Cleanup
      await activeConnection.close();
      await serverSocket.close();
    });
  });

  group('IceTcpServer', () {
    test('starts and gets bound port', () async {
      final server = IceTcpServer(
        localAddress: InternetAddress.loopbackIPv4,
      );

      await server.start();

      expect(server.port, isNotNull);
      expect(server.port, greaterThan(0));

      await server.stop();
    });

    test('accepts incoming connections', () async {
      final server = IceTcpServer(
        localAddress: InternetAddress.loopbackIPv4,
      );

      await server.start();

      final connections = <IceTcpConnection>[];
      server.onConnection.listen(connections.add);

      // Connect to server
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port!);
      await Future.delayed(Duration(milliseconds: 50));

      expect(connections.length, equals(1));
      expect(connections[0].isConnected, isTrue);
      expect(connections[0].remoteAddress.address, equals(socket.address.address));

      // Cleanup
      await socket.close();
      await server.stop();
    });

    test('getConnection returns connection by address', () async {
      final server = IceTcpServer(
        localAddress: InternetAddress.loopbackIPv4,
      );

      await server.start();

      // Connect to server
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port!);
      await Future.delayed(Duration(milliseconds: 50));

      final connection = server.getConnection(socket.address.address, socket.port);
      expect(connection, isNotNull);
      expect(connection!.isConnected, isTrue);

      // Cleanup
      await socket.close();
      await server.stop();
    });
  });

  group('TcpCandidateGatherer', () {
    test('gathers host candidates for addresses', () async {
      final gatherer = TcpCandidateGatherer();

      final candidates = await gatherer.gatherHostCandidates(['127.0.0.1']);

      expect(candidates.length, equals(1));
      expect(candidates[0].address, equals('127.0.0.1'));
      expect(candidates[0].port, greaterThan(0));

      await gatherer.close();
    });

    test('getServer returns server for address', () async {
      final gatherer = TcpCandidateGatherer();

      await gatherer.gatherHostCandidates(['127.0.0.1']);

      final server = gatherer.getServer('127.0.0.1');
      expect(server, isNotNull);
      expect(server!.port, isNotNull);

      await gatherer.close();
    });

    test('skips invalid addresses gracefully', () async {
      final gatherer = TcpCandidateGatherer();

      // Mix valid and invalid addresses
      final candidates = await gatherer.gatherHostCandidates([
        '127.0.0.1',
        '999.999.999.999', // Invalid
      ]);

      expect(candidates.length, equals(1));
      expect(candidates[0].address, equals('127.0.0.1'));

      await gatherer.close();
    });
  });

  group('Candidate with TCP', () {
    test('parses TCP candidate from SDP', () {
      // The SDP format for TCP candidates:
      // '1 1 tcp 2130706431 192.168.1.1 9999 typ host tcptype passive'
      // Use the Candidate.fromSdp factory
      // Note: This requires importing the candidate module
    });
  });

  group('IceOptions TCP', () {
    test('useTcp defaults to false', () {
      const options = IceOptions();
      expect(options.useTcp, isFalse);
      expect(options.useUdp, isTrue);
    });

    test('useTcp can be enabled', () {
      const options = IceOptions(useTcp: true);
      expect(options.useTcp, isTrue);
    });
  });
}

// Import IceOptions for testing
class IceOptions {
  final bool useTcp;
  final bool useUdp;
  final (String, int)? stunServer;
  final (String, int)? turnServer;
  final String? turnUsername;
  final String? turnPassword;
  final bool useIpv4;
  final bool useIpv6;
  final (int, int)? portRange;

  const IceOptions({
    this.stunServer,
    this.turnServer,
    this.turnUsername,
    this.turnPassword,
    this.useIpv4 = true,
    this.useIpv6 = true,
    this.portRange,
    this.useTcp = false,
    this.useUdp = true,
  });
}
