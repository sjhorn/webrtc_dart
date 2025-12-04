#!/bin/bash
pkill -f "js_answerer" 2>/dev/null || true
pkill -f "dart run" 2>/dev/null || true
sleep 1
rm -rf interop/signals
mkdir -p interop/signals

# Run JS answerer with debug logs
export DEBUG="werift*"
node interop/js_answerer.mjs 2>&1 &
JS_PID=$!
sleep 2

# Run Dart offerer
timeout 40 dart run interop/dart_offerer.dart 2>&1

# Clean up
kill $JS_PID 2>/dev/null || true
