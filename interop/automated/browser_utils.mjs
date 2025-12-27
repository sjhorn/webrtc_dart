/**
 * Shared Browser Utilities for Playwright Interop Tests
 *
 * Consolidates all repeated browser setup code:
 * - Browser selection (chrome/firefox/safari)
 * - Launch options with correct flags for each browser
 * - Context options with permissions
 * - Media stream helpers (canvas fallback for Safari)
 */

import { chromium, firefox, webkit } from 'playwright';

// =============================================================================
// Browser Selection & Arguments
// =============================================================================

/**
 * Get the browser argument from environment or command line.
 * Priority: BROWSER env var > process.argv[2] > default 'chrome'
 *
 * @returns {string} Browser name ('chrome', 'firefox', 'safari', 'webkit', or 'all')
 */
export function getBrowserArg() {
  return process.env.BROWSER || process.argv[2] || 'chrome';
}

/**
 * Get Playwright browser type from browser name.
 *
 * @param {string} browserArg - Browser name
 * @returns {{ browserType: any, browserName: string }}
 */
export function getBrowserType(browserArg) {
  const arg = (browserArg || 'chrome').toLowerCase();
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
 * Get list of all browser configs for 'all' option.
 *
 * @returns {Array<{ browserType: any, browserName: string }>}
 */
export function getAllBrowsers() {
  return [
    { browserType: chromium, browserName: 'chrome' },
    { browserType: firefox, browserName: 'firefox' },
    { browserType: webkit, browserName: 'safari' },
  ];
}

// =============================================================================
// Browser Launch & Context Options
// =============================================================================

/**
 * Get launch options for a browser.
 * Includes correct flags for fake media streams.
 *
 * @param {string} browserName - Browser name ('chrome', 'firefox', 'safari')
 * @param {Object} options - Additional options
 * @param {boolean} options.headless - Run headless (default: true)
 * @returns {Object} Playwright launch options
 */
export function getLaunchOptions(browserName, { headless = true } = {}) {
  const options = { headless };

  if (browserName === 'chrome') {
    options.args = [
      '--use-fake-ui-for-media-stream',      // Auto-accept permission prompts
      '--use-fake-device-for-media-stream',  // Use synthetic video/audio
      '--autoplay-policy=no-user-gesture-required',
    ];
  }

  // Firefox: firefoxUserPrefs must be at launch time
  if (browserName === 'firefox') {
    options.firefoxUserPrefs = {
      'media.navigator.streams.fake': true,
      'media.navigator.permission.disabled': true,
    };
  }

  // Safari/WebKit: No special launch options needed
  // Camera access uses canvas fallback (see getVideoStream)

  return options;
}

/**
 * Get context options for a browser.
 *
 * @param {string} browserName - Browser name
 * @returns {Object} Playwright context options
 */
export function getContextOptions(browserName) {
  // Only Chrome supports permission grants
  if (browserName === 'chrome') {
    return { permissions: ['camera', 'microphone'] };
  }
  // Firefox/Safari: Don't try to grant permissions (not supported)
  return {};
}

/**
 * Launch browser with correct options for the browser type.
 *
 * @param {string} browserName - Browser name ('chrome', 'firefox', 'safari')
 * @param {Object} options - Additional options
 * @param {boolean} options.headless - Run headless (default: true)
 * @returns {Promise<{ browser: any, context: any, page: any, browserName: string }>}
 */
export async function launchBrowser(browserName, { headless = true } = {}) {
  const { browserType } = getBrowserType(browserName);
  const launchOptions = getLaunchOptions(browserName, { headless });
  const contextOptions = getContextOptions(browserName);

  const browser = await browserType.launch(launchOptions);
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  return { browser, context, page, browserName };
}

/**
 * Close browser gracefully.
 *
 * @param {Object} browserInfo - Object with browser, context, page
 */
export async function closeBrowser({ browser, context, page }) {
  if (page) await page.close().catch(() => {});
  if (context) await context.close().catch(() => {});
  if (browser) await browser.close().catch(() => {});
}

// =============================================================================
// Media Stream Helpers (for use in page.evaluate)
// =============================================================================

/**
 * Script to inject into pages for media stream helpers.
 * Use this in your server's HTML or inject via page.addScriptTag().
 */
export const MEDIA_HELPERS_SCRIPT = `
// Canvas stream creator - works without permissions
function createCanvasStream(width = 640, height = 480, frameRate = 30) {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  let frame = 0;

  function draw() {
    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(0, 0, width, height);
    const x = width / 2 + Math.sin(frame * 0.05) * (width / 4);
    const y = height / 2 + Math.cos(frame * 0.03) * (height / 4);
    ctx.beginPath();
    ctx.arc(x, y, 40, 0, Math.PI * 2);
    ctx.fillStyle = '#ff6b6b';
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.font = '16px sans-serif';
    ctx.fillText('Canvas Frame ' + frame, 10, 25);
    frame++;
    requestAnimationFrame(draw);
  }
  draw();
  return canvas.captureStream(frameRate);
}

// Browser detection
function detectBrowser() {
  const ua = navigator.userAgent;
  if (ua.includes('Firefox')) return 'firefox';
  if (ua.includes('Chrome')) return 'chrome';
  if (ua.includes('Safari')) return 'safari';
  return 'unknown';
}

// Get video stream - Safari uses canvas directly to avoid permission dialogs
async function getVideoStream(width = 640, height = 480) {
  const browser = detectBrowser();

  // Safari: Always use canvas (no permission dialog)
  if (browser === 'safari') {
    console.log('Safari detected, using canvas stream');
    return { stream: createCanvasStream(width, height, 30), source: 'canvas' };
  }

  // Chrome/Firefox: Try camera, fall back to canvas
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width, height },
      audio: false
    });
    console.log('Camera access granted');
    return { stream, source: 'camera' };
  } catch (e) {
    console.log('Camera unavailable, using canvas fallback:', e.message);
    return { stream: createCanvasStream(width, height, 30), source: 'canvas-fallback' };
  }
}
`;

// =============================================================================
// Console Logging Helper
// =============================================================================

/**
 * Set up console message forwarding from page to Node console.
 *
 * @param {any} page - Playwright page
 * @param {string} prefix - Prefix for log messages (e.g., browser name)
 */
export function setupConsoleLogging(page, prefix) {
  page.on('console', msg => {
    const text = msg.text();
    // Skip internal messages
    if (!text.startsWith('TEST_RESULT:')) {
      console.log(`[${prefix}] ${text}`);
    }
  });
}

// =============================================================================
// Server Health Check
// =============================================================================

/**
 * Check if server is running at URL.
 *
 * @param {string} serverUrl - Server URL
 * @param {string} startCommand - Command to show in error message
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

/**
 * Print standard test header.
 *
 * @param {string} testName - Name of the test
 * @param {string} serverUrl - Server URL
 * @param {string} browserArg - Browser being tested
 */
export function printHeader(testName, serverUrl, browserArg) {
  console.log(testName);
  console.log('='.repeat(testName.length));
  console.log(`Server: ${serverUrl}`);
  console.log(`Browser: ${browserArg}`);
  console.log('');
}

// Default export
export default {
  getBrowserArg,
  getBrowserType,
  getAllBrowsers,
  getLaunchOptions,
  getContextOptions,
  launchBrowser,
  closeBrowser,
  MEDIA_HELPERS_SCRIPT,
  setupConsoleLogging,
  checkServer,
  printHeader,
};
