#!/usr/bin/env node
/**
 * Camera Permission Test
 *
 * Tests if we can get camera access in Playwright for each browser
 * using the same patterns as our working media tests.
 *
 * Usage:
 *   node camera_permission_test.mjs [browser]
 *   node camera_permission_test.mjs          # Test all browsers
 *   node camera_permission_test.mjs chrome   # Test Chrome only
 *   node camera_permission_test.mjs firefox  # Test Firefox only
 *   node camera_permission_test.mjs safari   # Test Safari only
 */

import { chromium, firefox, webkit } from 'playwright';
import http from 'http';

const browserArg = process.argv[2] || 'all';

// Simple HTML page with getUserMedia test
const testHtml = `
<!DOCTYPE html>
<html>
<head>
  <title>Camera Test</title>
</head>
<body>
  <h1>Camera Permission Test</h1>
  <video id="video" autoplay playsinline muted style="width: 320px; height: 240px; background: #333;"></video>
  <div id="status">Testing...</div>
  <script>
    async function testCamera() {
      const status = document.getElementById('status');
      const video = document.getElementById('video');

      try {
        // Check if getUserMedia is available
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          window.testResult = {
            success: false,
            error: 'getUserMedia not available',
            isSecureContext: window.isSecureContext,
          };
          status.textContent = 'FAILED: getUserMedia not available';
          return;
        }

        // Try to get video stream
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { width: 640, height: 480 },
          audio: false
        });

        // Attach to video element
        video.srcObject = stream;

        // Get track info
        const videoTracks = stream.getVideoTracks();
        const settings = videoTracks[0]?.getSettings() || {};

        window.testResult = {
          success: true,
          trackCount: videoTracks.length,
          label: videoTracks[0]?.label || 'unknown',
          readyState: videoTracks[0]?.readyState || 'unknown',
          width: settings.width,
          height: settings.height,
          frameRate: settings.frameRate,
          isSecureContext: window.isSecureContext,
        };
        status.textContent = 'SUCCESS: Camera access granted - ' + settings.width + 'x' + settings.height;

      } catch (err) {
        window.testResult = {
          success: false,
          error: err.message,
          errorName: err.name,
          isSecureContext: window.isSecureContext,
        };
        status.textContent = 'FAILED: ' + err.message;
      }
    }

    testCamera();
  </script>
</body>
</html>
`;

// Start a simple HTTP server
function startServer(port) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(testHtml);
    });
    // Listen on 0.0.0.0 to handle both IPv4 and IPv6 connections
    server.listen(port, '0.0.0.0', () => {
      resolve(server);
    });
    server.on('error', reject);
  });
}

async function testBrowser(browserType, name, serverUrl, headless = true) {
  const mode = headless ? 'headless' : 'headed';
  console.log(`\n${'='.repeat(50)}`);
  console.log(`Testing ${name} (${mode})...`);
  console.log('='.repeat(50));

  let browser = null;
  let context = null;
  let page = null;

  try {
    // Launch options - match our working test patterns
    const launchOptions = { headless };

    // Chrome: use fake media devices
    if (name === 'Chrome') {
      launchOptions.args = [
        '--use-fake-ui-for-media-stream',
        '--use-fake-device-for-media-stream',
      ];
    }

    // Firefox: use firefoxUserPrefs in launch
    if (name === 'Firefox') {
      launchOptions.firefoxUserPrefs = {
        'media.navigator.streams.fake': true,
        'media.navigator.permission.disabled': true,
      };
    }

    browser = await browserType.launch(launchOptions);

    // Context options - match our working patterns
    const contextOptions = {};

    if (name === 'Chrome') {
      // Chrome uses permissions array
      contextOptions.permissions = ['camera'];
    }

    context = await browser.newContext(contextOptions);
    page = await context.newPage();

    // Navigate to localhost server
    await page.goto(serverUrl, { timeout: 10000 });

    // Wait for test result
    const result = await page.evaluate(async () => {
      return new Promise((resolve) => {
        const check = () => {
          if (window.testResult) {
            resolve(window.testResult);
          } else {
            setTimeout(check, 100);
          }
        };
        setTimeout(check, 100);

        // Timeout after 10 seconds
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 10000);
      });
    });

    if (result.success) {
      console.log(`  ✓ SUCCESS: Camera access granted`);
      console.log(`    Secure context: ${result.isSecureContext}`);
      console.log(`    Label: ${result.label}`);
      console.log(`    State: ${result.readyState}`);
      console.log(`    Resolution: ${result.width}x${result.height}`);
      if (result.frameRate) {
        console.log(`    Frame rate: ${result.frameRate}`);
      }
      return { browser: name, mode, success: true, details: result };
    } else {
      console.log(`  ✗ FAILED: ${result.error}`);
      console.log(`    Secure context: ${result.isSecureContext}`);
      if (result.errorName) {
        console.log(`    Error type: ${result.errorName}`);
      }
      return { browser: name, mode, success: false, error: result.error };
    }

  } catch (err) {
    console.log(`  ✗ ERROR: ${err.message}`);
    return { browser: name, mode, success: false, error: err.message };
  } finally {
    if (page) await page.close().catch(() => {});
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}

