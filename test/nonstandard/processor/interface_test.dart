import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/processor/interface.dart';

// Test implementation of Processor
class TestProcessor extends CallbackProcessor<int, String> {
  final String prefix;

  TestProcessor({this.prefix = 'value:'});

  @override
  List<String> processInput(int input) {
    return ['$prefix$input'];
  }

  @override
  Map<String, dynamic> toJson() {
    return {'prefix': prefix};
  }
}

// Test implementation that produces multiple outputs
class MultiOutputProcessor extends CallbackProcessor<int, int> {
  @override
  List<int> processInput(int input) {
    // Return input and input doubled
    return [input, input * 2];
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'multi'};
  }
}

// Test implementation that filters (returns empty sometimes)
class FilterProcessor extends CallbackProcessor<int, int> {
  @override
  List<int> processInput(int input) {
    // Only pass even numbers
    if (input % 2 == 0) {
      return [input];
    }
    return [];
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'filter', 'filter': 'even'};
  }
}

void main() {
  group('Processor interface', () {
    test('processInput returns list of outputs', () {
      final processor = TestProcessor();
      final outputs = processor.processInput(42);

      expect(outputs, equals(['value:42']));
    });

    test('toJson returns state', () {
      final processor = TestProcessor(prefix: 'test:');
      final json = processor.toJson();

      expect(json['prefix'], equals('test:'));
    });
  });

  group('CallbackProcessor', () {
    test('input method calls callback with outputs', () {
      final processor = TestProcessor();
      final received = <String>[];

      processor.pipe((output) => received.add(output));
      processor.input(100);

      expect(received, equals(['value:100']));
    });

    test('pipe returns processor for chaining', () {
      final processor = TestProcessor();

      final result = processor.pipe((_) {});

      expect(result, same(processor));
    });

    test('multiple inputs accumulate in callback', () {
      final processor = TestProcessor();
      final received = <String>[];

      processor.pipe(received.add);
      processor.input(1);
      processor.input(2);
      processor.input(3);

      expect(received, equals(['value:1', 'value:2', 'value:3']));
    });

    test('multi-output processor calls callback multiple times', () {
      final processor = MultiOutputProcessor();
      final received = <int>[];

      processor.pipe(received.add);
      processor.input(5);

      expect(received, equals([5, 10])); // 5 and 5*2
    });

    test('filter processor may produce no outputs', () {
      final processor = FilterProcessor();
      final received = <int>[];

      processor.pipe(received.add);
      processor.input(3); // Odd - filtered out
      processor.input(4); // Even - passed through

      expect(received, equals([4]));
    });

    test('destroy clears callback', () {
      final processor = TestProcessor();
      final received = <String>[];

      processor.pipe(received.add);
      processor.input(1);
      processor.destroy();
      processor.input(2);

      expect(received, equals(['value:1'])); // Only first input
    });

    test('destroy calls destructor', () {
      final processor = TestProcessor();
      var destructorCalled = false;

      processor.pipe((_) {}, () => destructorCalled = true);
      expect(destructorCalled, isFalse);

      processor.destroy();
      expect(destructorCalled, isTrue);
    });

    test('destructor only called once', () {
      final processor = TestProcessor();
      var callCount = 0;

      processor.pipe((_) {}, () => callCount++);
      processor.destroy();
      processor.destroy();

      expect(callCount, equals(1));
    });

    test('works without destructor', () {
      final processor = TestProcessor();
      final received = <String>[];

      processor.pipe(received.add); // No destructor
      processor.input(42);
      processor.destroy(); // Should not throw

      expect(received, equals(['value:42']));
    });
  });

  group('SimpleProcessorCallback interface', () {
    test('processor implements interface', () {
      final processor = TestProcessor();

      expect(processor, isA<SimpleProcessorCallback<int, String>>());
    });
  });
}
