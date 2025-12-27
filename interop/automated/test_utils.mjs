/**
 * Shared test utilities for browser interop tests.
 *
 * Browser Selection:
 *   Supports both environment variable and command line argument:
 *   - BROWSER=firefox node test.mjs
 *   - node test.mjs firefox
 *
 *   Environment variable takes precedence over command line argument.
 *   Default is 'chrome' if neither is specified.
 *
 *   Valid values: chrome, firefox, safari, webkit, all
 */

import { chromium, firefox, webkit } from 'playwright';

/**
 * Get the browser argument from environment or command line.
 * @returns {string} Browser name ('chrome', 'firefox', 'safari', 'webkit', or 'all')
 */
export function getBrowserArg() {
  return process.env.BROWSER || process.argv[2] || 'chrome';
}

/**
 * Get browser type and name from the browser argument.
 * @param {string} browserArg - Browser argument ('chrome', 'firefox', 'safari', 'webkit')
 * @returns {{ browserType: any, browserName: string }} Playwright browser type and display name
 */
export function getBrowserType(browserArg) {
  const arg = browserArg.toLowerCase();
  switch (arg) {
    case 'chrome':
    case 'chromium':
      return { browserType: chromium, browserName: 'chrome' };
    case 'firefox':
      return { browserType: firefox, browserName: 'firefox' };
    case 'safari':
    case 'webkit':
      return { browserType: webkit, browserName: 'safari' };
    default:
      console.error(`Unknown browser: ${browserArg}`);
      console.error('Valid options: chrome, firefox, safari, webkit, all');
      process.exit(1);
  }
}

/**
 * Get list of browsers to test based on browser argument.
 * @param {string} browserArg - Browser argument (can be 'all' for all browsers)
 * @returns {Array<{ browserType: any, browserName: string }>} List of browser configs
 */
export function getBrowserList(browserArg) {
  if (browserArg === 'all') {
    return [
      { browserType: chromium, browserName: 'chrome' },
      { browserType: firefox, browserName: 'firefox' },
      { browserType: webkit, browserName: 'safari' },
    ];
  }
  return [getBrowserType(browserArg)];
}

/**
 * Get default launch options for a browser.
 * @param {string} browserName - Browser name ('chrome', 'firefox', 'safari')
 * @param {Object} options - Additional options
 * @param {boolean} options.headless - Run headless (default: true)
 * @param {boolean} options.fakeMedia - Use fake media devices (default: true)
 * @returns {Object} Playwright launch options
 */
export function getLaunchOptions(browserName, { headless = true, fakeMedia = true } = {}) {
  const options = { headless };

  if (browserName === 'chrome' && fakeMedia) {
    options.args = [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ];
  }

  return options;
}

/**
 * Get default context options for a browser.
 * @param {string} browserName - Browser name ('chrome', 'firefox', 'safari')
 * @param {Object} options - Additional options
 * @param {boolean} options.fakeMedia - Use fake media devices (default: true)
 * @returns {Object} Playwright context options
 */
export function getContextOptions(browserName, { fakeMedia = true } = {}) {
  const options = {};

  if (browserName === 'chrome') {
    options.permissions = ['camera', 'microphone'];
  }

  if (browserName === 'firefox' && fakeMedia) {
    options.firefoxUserPrefs = {
      'media.navigator.streams.fake': true,
      'media.navigator.permission.disabled': true,
    };
  }

  return options;
}

/**
 * Print standard test header.
 * @param {string} testName - Name of the test
 * @param {string} serverUrl - Server URL
 * @param {string} browserArg - Browser argument
 */
export function printHeader(testName, serverUrl, browserArg) {
  console.log(testName);
  console.log('='.repeat(testName.length));
  console.log(`Server: ${serverUrl}`);
  console.log(`Browser: ${browserArg}`);
  console.log('');
}

/**
 * Check if server is running.
 * @param {string} serverUrl - Server URL to check
 * @param {string} startCommand - Command to start the server (for error message)
 */
export async function checkServer(serverUrl, startCommand) {
  try {
    const resp = await fetch(`${serverUrl}/status`);
    if (!resp.ok) throw new Error('Server returned non-OK status');
  } catch (e) {
    console.error(`Error: Server is not running at ${serverUrl}`);
    console.error(`Start it with: ${startCommand}`);
    process.exit(1);
  }
}
