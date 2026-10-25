#!/usr/bin/env node
/*
 * PiliPlus Web proxy.
 *
 * Stateless relay: it forwards requests to bilibili hosts and never stores
 * cookies, accounts or other personal data. All client state lives in the
 * browser. Only hosts in ALLOWED_HOSTS can be reached (SSRF protection).
 */
import http from 'node:http';
import http2 from 'node:http2';
import dns from 'node:dns';
import net from 'node:net';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { Agent, fetch as fetchUpstream } from 'undici';
import { createHash } from 'node:crypto';
import { WebSocket, WebSocketServer } from 'ws';

const SERVER_VERSION = '0.1.0';
const SERVER_DIR = resolve(fileURLToPath(new URL('.', import.meta.url)));
const HOST = process.env.HOST || '127.0.0.1';
const PORT = Number(process.env.PORT || 8787);
const STATIC_DIR = process.env.STATIC_DIR
  ? resolve(process.env.STATIC_DIR)
  : resolve(SERVER_DIR, '../build/web');
const ALLOW_ORIGIN = process.env.ALLOW_ORIGIN || '*';
const PROXY_TOKEN = process.env.PROXY_TOKEN || '';
const LOG_REQUESTS = process.env.LOG_REQUESTS === '1';
const LOG_RESPONSES = process.env.LOG_RESPONSES === '1';
const UPSTREAM_TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT_MS || 60000);
const MEDIA_TIMEOUT_MS = Number(process.env.MEDIA_TIMEOUT_MS || 300000);
const MAX_REDIRECTS = 5;

const DEFAULT_ALLOWED_HOSTS = [
  // All bilibili services, image CDNs and video CDNs.
  'bilibili.com',
  'biliimg.com',
  'bilivideo.com',
  'bilivideo.cn',
  'bilivideo.net',
  'hdslb.com',
  'b23.tv',
  'mountaintoys.cn',
];

// Hosts that cannot be expressed as a plain suffix.
const DEFAULT_ALLOWED_PATTERNS = [
  // Overseas video CDN (used by the project's CDN selector).
  /^(?:upos|proxy)-[a-z0-9-]+\.akamaized\.net$/i,
  // Bilibili mirror CDN domain.
  /^(?:[a-z0-9-]+\.)*szbdyd\.com$/i,
  // SponsorBlock endpoint used by the app.
  /^www\.bsbsb\.top$/i,
  // Captcha provider used by bilibili login.
  /^(?:api|static|gcaptcha4|h5|gt4)\.geetest\.com$/i,
];

const ALLOWED_HOSTS = (process.env.ALLOWED_HOSTS || '')
  .split(',')
  .map((item) => item.trim().toLowerCase())
  .filter(Boolean)
  .concat(DEFAULT_ALLOWED_HOSTS);

const CORS_EXPOSE = [
  'content-length',
  'content-range',
  'accept-ranges',
  'content-type',
  'etag',
  'last-modified',
  'x-pili-set-cookie',
  'grpc-status',
  'grpc-message',
  'grpc-status-details-bin',
].join(', ');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.map': 'application/json; charset=utf-8',
  '.bin': 'application/octet-stream',
  '.mp4': 'video/mp4',
  '.m4s': 'video/iso.segment',
  '.flv': 'video/x-flv',
  '.ts': 'video/mp2t',
  '.txt': 'text/plain; charset=utf-8',
};

function isAllowedHost(hostname) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (!host || host.includes(':')) return false;
  // Never accept IP literals, including IPv6 loopback/private forms.
  if (net.isIP(host) !== 0) return false;
  if (host === 'localhost' || host.endsWith('.localhost')) return false;
  return (
    ALLOWED_HOSTS.some(
      (suffix) => host === suffix || host.endsWith(`.${suffix}`),
    ) || DEFAULT_ALLOWED_PATTERNS.some((pattern) => pattern.test(host))
  );
}

function isPublicIPv4(address) {
  const [a, b, c] = address.split('.').map(Number);
  if (a === 0 || a === 10 || a === 127) return false;
  // Carrier-grade NAT.
  if (a === 100 && b >= 64 && b <= 127) return false;
  // Link-local / cloud metadata.
  if (a === 169 && b === 254) return false;
  // Private ranges.
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  // Documentation / benchmark / relay ranges.
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false;
  if (a === 192 && b === 88 && c === 99) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  if (a === 198 && b === 51 && c === 100) return false;
  if (a === 203 && b === 0 && c === 113) return false;
  // Multicast, reserved and broadcast.
  if (a >= 224) return false;
  return true;
}

