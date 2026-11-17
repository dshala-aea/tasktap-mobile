#!/usr/bin/env node
// tool/prototype_shot.mjs
//
// Screenshot one phone / screen card from the HTML prototypes at 390×844 (DPR 2) without an
// npm dependency. The Playwright Node module is not installed in this repo, but the cached
// Chromium binary is sufficient: this script talks to it over the DevTools Protocol using the
// global WebSocket that ships with Node (>= 21) and the built-in fetch/http modules.
//
// Usage:
//   node tool/prototype_shot.mjs <html-path> <target> <out.png>
//
// <target> is one of:
//   * a list id from `lists` in prototypes/list-screens.html (e.g. cantieri, ticket, ferie)
//   * a screen name from `screens` in prototypes/other-details.html (e.g. Cliente, Report admin)
//   * a CSS selector starting with "." or "#"
//
// The page is rendered in a 390×844 mobile viewport, then the target element is isolated at
// (0, 0) and captured with an element clip, so the PNG contains the phone / card alone (not the
// surrounding design board). Google Fonts are blocked deliberately: the box is often offline,
// the layout is what matters, and an unreachable stylesheet can otherwise hold the renderer.
// Override the browser with CHROMIUM=/path/to/chrome.
//
// Exit codes: 0 success, 1 runtime failure, 2 bad CLI usage.

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const DEFAULT_CHROMIUM = '/root/.cache/ms-playwright/chromium-1223/chrome-linux64/chrome';
const VIEWPORT = { width: 390, height: 844 };
const DEVICE_SCALE_FACTOR = 2;

function usage(message) {
  if (message) console.error(`error: ${message}`);
  console.error('usage: node tool/prototype_shot.mjs <html-path> <target> <out.png>');
  console.error('  <target> = list id | detail screen name | CSS selector (.foo / #foo)');
  process.exit(2);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Minimal JSON-RPC client over one DevTools page WebSocket. */
class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    ws.addEventListener('message', (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      if (message.id && this.pending.has(message.id)) {
        const { resolve, reject, timer } = this.pending.get(message.id);
        this.pending.delete(message.id);
        clearTimeout(timer);
        if (message.error) {
          reject(new Error(`${message.error.message ?? 'CDP error'} (${JSON.stringify(message.error)})`));
        } else {
          resolve(message.result ?? {});
        }
      }
    });
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve, { once: true });
      ws.addEventListener('error', () => reject(new Error(`cannot connect to ${url}`)), {
        once: true,
      });
    });
    return new Cdp(ws);
  }

  send(method, params = {}, timeoutMs = 20000) {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP timeout: ${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    try {
      this.ws.close();
    } catch {
      // already closed
    }
  }
}

async function waitForDevtoolsPort(profileDir, child) {
  const file = path.join(profileDir, 'DevToolsActivePort');
  for (let i = 0; i < 120; i++) {
    if (child.exitCode != null) {
      throw new Error(`Chromium exited before DevTools was ready (code ${child.exitCode})`);
    }
    try {
      const text = fs.readFileSync(file, 'utf8');
      const port = Number(text.split(/\r?\n/, 1)[0]);
      if (Number.isInteger(port) && port > 0) return port;
    } catch {
      // not written yet
    }
    await sleep(100);
  }
  throw new Error('Chromium did not expose a DevTools port within 12s');
}

async function firstPageWebSocket(port) {
  for (let i = 0; i < 100; i++) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      if (response.ok) {
        const pages = await response.json();
        const page = pages.find((p) => p.type === 'page' && p.webSocketDebuggerUrl);
        if (page) return page.webSocketDebuggerUrl;
      }
    } catch {
      // browser endpoint not up yet
    }
    await sleep(100);
  }
  throw new Error('could not find a page target on the Chromium instance');
}

/** Runs in the page: choose the target, move it to (0, 0), report its box. */
function isolateTargetInPage(target) {
  const targetKind =
    target.startsWith('.') || target.startsWith('#') ? 'selector' : 'named';

  let element = null;

  if (targetKind === 'selector') {
    element = document.querySelector(target);
  } else {
    // list-screens.html exposes `lists`; click the tab so the page's own render() runs.
    if (typeof lists !== 'undefined' && Array.isArray(lists)) {
      const index = lists.findIndex((entry) => entry && entry.id === target);
      if (index >= 0) {
        const tab = document.querySelectorAll('#tabs .tab')[index];
        if (!tab) return { error: `list "${target}" found but its tab is missing` };
        tab.click();
        element = document.querySelector('.phone-wrap .phone') ?? document.querySelector('.phone');
      }
    }

    // other-details.html exposes `screens`; match the card heading exactly.
    if (!element && typeof screens !== 'undefined' && Array.isArray(screens)) {
      const cards = Array.from(document.querySelectorAll('.screen-card'));
      element =
        cards.find((card) => {
          const heading = card.querySelector('.card-head h2');
          return heading && heading.textContent.trim() === target;
        }) ?? null;
    }

    if (!element) {
      const listIds =
        typeof lists !== 'undefined' && Array.isArray(lists)
          ? lists.map((entry) => entry && entry.id).filter(Boolean)
          : [];
      const screenNames =
        typeof screens !== 'undefined' && Array.isArray(screens)
          ? screens.map((entry) => entry && entry.screen).filter(Boolean)
          : [];
      const available = [
        listIds.length ? `lists: ${listIds.join(', ')}` : '',
        screenNames.length ? `screens: ${screenNames.join(', ')}` : '',
      ]
        .filter(Boolean)
        .join(' | ');
      return {
        error: `target "${target}" not found${available ? ` (available ${available})` : ''}`,
      };
    }
  }

  if (!element) {
    return { error: `selector "${target}" matched nothing` };
  }

  // Detach the element from the design board: move a clone to a bare body so nothing from the
  // surrounding page (margins, grid columns, sticky wrappers) lands in the capture.
  const clone = element.cloneNode(true);
  document.body.replaceChildren(clone);

  const style = document.createElement('style');
  style.textContent = `
    *, *::before, *::after { animation: none !important; transition: none !important; }
    html, body { margin: 0 !important; padding: 0 !important; background: transparent !important; }
    body { width: 390px !important; }
    .phone { margin: 0 !important; }
  `;
  document.head.appendChild(style);

  // Two frames so the clone is laid out before we measure it.
  return new Promise((resolve) => {
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        const box = clone.getBoundingClientRect();
        if (!box.width || !box.height) {
          resolve({ error: `target "${target}" has an empty box` });
          return;
        }
        resolve({
          x: box.x,
          y: box.y,
          width: box.width,
          height: box.height,
        });
      }),
    );
  });
}