async function main() {
  console.log('Camera Permission Test for Playwright');
  console.log('=====================================\n');
  console.log('Testing if getUserMedia works with proper browser settings...');
  console.log('Using same patterns as our working media tests.\n');

  // Start HTTP server
  const port = 9999;
  const serverUrl = `http://localhost:${port}`;
  let server;

  try {
    server = await startServer(port);
    console.log(`HTTP server started at ${serverUrl}`);
  } catch (err) {
    console.error(`Failed to start server: ${err.message}`);
    process.exit(1);
  }

  const results = [];

  const browsers = [
    { type: chromium, name: 'Chrome' },
    { type: firefox, name: 'Firefox' },
    { type: webkit, name: 'Safari' },
  ];

  // Filter browsers based on argument
  const browsersToTest = browsers.filter(b => {
    if (browserArg === 'all') return true;
    const arg = browserArg.toLowerCase();
    if (arg === 'chrome' || arg === 'chromium') return b.name === 'Chrome';
    if (arg === 'firefox') return b.name === 'Firefox';
    if (arg === 'safari' || arg === 'webkit') return b.name === 'Safari';
    return false;
  });

  if (browsersToTest.length === 0) {
    console.log(`Unknown browser: ${browserArg}`);
    console.log('Valid options: chrome, firefox, safari, all');
    server.close();
    process.exit(1);
  }

  // Test headless mode
  console.log('\n*** HEADLESS MODE TESTS ***');
  for (const { type, name } of browsersToTest) {
    const result = await testBrowser(type, name, serverUrl, true);
    results.push(result);
  }

  // Test headed mode for browsers that failed headless
  console.log('\n\n*** HEADED MODE TESTS (for failed headless) ***');
  for (const { type, name } of browsersToTest) {
    const headlessResult = results.find(r => r.browser === name && r.mode === 'headless');
    if (!headlessResult?.success) {
      const result = await testBrowser(type, name, serverUrl, false);
      results.push(result);
    } else {
      console.log(`\nSkipping ${name} headed test (headless works)`);
    }
  }

  // Stop server
  server.close();

  // Summary
  console.log('\n\n' + '='.repeat(50));
  console.log('SUMMARY');
  console.log('='.repeat(50));

  const headlessResults = results.filter(r => r.mode === 'headless');
  const headedResults = results.filter(r => r.mode === 'headed');

  console.log('\nHeadless mode:');
  for (const r of headlessResults) {
    const status = r.success ? '✓ PASS' : '✗ FAIL';
    const shortError = r.error ? ` (${r.error.substring(0, 50)}...)` : '';
    console.log(`  ${r.browser}: ${status}${shortError}`);
  }

  if (headedResults.length > 0) {
    console.log('\nHeaded mode:');
    for (const r of headedResults) {
      const status = r.success ? '✓ PASS' : '✗ FAIL';
      const shortError = r.error ? ` (${r.error.substring(0, 50)}...)` : '';
      console.log(`  ${r.browser}: ${status}${shortError}`);
    }
  }

  // Recommendations
  console.log('\n\nRECOMMENDATIONS:');
  for (const { type, name } of browsersToTest) {
    const headless = results.find(r => r.browser === name && r.mode === 'headless');
    const headed = results.find(r => r.browser === name && r.mode === 'headed');

    if (headless?.success) {
      console.log(`  ${name}: ✓ Use headless mode`);
      if (name === 'Chrome') {
        console.log(`           args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream']`);
        console.log(`           permissions: ['camera']`);
      } else if (name === 'Firefox') {
        console.log(`           firefoxUserPrefs: { 'media.navigator.streams.fake': true, 'media.navigator.permission.disabled': true }`);
      } else if (name === 'Safari') {
        console.log(`           No special config needed (uses fake media by default)`);
      }
    } else if (headed?.success) {
      console.log(`  ${name}: ⚠ Use headed mode only (headless not supported)`);
    } else {
      console.log(`  ${name}: ✗ Camera not available`);
    }
  }

  console.log('\n');

  // Exit with error if any headless tests failed
  const allHeadlessPass = headlessResults.every(r => r.success);
  process.exit(allHeadlessPass ? 0 : 1);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