function isPublicIPv6(address) {
  const addr = address.toLowerCase().split('%')[0];
  if (addr === '::' || addr === '::1') return false;
  // IPv4-mapped, IPv4-compatible and other ::/96 forms.
  if (addr.startsWith('::')) return false;
  if (/^(?:0{1,4}:){5}ffff:/.test(addr)) return false;
  // Unique local (fc00::/7), link-local (fe80::/10), site-local (fec0::/10).
  if (/^f[cd]/.test(addr)) return false;
  if (/^fe[89ab]/.test(addr) || /^fe[c-f]/.test(addr)) return false;
  // Multicast, discard-only, documentation, NAT64, 6to4, Teredo, ORCHID.
  if (/^ff/.test(addr)) return false;
  if (addr.startsWith('100:')) return false;
  if (addr.startsWith('2001:db8')) return false;
  if (addr.startsWith('64:ff9b')) return false;
  if (addr.startsWith('2002')) return false;
  if (addr.startsWith('2001:0:') || addr.startsWith('2001:0000:')) return false;
  if (addr.startsWith('2001:10') || addr.startsWith('2001:20')) return false;
  return true;
}

function isPublicAddress(address) {
  if (net.isIPv4(address)) return isPublicIPv4(address);
  if (net.isIPv6(address)) return isPublicIPv6(address);
  return false;
}

// Validate every DNS answer before connecting. This blocks hostnames that
// resolve to loopback, RFC1918, link-local or IPv6 ULA addresses, including
// IPv4-mapped IPv6 forms.
function safeLookup(hostname, options, callback) {
  dns.lookup(
    hostname,
    { all: true, family: options?.family || 0 },
    (error, addresses) => {
      if (error) return callback(error);
      const list = Array.isArray(addresses)
        ? addresses
        : [{ address: addresses, family: options?.family || 4 }];
      const safe = list.filter((item) => isPublicAddress(item.address));
      if (safe.length === 0) {
        const blocked = new Error('blocked_non_public_address');
        blocked.code = 'EADDRBLOCKED';
        return callback(blocked);
      }
      if (options?.all) return callback(null, safe);
      return callback(null, safe[0].address, safe[0].family);
    },
  );
}

const WBI_MIXIN_TAB = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
  27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
];
let wbiCache = { key: null, at: 0 };

async function getWbiMixinKey() {
  if (wbiCache.key && Date.now() - wbiCache.at < 3600_000) {
    return wbiCache.key;
  }
  try {
    const response = await fetchUpstream(
      'https://api.bilibili.com/x/web-interface/nav',
      {
        headers: {
          accept: 'application/json',
          referer: 'https://www.bilibili.com/',
          'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
        dispatcher: upstreamDispatcher,
        signal: AbortSignal.timeout(10000),
      },
    );
    const body = await response.json();
    const imgUrl = body?.data?.wbi_img?.img_url;
    const subUrl = body?.data?.wbi_img?.sub_url;
    if (!imgUrl || !subUrl) return null;
    const name = (value) => value.split('/').pop().split('.')[0];
    const original = name(imgUrl) + name(subUrl);
    const key = WBI_MIXIN_TAB.map((index) => original[index]).join('');
    if (key.length !== 32) return null;
    wbiCache = { key, at: Date.now() };
    return key;
  } catch {
    return null;
  }
}

function parseRawQuery(search) {
  const pairs = [];
  for (const part of search.replace(/^\?/, '').split('&')) {
    if (!part) continue;
    const index = part.indexOf('=');
    try {
      const key = decodeURIComponent(index >= 0 ? part.slice(0, index) : part);
      const value = index >= 0 ? decodeURIComponent(part.slice(index + 1)) : '';
      pairs.push([key, value]);
    } catch {
      // Ignore malformed pairs.
    }
  }
  return pairs;
}

async function sanitizeWbiTarget(target) {
  if (!target.searchParams.has('w_rid')) return target;
  const key = await getWbiMixinKey();
  let valid = false;
  if (key) {
    const pairs = parseRawQuery(target.search);
    const rid = pairs.find(([k]) => k === 'w_rid')?.[1];
    const map = new Map(pairs.filter(([k]) => k !== 'w_rid'));
    const query = [...map.keys()]
      .sort()
      .map(
        (k) =>
          `${encodeURIComponent(k)}=${encodeURIComponent(
            (map.get(k) || '').replace(/[!'()*]/g, ''),
          )}`,
      )
      .join('&');
    const expected = createHash('md5')
      .update(query + key)
      .digest('hex');
    valid = rid === expected;
  }
  if (valid && LOG_REQUESTS) {
    console.log(`[wbi] valid signature ${target.host}${target.pathname}`);
  }
  if (!valid) {
    target.searchParams.delete('w_rid');
    target.searchParams.delete('wts');
    if (LOG_REQUESTS) {
      console.log(`[wbi] stripped invalid signature ${target.host}${target.pathname}`);
    }
  }
  return target;
}

const upstreamDispatcher = new Agent({
  connect: { lookup: safeLookup },
  keepAliveTimeout: 10_000,
  keepAliveMaxTimeout: 30_000,
});

function setCors(req, res) {
  const requestOrigin = req.headers.origin;
  let origin = '*';
  if (ALLOW_ORIGIN === '*') {
    origin = '*';
  } else if (ALLOW_ORIGIN.split(',').map((v) => v.trim()).includes(requestOrigin)) {
    origin = requestOrigin;
  }
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,HEAD,OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    req.headers['access-control-request-headers'] ||
      'content-type,range,if-range,if-none-match,if-modified-since,x-pili-target,x-pili-cookie,x-pili-referer,x-pili-user-agent,x-pili-origin',
  );
  res.setHeader('Access-Control-Expose-Headers', CORS_EXPOSE);
  res.setHeader('Access-Control-Max-Age', '86400');
}

