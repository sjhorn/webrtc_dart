/// ICE Candidate Serialization Experiment
///
/// Compares different serialization approaches:
/// 1. String interpolation
/// 2. StringBuffer
/// 3. String concatenation with +
///
/// Run: dart run benchmark/micro/ice_serialize_experiment.dart

const iterations = 500000;
const warmup = 10000;

// Test data
const foundation = '6815297761';
const component = 1;
const transport = 'udp';
const priority = 2130706431;
const host = '192.168.1.100';
const port = 31102;
const type = 'host';
const generation = 0;
const ufrag = 'b7l3';

void main() {
  print('ICE Candidate Serialization Experiment');
  print('=' * 60);
  print('Iterations: $iterations\n');

  // Warm up
  for (var i = 0; i < warmup; i++) {
    serializeInterpolation();
    serializeStringBuffer();
    serializeConcatenation();
  }

  // Benchmark interpolation
  var sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    serializeInterpolation();
  }
  sw.stop();
  final interpTime = sw.elapsedMicroseconds;
  final interpOps = (iterations / interpTime * 1000000).round();
  print('String interpolation:');
  print('  ${interpOps} ops/sec');
  print('  ${(interpTime / iterations).toStringAsFixed(2)} µs/op\n');

  // Benchmark StringBuffer
  sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    serializeStringBuffer();
  }
  sw.stop();
  final bufferTime = sw.elapsedMicroseconds;
  final bufferOps = (iterations / bufferTime * 1000000).round();
  print('StringBuffer:');
  print('  ${bufferOps} ops/sec');
  print('  ${(bufferTime / iterations).toStringAsFixed(2)} µs/op\n');

  // Benchmark concatenation
  sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    serializeConcatenation();
  }
  sw.stop();
  final concatTime = sw.elapsedMicroseconds;
  final concatOps = (iterations / concatTime * 1000000).round();
  print('String += concatenation:');
  print('  ${concatOps} ops/sec');
  print('  ${(concatTime / iterations).toStringAsFixed(2)} µs/op\n');

  // Benchmark single interpolation (no conditionals)
  sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    serializeSingleInterpolation();
  }
  sw.stop();
  final singleTime = sw.elapsedMicroseconds;
  final singleOps = (iterations / singleTime * 1000000).round();
  print('Single string interpolation:');
  print('  ${singleOps} ops/sec');
  print('  ${(singleTime / iterations).toStringAsFixed(2)} µs/op\n');

  print('=' * 60);
  print('Comparison (vs StringBuffer):');
  print('  interpolation: ${(interpOps / bufferOps).toStringAsFixed(2)}x');
  print('  concatenation: ${(concatOps / bufferOps).toStringAsFixed(2)}x');
  print('  single interp: ${(singleOps / bufferOps).toStringAsFixed(2)}x');

  // Verify correctness
  print('\nVerifying correctness...');
  final r1 = serializeInterpolation();
  final r2 = serializeStringBuffer();
  final r3 = serializeConcatenation();
  final r4 = serializeSingleInterpolation();

  if (r1 == r2 && r2 == r3 && r3 == r4) {
    print('✓ All approaches produce identical results');
    print('  Result: $r1');
  } else {
    print('✗ Results differ!');
    print('  interp: $r1');
    print('  buffer: $r2');
    print('  concat: $r3');
    print('  single: $r4');
  }
}

/// String interpolation with conditionals
String serializeInterpolation() {
  var sdp = '$foundation $component $transport $priority $host $port typ $type';
  sdp += ' generation $generation';
  sdp += ' ufrag $ufrag';
  return sdp;
}

/// StringBuffer approach
String serializeStringBuffer() {
  final sb = StringBuffer()
    ..write(foundation)
    ..write(' ')
    ..write(component)
    ..write(' ')
    ..write(transport)
    ..write(' ')
    ..write(priority)
    ..write(' ')
    ..write(host)
    ..write(' ')
    ..write(port)
    ..write(' typ ')
    ..write(type)
    ..write(' generation ')
    ..write(generation)
    ..write(' ufrag ')
    ..write(ufrag);
  return sb.toString();
}

/// String += concatenation
String serializeConcatenation() {
  var sdp = foundation;
  sdp += ' ';
  sdp += component.toString();
  sdp += ' ';
  sdp += transport;
  sdp += ' ';
  sdp += priority.toString();
  sdp += ' ';
  sdp += host;
  sdp += ' ';
  sdp += port.toString();
  sdp += ' typ ';
  sdp += type;
  sdp += ' generation ';
  sdp += generation.toString();
  sdp += ' ufrag ';
  sdp += ufrag;
  return sdp;
}

/// Single string interpolation (no conditionals)
String serializeSingleInterpolation() {
  return '$foundation $component $transport $priority $host $port typ $type generation $generation ufrag $ufrag';
}
