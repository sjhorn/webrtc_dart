/// Processor Interface - Base interfaces for media processing pipeline
///
/// Provides abstract processor interfaces for building media processing
/// pipelines with callback and transformer patterns.
///
/// Ported from werift-webrtc interface.ts
library;

/// Base processor interface for input/output transformation
///
/// Processors take input data and produce zero or more output items.
abstract class Processor<Input, Output> {
  /// Process input and return list of outputs
  List<Output> processInput(Input input);

  /// Convert processor state to JSON for debugging/logging
  Map<String, dynamic> toJson();
}

/// Audio/Video processor interface for handling both media types
abstract class AVProcessor<Input> {
  /// Process audio input
  void processAudioInput(Input input);

  /// Process video input
  void processVideoInput(Input input);

  /// Convert processor state to JSON
  Map<String, dynamic> toJson();
}

/// Simple processor callback interface for pipeline-style processing
///
/// Supports chaining via [pipe] method and cleanup via [destroy].
abstract class SimpleProcessorCallback<Input, Output> {
  /// Pipe output to a callback function
  ///
  /// Returns this processor for method chaining.
  /// Optional [destructor] is called when [destroy] is invoked.
  SimpleProcessorCallback<Input, Output> pipe(
    void Function(Output output) callback, [
    void Function()? destructor,
  ]);

  /// Send input to the processor
  void input(Input data);

  /// Clean up resources and disconnect callbacks
  void destroy();

  /// Convert processor state to JSON
  Map<String, dynamic> toJson();
}

/// Mixin to add callback-style interface to a [Processor]
///
/// Provides a simple way to convert batch-style processors to
/// callback-style processing.
mixin SimpleProcessorCallbackMixin<Input, Output>
    on Processor<Input, Output>
    implements SimpleProcessorCallback<Input, Output> {
  void Function(Output output)? _callback;
  void Function()? _destructor;

  @override
  SimpleProcessorCallback<Input, Output> pipe(
    void Function(Output output) callback, [
    void Function()? destructor,
  ]) {
    _callback = callback;
    _destructor = destructor;
    return this;
  }

  @override
  void input(Input data) {
    for (final output in processInput(data)) {
      _callback?.call(output);
    }
  }

  @override
  void destroy() {
    _destructor?.call();
    _destructor = null;
    _callback = null;
  }
}

/// Base class for processors with callback support
///
/// Extend this class to create processors that can be used in
/// both batch and callback-style pipelines.
abstract class CallbackProcessor<Input, Output>
    implements Processor<Input, Output>, SimpleProcessorCallback<Input, Output> {
  void Function(Output output)? _callback;
  void Function()? _destructor;

  @override
  SimpleProcessorCallback<Input, Output> pipe(
    void Function(Output output) callback, [
    void Function()? destructor,
  ]) {
    _callback = callback;
    _destructor = destructor;
    return this;
  }

  @override
  void input(Input data) {
    for (final output in processInput(data)) {
      _callback?.call(output);
    }
  }

  @override
  void destroy() {
    _destructor?.call();
    _destructor = null;
    _callback = null;
  }

  @override
  List<Output> processInput(Input input);

  @override
  Map<String, dynamic> toJson();
}