function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(body);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function authorized(req) {
  if (!PROXY_TOKEN) return true;
  const header = req.headers['x-pili-token'];
  const bearer = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  return (
    (typeof header === 'string' && timingSafeEqual(header, PROXY_TOKEN)) ||
    (typeof bearer === 'string' && timingSafeEqual(bearer, PROXY_TOKEN))
  );
}

function getTarget(req, url) {
  const raw = req.headers['x-pili-target'] || url.searchParams.get('url');
  if (!raw) return null;
  try {
    return new URL(raw);
  } catch {
    return null;
  }
}

function defaultReferer(target) {
  const host = target.hostname;
  if (host === 'live.bilibili.com' || host === 'api.live.bilibili.com') {
    return 'https://live.bilibili.com/';
  }
  if (host === 'passport.bilibili.com' || host.endsWith('.passport.bilibili.com')) {
    return 'https://passport.bilibili.com/';
  }
  if (host.endsWith('space.bilibili.com')) {
    return `https://${host}/`;
  }
  if (host === 'bilibili.com' || host.endsWith('.bilibili.com')) {
    return 'https://www.bilibili.com/';
  }
  // Static/media CDNs reject requests carrying a foreign Referer.
  if (
    host === 'hdslb.com' ||
    host.endsWith('.hdslb.com') ||
    host === 'biliimg.com' ||
    host.endsWith('.biliimg.com') ||
    host === 'bilivideo.com' ||
    host.endsWith('.bilivideo.com') ||
    host === 'bilivideo.cn' ||
    host.endsWith('.bilivideo.cn') ||
    host === 'bilivideo.net' ||
    host.endsWith('.bilivideo.net') ||
    host.endsWith('.szbdyd.com') ||
    host.endsWith('.akamaized.net') ||
    host.endsWith('.mountaintoys.cn')
  ) {
    return 'https://www.bilibili.com/';
  }
  if (host === 'geetest.com' || host.endsWith('.geetest.com')) {
    return 'https://www.bilibili.com/';
  }
  return undefined;
}

function upstreamHeaders(req, target, method) {
  const headers = new Headers();
  // Forward every safe client header. App endpoints depend on buvid, fp_local,
  // session_id, app-key, x-bili-* and friends; a narrow allowlist made those
  // calls fail with bilibili error -400.
  const skip = new Set([
    'host',
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'content-length',
    'accept-encoding',
    'origin',
    'referer',
    'user-agent',
  ]);
  for (const [key, value] of Object.entries(req.headers)) {
    if (typeof value !== 'string' || !value) continue;
    if (skip.has(key) || key.startsWith('sec-') || key.startsWith('x-pili-')) {
      continue;
    }
    headers.set(key, value);
  }

  // Browsers forbid scripts from setting these headers, so the web client
  // forwards them through x-pili-* aliases instead.
  const aliasCookie = req.headers['x-pili-cookie'];
  if (typeof aliasCookie === 'string' && aliasCookie) {
    headers.set('cookie', aliasCookie);
  }
  const aliasUa = req.headers['x-pili-user-agent'];
  headers.set(
    'user-agent',
    typeof aliasUa === 'string' && aliasUa
      ? aliasUa
      : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  );
  const aliasReferer = req.headers['x-pili-referer'];
  const referer =
    typeof aliasReferer === 'string' && aliasReferer
      ? aliasReferer
      : defaultReferer(target);
  if (referer) headers.set('referer', referer);
  // Origin is not sent by the native app; only forward an explicit override.
  const aliasOrigin = req.headers['x-pili-origin'];
  if (typeof aliasOrigin === 'string' && aliasOrigin) {
    headers.set('origin', aliasOrigin);
  }
  return headers;
}

