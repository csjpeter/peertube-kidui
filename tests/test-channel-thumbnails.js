// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Peter Csaszar (Császár Péter)
// Created: 2026-10-12
// Dependency-free node test of the channel list thumbnails (KIDUI-3), with a minimal DOM stub.

'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const player = html.split('<script>')[1].split('</script>')[0];

class El {
    constructor(tag) {
        this.tag = tag;
        this.children = [];
        this.style = {};
        this.classList = { add: (c) => { this.classes.push(c); } };
        this.classes = [];
        this.attrs = {};
        this.onclick = null;
        this.onerror = null;
        this.src = '';
        this.alt = '';
        this.textContent = '';
        this.innerHTML = '';
    }
    appendChild(c) { this.children.push(c); return c; }
    addEventListener() {}
}

// Runs loadChannels() against canned API responses and returns the rendered list element.
async function renderChannels(channels, videosByChannel) {
    const byId = {};
    const document = {
        getElementById: (id) => (byId[id] = byId[id] || new El('div')),
        querySelectorAll: () => [],
        createElement: (t) => new El(t),
        addEventListener: () => {},
    };
    const requests = [];
    const fetch = async (url) => {
        requests.push(url);
        if (url.includes('/video-channels?count=100')) {
            return { ok: true, json: async () => ({ data: channels.map(c => ({ ...c })) }) };
        }
        const m = url.match(/\/video-channels\/([^/]+)\/videos\?count=1&sort=-publishedAt$/);
        assert(m, `unexpected request: ${url}`);
        const r = videosByChannel[decodeURIComponent(m[1])];
        if (r === 'fail') { throw new Error('network'); }
        if (r === 'http500') { return { ok: false, json: async () => ({}) }; }
        return { ok: true, json: async () => ({ data: r }) };
    };
    const window = { location: { protocol: 'http:', hostname: 'host.example.org' } };
    new Function('window', 'document', 'fetch', 'console',
        `${player}\n videoPlayer();`)(window, document, fetch, console);
    await window.loadChannels();
    return { list: document.getElementById('content-list'), requests };
}

const BASE = 'http://host.example.org';
let failures = 0;
async function test(name, fn) {
    try { await fn(); console.log(`ok: ${name}`); }
    catch (e) { failures++; console.error(`FAIL: ${name}: ${e.message}`); }
}

(async () => {
    await test('card shows the latest video thumbnail, name below', async () => {
        const { list, requests } = await renderChannels(
            [{ name: 'cartoons', displayName: 'Cartoons' }],
            { cartoons: [{ thumbnailPath: '/lazy-static/thumbnails/a.jpg' }] });
        assert.strictEqual(list.children.length, 1);
        const card = list.children[0];
        assert.deepStrictEqual(card.classes, ['video-item']);
        assert.strictEqual(card.children[0].src, `${BASE}/lazy-static/thumbnails/a.jpg`);
        assert.strictEqual(card.children[1].textContent, 'Cartoons');
        assert(requests.some(u => u.endsWith('/api/v1/video-channels/cartoons/videos?count=1&sort=-publishedAt')));
    });

    await test('channel without videos falls back to the avatar', async () => {
        const { list } = await renderChannels(
            [{ name: 'empty', displayName: 'Empty', avatars: [{ path: '/lazy-static/avatars/e.png' }] }],
            { empty: [] });
        assert.strictEqual(list.children[0].children[0].src, `${BASE}/lazy-static/avatars/e.png`);
    });

    await test('channel without videos and avatar gets the placeholder', async () => {
        const { list } = await renderChannels([{ name: 'bare', displayName: 'Bare' }], { bare: [] });
        assert(list.children[0].children[0].src.startsWith('data:image/svg+xml,'));
    });

    await test('a failed fetch does not break the list and falls back silently', async () => {
        const { list } = await renderChannels(
            [{ name: 'a', displayName: 'A', avatar: { path: '/av/a.png' } },
             { name: 'b', displayName: 'B' },
             { name: 'c', displayName: 'C' }],
            { a: 'fail', b: 'http500', c: [{ thumbnailPath: '/t/c.jpg' }] });
        assert.strictEqual(list.children.length, 3);
        assert.strictEqual(list.children[0].children[0].src, `${BASE}/av/a.png`);
        assert(list.children[1].children[0].src.startsWith('data:image/svg+xml,'));
        assert.strictEqual(list.children[2].children[0].src, `${BASE}/t/c.jpg`);
    });

    await test('an image that fails to load steps to avatar, then placeholder', async () => {
        const { list } = await renderChannels(
            [{ name: 'x', displayName: 'X', avatars: [{ path: '/av/x.png' }] }],
            { x: [{ thumbnailPath: '/t/x.jpg' }] });
        const img = list.children[0].children[0];
        assert.strictEqual(img.src, `${BASE}/t/x.jpg`);
        img.onerror();
        assert.strictEqual(img.src, `${BASE}/av/x.png`);
        img.onerror();
        assert(img.src.startsWith('data:image/svg+xml,'));
        img.onerror();
        assert(img.src.startsWith('data:image/svg+xml,'));
    });

    await test('channels are sorted by name and cards stay clickable', async () => {
        const { list } = await renderChannels(
            [{ name: 'z', displayName: 'Zebra' }, { name: 'a', displayName: 'alpha' }],
            { z: [], a: [] });
        assert.deepStrictEqual(list.children.map(c => c.children[1].textContent), ['alpha', 'Zebra']);
        assert.strictEqual(typeof list.children[0].onclick, 'function');
    });

    process.exit(failures ? 1 : 0);
})();
