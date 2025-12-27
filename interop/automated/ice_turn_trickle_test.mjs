/**
 * Automated TURN + Trickle ICE Browser Test using Playwright
 *
 * Tests WebRTC TURN relay functionality with trickle ICE:
 * - Uses Open Relay Project's free TURN server
 * - Forces relay-only connections (iceTransportPolicy: relay)
 * - Verifies TURN candidates are generated and used
 * - Tests DataChannel through TURN relay
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/ice_turn_trickle_server.dart
 *
 *   # Then run browser tests:
 *   BROWSER=chrome node interop/automated/ice_turn_trickle_test.mjs
 *   node interop/automated/ice_turn_trickle_test.mjs firefox
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8783';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing TURN + Trickle ICE: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 15000 });

    console.log(`[${browserName}] Running TURN + trickle ICE test...`);
    console.log(`[${browserName}] (TURN connections take longer due to relay setup)`);

    // TURN tests take longer due to relay setup
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

        // Extended timeout for TURN (45 seconds)
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout (TURN takes longer)' });
        }, 60000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  TURN Used: ${result.turnUsed ? 'YES' : 'NO'}`);
    console.log(`  ICE Trickle: ${result.iceTrickle ? 'YES' : 'NO'}`);
    if (result.candidateTypes) {
      console.log(`  Relay Candidates: ${result.candidateTypes.relay || 0}`);
      console.log(`  Host Candidates: ${result.candidateTypes.host || 0}`);
      console.log(`  SRFLX Candidates: ${result.candidateTypes.srflx || 0}`);
    }
    console.log(`  Candidates Sent: ${result.candidatesSent || 0}`);
    console.log(`  Candidates Received: ${result.candidatesReceived || 0}`);
    console.log(`  Ping/Pong: ${result.pingPongSuccess ? 'YES' : 'NO'}`);
    if (result.connectionTimeMs) {
      console.log(`  Connection time: ${result.connectionTimeMs}ms`);
    }
    if (result.error) {
      console.log(`  Error: ${result.error}`);
    }

    return {
      browser: browserName,
      ...result,
    };

  } catch (error) {
    console.error(`[${browserName}] Error: ${error.message}`);
    return {
      browser: browserName,
      success: false,
      error: error.message,
    };
  } finally {
    await closeBrowser({ browser, context, page });
  }
}

async function main() {
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC TURN + Trickle ICE Browser Test');
  console.log('======================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('');
  console.log('Using Open Relay Project free TURN server');
  console.log('Policy: relay-only (forces TURN usage)');

  await checkServer(SERVER_URL, 'dart run interop/automated/ice_turn_trickle_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  if (browserArg === 'all' || browserArg === 'firefox') {
    results.push(await runBrowserTest('firefox'));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('TURN + TRICKLE ICE TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success && result.turnUsed ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success && result.turnUsed) {
      console.log(`       TURN Used: YES`);
      console.log(`       Relay Candidates: ${result.candidateTypes?.relay || 0}`);
      console.log(`       Connection: ${result.connectionTimeMs || 0}ms`);
    }
    if (!result.success || !result.turnUsed) {
      if (!result.turnUsed && result.success) {
        console.log(`       Error: Connected but TURN was not used`);
      } else if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  const actualResults = results.filter(r => !r.skipped);
  const passed = actualResults.filter(r => r.success && r.turnUsed).length;
  const total = actualResults.length;

  if (passed === total && total > 0) {
    console.log(`\nAll browsers PASSED with TURN! (${passed}/${total})`);
    process.exit(0);
  } else {
    console.log(`\nSome tests FAILED! (${passed}/${total} passed with TURN)`);
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