function isMediaRequest(req, target) {
  if (req.headers.range) return true;
  return /\.(m4s|mp4|flv|ts|m4a|aac)$/i.test(target.pathname);
}

function copyResponseHeaders(upstream, res, collectedCookies = []) {
  for (const [key, value] of upstream.headers) {
    const name = key.toLowerCase();
    if (
      name === 'set-cookie' ||
      name === 'content-encoding' ||
      name === 'transfer-encoding' ||
      name === 'connection' ||
      name === 'keep-alive' ||
      name === 'access-control-allow-origin' ||
      name === 'access-control-allow-headers' ||
      name === 'access-control-allow-methods' ||
      name === 'access-control-expose-headers'
    ) {
      continue;
    }
    if (name === 'content-length') continue;
    res.setHeader(name, value);
  }

  // fetch() transparently decompresses bodies, so a compressed length would
  // be wrong. Keep the original length only when no encoding was applied.
  const encoding = upstream.headers.get('content-encoding');
  const length = upstream.headers.get('content-length');
  if (!encoding && length) res.setHeader('content-length', length);

  const cookies = [
    ...collectedCookies,
    ...(upstream.headers.getSetCookie?.() ?? []),
  ];
  if (cookies.length) {
    // set-cookie is not readable from browser scripts; expose it through a
    // custom header that the web adapter converts back. Cookies are only
    // relayed, never stored on the server.
    res.setHeader(
      'x-pili-set-cookie',
      Buffer.from(JSON.stringify(cookies), 'utf8').toString('base64'),
    );
  }
}

function isBlockedAddressError(error) {
  const chain = [error, error?.cause, error?.cause?.cause];
  return chain.some(
    (item) =>
      item?.code === 'EADDRBLOCKED' ||
      String(item?.message || '').includes('blocked_non_public_address'),
  );
}

function logRequestDetails(req, target, method) {
  if (!LOG_RESPONSES) return;
  const interesting = new Set([
    'bvid',
    'aid',
    'cid',
    'qn',
    'fnval',
    'platform',
    'try_look',
    'wts',
    'w_rid',
    'type',
    'oid',
    'pn',
    'ps',
    'web_location',
    'isGaiaAvoided',
  ]);
  const parts = parseRawQuery(target.search)
    .filter(([key]) => interesting.has(key))
    .map(([key, value]) => {
      if (key === 'w_rid' && value.length > 12) return `${key}=${value.slice(0, 12)}…`;
      return `${key}=${value.length > 120 ? `${value.slice(0, 120)}…` : value}`;
    });
  const cookie = req.headers['x-pili-cookie'] || req.headers['cookie'] || '';
  const cookieNames = cookie
    .split(';')
    .map((item) => item.split('=')[0].trim())
    .filter(Boolean);
  console.log(
    `[req] ${method} ${target.host}${target.pathname} ${parts.join('&')} cookies=[${cookieNames.join(',')}]`,
  );
}

const GRPC_DEFAULT_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function grpcUpstreamHeaders(req, target, body) {
  const skip = new Set([
    'host',
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'content-length',
    'accept-encoding',
    'origin',
    'referer',
    'user-agent',
    'content-type',
  ]);
  const headers = {
    ':method': 'POST',
    ':path': target.pathname + target.search,
    ':authority': target.host,
    'content-type': 'application/grpc',
    te: 'trailers',
  };
  for (const [key, value] of Object.entries(req.headers)) {
    if (typeof value !== 'string' || !value) continue;
    if (skip.has(key) || key.startsWith('sec-') || key.startsWith('x-pili-')) {
      continue;
    }
    headers[key] = value;
  }
  const cookie = req.headers['x-pili-cookie'];
  if (typeof cookie === 'string' && cookie) headers.cookie = cookie;
  const ua = req.headers['x-pili-user-agent'];
  headers['user-agent'] =
    typeof ua === 'string' && ua ? ua : GRPC_DEFAULT_UA;
  if (body.length > 0 && body[0] === 1 && !headers['grpc-encoding']) {
    headers['grpc-encoding'] = 'gzip';
  }
  return headers;
}

