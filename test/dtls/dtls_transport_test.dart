import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/dtls_transport.dart';
import 'package:webrtc_dart/src/dtls/dtls_transport_stub.dart';

void main() {
  group('DTLS Transport (Stub)', () {
    test('creates transport in new state', () {
      final dtls = DtlsTransportStub();

      expect(dtls.state, equals(DtlsState.newState));
      expect(dtls.role, equals(DtlsRole.auto));
      expect(dtls.localFingerprint, isNotNull);
      expect(dtls.localFingerprint.algorithm, equals('sha-256'));
      expect(dtls.localFingerprint.value, isNotEmpty);
    });

    test('fingerprint has correct format', () {
      final dtls = DtlsTransportStub();
      final fingerprint = dtls.localFingerprint.value;

      // SHA-256 fingerprint: 32 hex pairs separated by colons
      // Format: XX:XX:XX:...:XX (32 pairs = 95 characters total)
      expect(fingerprint, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    });

    test('each transport has unique fingerprint', () {
      final dtls1 = DtlsTransportStub();
      final dtls2 = DtlsTransportStub();

      expect(dtls1.localFingerprint.value, isNot(equals(dtls2.localFingerprint.value)));
    });

    test('sets remote fingerprint', () {
      final dtls = DtlsTransportStub();
      final remoteFingerprint = CertificateFingerprint(
        algorithm: 'sha-256',
        value: 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
      );

      expect(dtls.remoteFingerprint, isNull);

      dtls.setRemoteFingerprint(remoteFingerprint);

      expect(dtls.remoteFingerprint, equals(remoteFingerprint));
      expect(dtls.remoteFingerprint!.algorithm, equals('sha-256'));
    });

    test('starts as client', () async {
      final dtls = DtlsTransportStub();

      expect(dtls.state, equals(DtlsState.newState));

      await dtls.start(role: DtlsRole.client);

      expect(dtls.state, equals(DtlsState.connected));
      expect(dtls.role, equals(DtlsRole.client));
    });

    test('starts as server', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.server);

      expect(dtls.state, equals(DtlsState.connected));
      expect(dtls.role, equals(DtlsRole.server));
    });

    test('emits state change events', () async {
      final dtls = DtlsTransportStub();
      final states = <DtlsState>[];

      final subscription = dtls.onStateChanged.listen((state) {
        states.add(state);
      });

      await dtls.start(role: DtlsRole.client);
      await Future.delayed(Duration(milliseconds: 100));

      expect(states, contains(DtlsState.connecting));
      expect(states, contains(DtlsState.connected));

      await subscription.cancel();
      await dtls.close();
    });

    test('cannot start twice', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.client);

      expect(
        () => dtls.start(role: DtlsRole.server),
        throwsStateError,
      );

      await dtls.close();
    });

    test('cannot send before connected', () async {
      final dtls = DtlsTransportStub();
      final data = Uint8List.fromList([1, 2, 3, 4]);

      expect(
        () => dtls.send(data),
        throwsStateError,
      );

      await dtls.close();
    });

    test('can send after connected', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.client);

      final data = Uint8List.fromList([1, 2, 3, 4]);
      // Stub echoes data back
      await dtls.send(data);

      await dtls.close();
    });

    test('receives echoed data', () async {
      final dtls = DtlsTransportStub();
      final receivedData = <List<int>>[];

      final subscription = dtls.onData.listen((data) {
        receivedData.add(data);
      });

      await dtls.start(role: DtlsRole.client);

      final testData = Uint8List.fromList([1, 2, 3, 4]);
      await dtls.send(testData);
      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedData, hasLength(1));
      expect(receivedData[0], equals(testData));

      await subscription.cancel();
      await dtls.close();
    });

    test('cannot get SRTP keys before connected', () {
      final dtls = DtlsTransportStub();

      expect(
        () => dtls.getSrtpKeys(),
        throwsStateError,
      );
    });

    test('can get SRTP keys after connected', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.client);

      final keys = dtls.getSrtpKeys();

      expect(keys.localKey, hasLength(16)); // AES-128
      expect(keys.localSalt, hasLength(14)); // SRTP salt
      expect(keys.remoteKey, hasLength(16));
      expect(keys.remoteSalt, hasLength(14));

      await dtls.close();
    });

    test('SRTP keys are unique per connection', () async {
      final dtls1 = DtlsTransportStub();
      final dtls2 = DtlsTransportStub();

      await dtls1.start(role: DtlsRole.client);
      await dtls2.start(role: DtlsRole.server);

      final keys1 = dtls1.getSrtpKeys();
      final keys2 = dtls2.getSrtpKeys();

      expect(keys1.localKey, isNot(equals(keys2.localKey)));
      expect(keys1.remoteKey, isNot(equals(keys2.remoteKey)));

      await dtls1.close();
      await dtls2.close();
    });

    test('closes cleanly', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.client);
      expect(dtls.state, equals(DtlsState.connected));

      await dtls.close();
      expect(dtls.state, equals(DtlsState.closed));
    });

    test('can close multiple times', () async {
      final dtls = DtlsTransportStub();

      await dtls.start(role: DtlsRole.client);
      await dtls.close();
      await dtls.close(); // Should not throw

      expect(dtls.state, equals(DtlsState.closed));
    });
  });

  group('DtlsState', () {
    test('has all required states', () {
      expect(DtlsState.values, contains(DtlsState.newState));
      expect(DtlsState.values, contains(DtlsState.connecting));
      expect(DtlsState.values, contains(DtlsState.connected));
      expect(DtlsState.values, contains(DtlsState.failed));
      expect(DtlsState.values, contains(DtlsState.closed));
    });
  });

  group('DtlsRole', () {
    test('has all required roles', () {
      expect(DtlsRole.values, contains(DtlsRole.client));
      expect(DtlsRole.values, contains(DtlsRole.server));
      expect(DtlsRole.values, contains(DtlsRole.auto));
    });
  });

  group('CertificateFingerprint', () {
    test('creates fingerprint', () {
      final fp = CertificateFingerprint(
        algorithm: 'sha-256',
        value: 'AA:BB:CC:DD',
      );

      expect(fp.algorithm, equals('sha-256'));
      expect(fp.value, equals('AA:BB:CC:DD'));
    });

    test('toString formats correctly', () {
      final fp = CertificateFingerprint(
        algorithm: 'sha-256',
        value: 'AA:BB:CC:DD',
      );

      expect(fp.toString(), equals('sha-256 AA:BB:CC:DD'));
    });
  });
}