async function main() {
  const [htmlArg, target, outArg, ...extra] = process.argv.slice(2);
  if (!htmlArg || !target || !outArg || extra.length) {
    usage(extra.length ? `unexpected argument "${extra[0]}"` : 'missing arguments');
  }

  const htmlPath = path.resolve(htmlArg);
  if (!fs.existsSync(htmlPath) || !fs.statSync(htmlPath).isFile()) {
    console.error(`error: prototype file not found: ${htmlPath}`);
    process.exit(1);
  }

  const outPath = path.resolve(outArg);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });

  const chromium = process.env.CHROMIUM || DEFAULT_CHROMIUM;
  if (!fs.existsSync(chromium)) {
    console.error(`error: Chromium binary not found: ${chromium}`);
    console.error('       set CHROMIUM=/path/to/chrome to override.');
    process.exit(1);
  }

  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tasktap-protoshot-'));
  let child = null;
  let cdp = null;

  const cleanup = () => {
    try {
      cdp?.close();
    } catch {
      // ignore
    }
    if (child && child.exitCode == null) {
      try {
        process.kill(-child.pid, 'SIGKILL');
      } catch {
        try {
          child.kill('SIGKILL');
        } catch {
          // ignore
        }
      }
    }
    try {
      fs.rmSync(profileDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  };

  try {
    child = spawn(
      chromium,
      [
        '--headless=new',
        '--no-sandbox',
        '--disable-gpu',
        '--disable-dev-shm-usage',
        '--hide-scrollbars',
        '--disable-background-networking',
        '--disable-component-update',
        '--no-first-run',
        '--no-default-browser-check',
        '--remote-debugging-port=0',
        `--user-data-dir=${profileDir}`,
        'about:blank',
      ],
      { stdio: 'ignore', detached: true },
    );

    process.on('SIGINT', () => {
      cleanup();
      process.exit(130);
    });

    const port = await waitForDevtoolsPort(profileDir, child);
    const pageWs = await firstPageWebSocket(port);
    cdp = await Cdp.connect(pageWs);

    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Network.enable');
    await cdp.send('Network.setBlockedURLs', {
      urls: ['*fonts.googleapis.com*', '*fonts.gstatic.com*'],
    });
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: VIEWPORT.width,
      height: VIEWPORT.height,
      deviceScaleFactor: DEVICE_SCALE_FACTOR,
      mobile: true,
    });

    const fileUrl = `file://${htmlPath.split(path.sep).join('/')}`;
    await cdp.send('Page.navigate', { url: fileUrl });

    // Let the page's scripts run. With Google Fonts blocked the load settles quickly, but poll
    // for completeness instead of relying on a fixed delay.
    for (let i = 0; i < 100; i++) {
      const state = await cdp.send('Runtime.evaluate', {
        expression: 'document.readyState',
        returnByValue: true,
      });
      if (state.result?.value === 'complete') break;
      await sleep(100);
    }
    await cdp.send('Runtime.evaluate', {
      expression: 'document.fonts && document.fonts.ready',
      awaitPromise: true,
      returnByValue: true,
      timeout: 3000,
    }).catch(() => {});

    const isolated = await cdp.send('Runtime.evaluate', {
      expression: `(${isolateTargetInPage.toString()})(${JSON.stringify(target)})`,
      awaitPromise: true,
      returnByValue: true,
    });

    const box = isolated.result?.value;
    if (!box || box.error) {
      throw new Error(box?.error ?? `could not isolate target "${target}"`);
    }

    const screenshot = await cdp.send(
      'Page.captureScreenshot',
      {
        format: 'png',
        fromSurface: true,
        captureBeyondViewport: true,
        clip: {
          x: box.x,
          y: box.y,
          width: box.width,
          height: box.height,
          scale: 1,
        },
      },
      30000,
    );

    const bytes = Buffer.from(screenshot.data, 'base64');
    if (!bytes.length) throw new Error('Chromium returned an empty screenshot');
    fs.writeFileSync(outPath, bytes);
    console.log(
      `wrote ${outPath} (${Math.round(box.width)}×${Math.round(box.height)} css px, ` +
        `${DEVICE_SCALE_FACTOR}× → ${bytes.length} bytes)`,
    );
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  } finally {
    cleanup();
  }
}

main();