async function relayGrpc(req, res, target) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 16 * 1024 * 1024) {
      return sendJson(res, 413, { error: 'grpc_body_too_large' });
    }
    chunks.push(chunk);
  }
  const body = Buffer.concat(chunks);
  const headers = grpcUpstreamHeaders(req, target, body);
  let client;
  let finished = false;
  const fail = (error) => {
    if (finished) return;
    finished = true;
    try {
      client?.close();
    } catch {}
    if (!res.headersSent) {
      sendJson(res, 502, {
        error: 'grpc_upstream_failed',
        message: error instanceof Error ? error.message : String(error),
      });
    } else {
      res.destroy(error);
    }
  };

  try {
    client = http2.connect(target.origin, { lookup: safeLookup });
  } catch (error) {
    return fail(error);
  }
  client.on('error', fail);
  const stream = client.request(headers);
  const parts = [];
  let status = null;
  let message = null;
  let details = null;
  let upstreamContentType = '';
  const capture = (upstreamHeaders) => {
    if (upstreamHeaders['content-type']) {
      upstreamContentType = String(upstreamHeaders['content-type']);
    }
    if (upstreamHeaders['grpc-status'] !== undefined) {
      status = String(upstreamHeaders['grpc-status']);
    }
    if (upstreamHeaders['grpc-message'] !== undefined) {
      message = String(upstreamHeaders['grpc-message']);
    }
    if (upstreamHeaders['grpc-status-details-bin'] !== undefined) {
      details = String(upstreamHeaders['grpc-status-details-bin']);
    }
  };
  stream.on('response', capture);
  stream.on('trailers', capture);
  stream.on('data', (chunk) => parts.push(chunk));
  stream.on('error', fail);
  stream.on('end', () => {
    if (finished) return;
    finished = true;
    const responseBody = Buffer.concat(parts);
    if (LOG_REQUESTS) {
      console.log(
        `[grpc] status=${status ?? '?'} bytes=${responseBody.length} ${target.pathname}`,
      );
    }
    if (LOG_RESPONSES && upstreamContentType.includes('json')) {
      console.log(
        `[grpc] upstream returned JSON: ${responseBody.toString('utf8').slice(0, 200)}`,
      );
    }
    let responseStatus = status ?? (responseBody.length > 0 ? '0' : '13');
    if (upstreamContentType.includes('json') && responseBody.length > 0) {
      responseStatus = '13';
      message = responseBody.toString('utf8').slice(0, 200);
    }
    const responseHeaders = {
      'content-type': 'application/grpc',
      'grpc-status': responseStatus,
    };
    if (message) responseHeaders['grpc-message'] = message;
    if (details) responseHeaders['grpc-status-details-bin'] = details;
    res.writeHead(200, responseHeaders);
    res.end(responseBody);
    client.close();
  });
  const timer = setTimeout(() => {
    if (!finished) {
      try {
        stream.close(http2.constants.NGHTTP2_CANCEL);
      } catch {}
      fail(new Error('grpc timeout'));
    }
  }, 30000);
  timer.unref();
  stream.end(body);
}

let anonBuvidCache = { cookie: '', at: 0 };

