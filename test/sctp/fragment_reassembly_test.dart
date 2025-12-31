import 'dart:typed_data';

import 'package:test/test.dart';

// Import test helpers that provide access to InboundStream
import 'fragment_reassembly_test_helper.dart';

void main() {
  group('Fragment Reassembly', () {
    group('InboundStream', () {
      test('delivers unfragmented message immediately', () {
        final stream = createInboundStream();
        final chunk = createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51, // WebRTC string PPID
          userData: Uint8List.fromList([1, 2, 3, 4, 5]),
          beginningFragment: true,
          endFragment: true,
        );

        stream.addChunk(chunk);
        final messages = stream.popMessages().toList();

        expect(messages.length, 1);
        expect(messages[0].$1, 0); // streamId
        expect(messages[0].$2, [1, 2, 3, 4, 5]); // userData
        expect(messages[0].$3, 51); // ppid
      });

      test('reassembles two fragments', () {
        final stream = createInboundStream();

        // First fragment
        final chunk1 = createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2, 3]),
          beginningFragment: true,
          endFragment: false,
        );

        // Last fragment
        final chunk2 = createDataChunk(
          tsn: 2,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([4, 5, 6]),
          beginningFragment: false,
          endFragment: true,
        );

        stream.addChunk(chunk1);
        var messages = stream.popMessages().toList();
        expect(messages.length, 0); // Not complete yet

        stream.addChunk(chunk2);
        messages = stream.popMessages().toList();
        expect(messages.length, 1);
        expect(messages[0].$2, [1, 2, 3, 4, 5, 6]); // Reassembled data
      });

      test('reassembles three fragments', () {
        final stream = createInboundStream();

        // First fragment
        stream.addChunk(createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2]),
          beginningFragment: true,
          endFragment: false,
        ));

        // Middle fragment
        stream.addChunk(createDataChunk(
          tsn: 2,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([3, 4]),
          beginningFragment: false,
          endFragment: false,
        ));

        // Last fragment
        stream.addChunk(createDataChunk(
          tsn: 3,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([5, 6]),
          beginningFragment: false,
          endFragment: true,
        ));

        final messages = stream.popMessages().toList();
        expect(messages.length, 1);
        expect(messages[0].$2, [1, 2, 3, 4, 5, 6]);
      });

      test('handles out-of-order fragments for ordered delivery', () {
        final stream = createInboundStream();

        // Add last fragment first
        stream.addChunk(createDataChunk(
          tsn: 2,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([4, 5, 6]),
          beginningFragment: false,
          endFragment: true,
        ));

        var messages = stream.popMessages().toList();
        expect(messages.length, 0); // Can't deliver without first fragment

        // Now add first fragment
        stream.addChunk(createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2, 3]),
          beginningFragment: true,
          endFragment: false,
        ));

        messages = stream.popMessages().toList();
        expect(messages.length, 1);
        expect(messages[0].$2, [1, 2, 3, 4, 5, 6]);
      });

      test('handles multiple messages in order', () {
        final stream = createInboundStream();

        // First message (unfragmented)
        stream.addChunk(createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2, 3]),
          beginningFragment: true,
          endFragment: true,
        ));

        // Second message (unfragmented)
        stream.addChunk(createDataChunk(
          tsn: 2,
          streamId: 0,
          streamSeq: 1,
          ppid: 51,
          userData: Uint8List.fromList([4, 5, 6]),
          beginningFragment: true,
          endFragment: true,
        ));

        final messages = stream.popMessages().toList();
        expect(messages.length, 2);
        expect(messages[0].$2, [1, 2, 3]);
        expect(messages[1].$2, [4, 5, 6]);
      });

      test('waits for missing middle fragment', () {
        final stream = createInboundStream();

        // First fragment
        stream.addChunk(createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2]),
          beginningFragment: true,
          endFragment: false,
        ));

        // Last fragment (missing middle)
        stream.addChunk(createDataChunk(
          tsn: 3,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([5, 6]),
          beginningFragment: false,
          endFragment: true,
        ));

        var messages = stream.popMessages().toList();
        expect(messages.length, 0); // Missing TSN 2

        // Add missing middle fragment
        stream.addChunk(createDataChunk(
          tsn: 2,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([3, 4]),
          beginningFragment: false,
          endFragment: false,
        ));

        messages = stream.popMessages().toList();
        expect(messages.length, 1);
        expect(messages[0].$2, [1, 2, 3, 4, 5, 6]);
      });

      test('ignores duplicate chunks', () {
        final stream = createInboundStream();

        final chunk = createDataChunk(
          tsn: 1,
          streamId: 0,
          streamSeq: 0,
          ppid: 51,
          userData: Uint8List.fromList([1, 2, 3]),
          beginningFragment: true,
          endFragment: true,
        );

        stream.addChunk(chunk);
        stream.addChunk(chunk); // Duplicate

        final messages = stream.popMessages().toList();
        expect(messages.length, 1);
      });

      test('handles large fragmented message', () {
        final stream = createInboundStream();
        const fragmentSize = 1024;
        const numFragments = 5;

        // Create a large message split into fragments
        for (var i = 0; i < numFragments; i++) {
          final userData = Uint8List(fragmentSize);
          for (var j = 0; j < fragmentSize; j++) {
            userData[j] = (i * fragmentSize + j) & 0xFF;
          }

          stream.addChunk(createDataChunk(
            tsn: i + 1,
            streamId: 0,
            streamSeq: 0,
            ppid: 51,
            userData: userData,
            beginningFragment: i == 0,
            endFragment: i == numFragments - 1,
          ));
        }

        final messages = stream.popMessages().toList();
        expect(messages.length, 1);
        expect(messages[0].$2.length, fragmentSize * numFragments);
      });
    });
  });
}