async function getAnonymousBuvidCookie() {
  if (anonBuvidCache.cookie && Date.now() - anonBuvidCache.at < 10 * 60_000) {
    return anonBuvidCache.cookie;
  }
  try {
    const response = await fetchUpstream(
      'https://api.bilibili.com/x/frontend/finger/spi',
      {
        headers: {
          accept: 'application/json',
          referer: 'https://www.bilibili.com/',
          'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
        dispatcher: upstreamDispatcher,
        signal: AbortSignal.timeout(10000),
      },
    );
    const body = await response.json();
    const b3 = body?.data?.b_3;
    const b4 = body?.data?.b_4;
    if (!b3 || !b4) return '';
    const cookie = `buvid3=${b3}; buvid4=${b4}; b_nut=${Math.floor(Date.now() / 1000)}`;
    anonBuvidCache = { cookie, at: Date.now() };
    return cookie;
  } catch {
    return '';
  }
}

async function signLiveDanmakuTarget(target) {
  if (!target.pathname.includes('getDanmuInfo')) return;
  if (target.searchParams.has('w_rid')) return;
  const key = await getWbiMixinKey();
  if (!key) return;
  const map = new Map(parseRawQuery(target.search));
  map.set('wts', String(Math.floor(Date.now() / 1000)));
  const query = [...map.keys()]
    .sort()
    .map(
      (k) =>
        `${encodeURIComponent(k)}=${encodeURIComponent(
          (map.get(k) || '').replace(/[!'()*]/g, ''),
        )}`,
    )
    .join('&');
  const rid = createHash('md5').update(query + key).digest('hex');
  target.searchParams.set('wts', map.get('wts'));
  target.searchParams.set('w_rid', rid);
  if (LOG_REQUESTS) console.log('[live-dm] signed WBI');
}

async function injectLiveDanmakuCookies(headers, target) {
  if (!target.pathname.includes('getDanmuInfo')) return;
  headers.set('origin', 'https://live.bilibili.com');
  const existing = headers.get('cookie') || '';
  const names = new Set(
    existing
      .split(';')
      .map((item) => item.split('=')[0].trim())
      .filter(Boolean),
  );
  if (names.has('buvid4')) return;
  const cookie = await getAnonymousBuvidCookie();
  if (!cookie) return;
  const additions = cookie
    .split('; ')
    .filter((item) => !names.has(item.split('=')[0].trim()));
  if (additions.length) {
    headers.set('cookie', [existing, ...additions].filter(Boolean).join('; '));
    if (LOG_REQUESTS) {
      console.log(
        `[live-dm] injected anonymous buvid (${additions
          .map((i) => i.split('=')[0])
          .join(',')})`,
      );
    }
  }
}

async function relay(req, res, target) {
  let current = target;
  const collectedCookies = [];
  let method = req.method || 'GET';
  const media = isMediaRequest(req, target);
  const signal = AbortSignal.timeout(media ? MEDIA_TIMEOUT_MS : UPSTREAM_TIMEOUT_MS);
  const hasBody = !['GET', 'HEAD'].includes(method);

  let body;
  if (hasBody) {
    body = Readable.toWeb(req);
  }

  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects += 1) {
    const headers = upstreamHeaders(req, current, method);
    await injectLiveDanmakuCookies(headers, current);
    if (redirects > 0) {
      // Only allow redirects to bilibili-owned hosts. Cookies are kept because
      // login flows hop between bilibili subdomains; the allowlist keeps them
      // from ever reaching an unrelated host.
      if (!isAllowedHost(current.hostname)) {
        return sendJson(res, 403, { error: 'redirect_target_not_allowed' });
      }
    }
    const upstream = await fetchUpstream(current, {
      method,
      headers,
      body,
      redirect: 'manual',
      signal,
      dispatcher: upstreamDispatcher,
      duplex: hasBody ? 'half' : undefined,
    });

    if (LOG_REQUESTS) {
      console.log(
        `[proxy] -> ${upstream.status} ${method} ${current.host}${current.pathname}`,
      );
    }
    if (LOG_RESPONSES && !isMediaRequest(req, current)) {
      const contentType = upstream.headers.get('content-type') || '';
      if (contentType.includes('json')) {
        try {
          const text = await upstream.clone().text();
          const body = JSON.parse(text);
          if (body && body.code !== undefined) {
            console.log(
              `[api] code=${body.code} msg=${body.message || ''} ${method} ${current.host}${current.pathname}`,
            );
          }
        } catch {
          // Non-JSON or empty body: ignore.
        }
      }
    }

    if (
      upstream.status >= 300 &&
      upstream.status < 400 &&
      upstream.headers.has('location') &&
      redirects < MAX_REDIRECTS
    ) {
      const next = new URL(upstream.headers.get('location'), current);
      if (next.protocol !== 'http:' && next.protocol !== 'https:') {
        return sendJson(res, 502, { error: 'unsupported_redirect_scheme' });
      }
      collectedCookies.push(...(upstream.headers.getSetCookie?.() ?? []));
      current = next;
      await upstream.body?.cancel();
      if (
        upstream.status === 303 ||
        ((upstream.status === 301 || upstream.status === 302) &&
          method === 'POST')
      ) {
        method = 'GET';
        body = undefined;
      }
      continue;
    }

    copyResponseHeaders(upstream, res, collectedCookies);
    res.statusCode = upstream.status;
    if (method === 'HEAD' || !upstream.body) {
      res.end();
      return;
    }
    const stream = Readable.fromWeb(upstream.body);
    stream.on('error', () => res.destroy());
    res.on('close', () => stream.destroy());
    stream.pipe(res);
    return;
  }
  return sendJson(res, 508, { error: 'too_many_redirects' });
}

async function serveHls(req, res, url) {
  const target = getTarget(req, url);
  if (!target) return sendJson(res, 400, { error: 'missing_target' });
  if (target.protocol !== 'http:' && target.protocol !== 'https:') {
    return sendJson(res, 400, { error: 'unsupported_scheme' });
  }
  if (!isAllowedHost(target.hostname)) {
    return sendJson(res, 403, { error: 'host_not_allowed', host: target.hostname });
  }
  try {
    const upstream = await fetchUpstream(target, {
      headers: {
        accept: '*/*',
        referer: 'https://live.bilibili.com/',
        'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      },
      redirect: 'follow',
      dispatcher: upstreamDispatcher,
      signal: AbortSignal.timeout(20000),
    });
    if (!upstream.ok) {
      return sendJson(res, 502, { error: 'hls_upstream_failed', status: upstream.status });
    }
    const text = await upstream.text();
    const base = new URL(upstream.url || target.toString());
    const rewrite = (value) => {
      const absolute = new URL(value, base).toString();
      const pathname = new URL(absolute).pathname;
      const playlist = pathname.toLowerCase().endsWith('.m3u8');
      return playlist
        ? `/hls?url=${encodeURIComponent(absolute)}`
        : `/proxy?url=${encodeURIComponent(absolute)}`;
    };
    const lines = text.split(/\r?\n/).map((line) => {
      if (!line) return line;
      const trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        return line.replace(/URI="([^"]*)"/g, (_, value) => `URI="${rewrite(value)}"`);
      }
      return rewrite(trimmed);
    });
    if (LOG_REQUESTS) {
      console.log(`[hls] ${target.host}${target.pathname}`);
    }
    res.writeHead(200, {
      'content-type': 'application/vnd.apple.mpegurl',
      'cache-control': 'no-store',
    });
    res.end(lines.join('\n'));
  } catch (error) {
    sendJson(res, 502, {
      error: 'hls_upstream_failed',
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

function serveStatic(req, res, url) {
  if (!existsSync(STATIC_DIR)) {
    if (url.pathname === '/') {
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      });
      res.end(`<!doctype html>
<html lang="zh-CN"><meta charset="utf-8">
<title>PiliPlus Web Proxy</title>
<style>body{font:15px/1.7 system-ui,sans-serif;max-width:720px;margin:48px auto;padding:0 20px;color:#333}code{background:#f4f5f7;padding:2px 5px;border-radius:4px}</style>
<h1>PiliPlus Web Proxy</h1>
<p>服务端已启动。静态页面尚未构建，请先运行：</p>
<pre><code>source .tooling/env.sh
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run</code></pre>
<p>也可以把 <code>build/web</code> 部署到任意静态托管，并在此服务端设置
<code>STATIC_DIR</code> 直接托管。</p>
<ul>
<li><a href="/health">/health</a> 健康检查</li>
<li><code>/proxy</code> 请求转发端点</li>
</ul>
<p>账号与 Cookie 仅保存在浏览器，本服务不落盘、不记录请求内容。</p>`);
      return;
    }
    return sendJson(res, 404, {
      error: 'static_dir_missing',
      hint: 'Build the web app first: flutter build web --release --no-wasm-dry-run',
      staticDir: STATIC_DIR,
    });
  }
  let pathname;
  try {
    pathname = decodeURIComponent(url.pathname);
  } catch {
    return sendJson(res, 400, { error: 'bad_path' });
  }
  const relative = normalize(pathname).replace(/^([/\\])+/, '');
  let filePath = resolve(join(STATIC_DIR, relative));
  if (!filePath.startsWith(STATIC_DIR + sep) && filePath !== STATIC_DIR) {
    return sendJson(res, 403, { error: 'forbidden' });
  }
  if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
    const wantsHtml =
      url.pathname === '/' || (req.headers.accept || '').includes('text/html');
    filePath = join(STATIC_DIR, 'index.html');
    if (!wantsHtml || !existsSync(filePath)) {
      return sendJson(res, 404, { error: 'not_found' });
    }
  }
  const stat = statSync(filePath);
  const ext = extname(filePath).toLowerCase();
  const base = filePath.slice(STATIC_DIR.length + 1);
  const shellFile =
    base === 'index.html' ||
    base === 'flutter_bootstrap.js' ||
    base === 'flutter_service_worker.js' ||
    base === 'main.dart.js' ||
    base === 'manifest.json';
  res.writeHead(200, {
    'content-type': MIME_TYPES[ext] || 'application/octet-stream',
    'content-length': stat.size,
    'cache-control': shellFile ? 'no-store' : 'public, max-age=3600',
  });
  if (req.method === 'HEAD') return res.end();
  createReadStream(filePath).pipe(res);
}

const liveWss = new WebSocketServer({ noServer: true });

function isAllowedLiveWsTarget(target) {
  const host = target.hostname.toLowerCase();
  return host === 'chat.bilibili.com' || host.endsWith('.chat.bilibili.com');
}

function relayLiveWebSocket(req, socket, head) {
  let target;
  try {
    const requestUrl = new URL(req.url || '/', 'http://localhost');
    if (requestUrl.pathname !== '/live-ws') {
      socket.destroy();
      return;
    }
    const raw = requestUrl.searchParams.get('target');
    if (!raw) {
      socket.destroy();
      return;
    }
    target = new URL(raw);
  } catch {
    socket.destroy();
    return;
  }
  if (target.protocol !== 'wss:' && target.protocol !== 'ws:') {
    socket.destroy();
    return;
  }
  if (!isAllowedLiveWsTarget(target)) {
    socket.destroy();
    return;
  }
  liveWss.handleUpgrade(req, socket, head, (client) => {
    if (LOG_REQUESTS) {
      console.log(`[live-ws] connect ${target.host}${target.pathname}`);
    }
    const upstream = new WebSocket(target.toString(), {
      headers: {
        'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      },
      handshakeTimeout: 10000,
    });
    const pending = [];
    let upstreamOpen = false;
    const closeBoth = () => {
      try {
        client.close();
      } catch {}
      try {
        upstream.close();
      } catch {}
    };
    client.on('message', (data, isBinary) => {
      if (upstreamOpen) {
        upstream.send(data, { binary: isBinary });
      } else {
        pending.push([data, isBinary]);
      }
    });
    upstream.on('open', () => {
      upstreamOpen = true;
      for (const [data, isBinary] of pending) {
        upstream.send(data, { binary: isBinary });
      }
      pending.length = 0;
    });
    upstream.on('message', (data, isBinary) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data, { binary: isBinary });
      }
    });
    client.on('close', closeBoth);
    client.on('error', closeBoth);
    upstream.on('close', closeBoth);
    upstream.on('error', (error) => {
      if (LOG_REQUESTS) console.log(`[live-ws] upstream error ${error.message}`);
      closeBoth();
    });
  });
}

const server = http.createServer(async (req, res) => {
  setCors(req, res);
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (url.pathname === '/health' || url.pathname === '/api/health') {
    return sendJson(res, 200, {
      ok: true,
      name: 'piliplus-web-proxy',
      version: SERVER_VERSION,
      node: process.version,
      allowedHosts: ALLOWED_HOSTS,
      allowedPatterns: DEFAULT_ALLOWED_PATTERNS.map((pattern) => pattern.source),
      dnsGuard: 'public-address-only (IPv4 + IPv6)',
      auth: Boolean(PROXY_TOKEN),
    });
  }

  if (url.pathname === '/hls') {
    return serveHls(req, res, url);
  }

  if (url.pathname === '/proxy' || url.pathname === '/api/proxy') {
    if (!authorized(req)) {
      return sendJson(res, 401, { error: 'unauthorized' });
    }
    const target = getTarget(req, url);
    if (!target) {
      return sendJson(res, 400, { error: 'missing_target' });
    }
    if (target.protocol !== 'http:' && target.protocol !== 'https:') {
      return sendJson(res, 400, { error: 'unsupported_scheme' });
    }
    if (target.username || target.password) {
      return sendJson(res, 400, { error: 'userinfo_not_allowed' });
    }
    if (!isAllowedHost(target.hostname)) {
      return sendJson(res, 403, {
        error: 'host_not_allowed',
        host: target.hostname,
      });
    }
    if (LOG_REQUESTS) {
      console.log(`[proxy] ${req.method} ${target.host}${target.pathname}`);
    }
    try {
      logRequestDetails(req, target, req.method || 'GET');
      const contentType = req.headers['content-type'] || '';
      if (contentType.startsWith('application/grpc')) {
        await relayGrpc(req, res, target);
        return;
      }
      await signLiveDanmakuTarget(target);
      await sanitizeWbiTarget(target);
      await relay(req, res, target);
    } catch (error) {
      if (res.headersSent) {
        res.destroy(error);
      } else if (isBlockedAddressError(error)) {
        sendJson(res, 403, { error: 'private_address_blocked' });
      } else {
        sendJson(res, 502, {
          error: 'upstream_failed',
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }
    return;
  }

  if (req.method === 'GET' || req.method === 'HEAD') {
    return serveStatic(req, res, url);
  }
  return sendJson(res, 404, { error: 'not_found' });
});

server.on('upgrade', relayLiveWebSocket);

server.listen(PORT, HOST, () => {
  const shown = HOST === '0.0.0.0' ? '127.0.0.1' : HOST;
  console.log(`PiliPlus web proxy ${SERVER_VERSION}`);
  console.log(`  listen:    http://${shown}:${PORT}`);
  console.log(`  static:    ${STATIC_DIR}`);
  console.log(`  auth:      ${PROXY_TOKEN ? 'token required' : 'none (local use)'}`);
  console.log(`  allowlist: ${ALLOWED_HOSTS.join(', ')}`);
  console.log('Cookies and account data are relayed only; nothing is stored.');
});
