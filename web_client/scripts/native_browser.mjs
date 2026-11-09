import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {chromium} from 'playwright';
import {emitTiming, timed} from './test_timings.mjs';

// Every browser request, including service workers and WebSockets, traverses
// this owned proxy. Only fixture origins explicitly registered by the caller
// can reach the network. No DNS lookup is performed for rejected targets.
export async function createNativeBrowser({externalOrigins = []} = {}) {
    const approvedExternal = new Set(['https://www.googletagmanager.com']);
    for (const origin of externalOrigins) assert.ok(approvedExternal.has(origin), 'unapproved external fixture origin');
    const allowed = new Set(externalOrigins);
    const sockets = new Set();
    let denied = 0;
    const hostname = url => url.hostname.replace(/^\[|\]$/g, '');
    function track(socket) { if (!sockets.has(socket)) { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); } return socket; }
    function pair(a,b) { track(a);track(b);a.once('close',()=>b.destroy());b.once('close',()=>a.destroy()); }
    function target(raw) {
        let url;
        try { url = new URL(raw); } catch { return null; }
        if (url.protocol === 'ws:') url.protocol = 'http:';
        if (url.protocol !== 'http:' || !allowed.has(url.origin)) return null;
        return url;
    }
    const proxy = http.createServer((req, res) => {
        const url = target(req.url);
        if (!url) { denied++; res.writeHead(403); res.end(); return; }
        const upstream = http.request({hostname: hostname(url), autoSelectFamily:true,
            port: url.port, method:req.method, path:url.pathname + url.search, headers:req.headers}, response => {
            res.writeHead(response.statusCode, response.headers); response.pipe(res);
        });
        upstream.on('socket',track);
        upstream.on('error', () => { if (!res.headersSent) res.writeHead(502); res.end(); });
        res.on('close', () => upstream.destroy());
        req.pipe(upstream);
    });
    proxy.on('connect', (req, socket, head) => {
        const remote = allowed.has(`https://${req.url.replace(/:443$/, '')}`) && req.url.endsWith(':443');
        const url = remote ? new URL(`https://${req.url}`) : target(`http://${req.url}`);
        if (!url || url.pathname !== '/') { denied++; socket.destroy(); return; }
        const upstream = net.connect(Number(url.port || (url.protocol === 'https:' ? 443 : 80)), hostname(url), () => {
            socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
            if (head.length) upstream.write(head);
            socket.pipe(upstream).pipe(socket);
        });
        pair(socket,upstream);
        upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
    });
    proxy.on('upgrade', (req, socket, head) => {
        const url = target(req.url);
        if (!url) { denied++; socket.destroy(); return; }
        const upstream = net.connect(Number(url.port || (url.protocol === 'https:' ? 443 : 80)), hostname(url), () => {
            upstream.write(`${req.method} ${url.pathname}${url.search} HTTP/${req.httpVersion}\r\n`);
            for (let i=0; i<req.rawHeaders.length; i+=2) upstream.write(`${req.rawHeaders[i]}: ${req.rawHeaders[i+1]}\r\n`);
            upstream.write('\r\n'); if (head.length) upstream.write(head); socket.pipe(upstream).pipe(socket);
        });
        pair(socket,upstream);
        upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
    });
    proxy.on('connection', track);
    async function closeProxy() {
        for (const socket of sockets) socket.destroy();
        await new Promise((resolve,reject)=>proxy.close(error=>error ? reject(error) : resolve()));
    }
    await new Promise((resolve,reject) => {proxy.once('error',reject);proxy.listen(0,'127.0.0.1',resolve);});
    const port=proxy.address().port;
    let browser;
    try {
        browser = await timed('browser.launch', () => chromium.launch({headless:true,
            proxy:{server:`http://127.0.0.1:${port}`}, args:['--site-per-process', '--proxy-bypass-list=<-loopback>', '--disable-quic', '--disable-background-networking', '--force-webrtc-ip-handling-policy=disable_non_proxied_udp', '--mute-audio']}));
    } catch (error) { await closeProxy(); throw error; }
    const contexts = new Set();
    let created=0, closing=false, disconnected=false, closePromise;
    browser.on('disconnected', () => { if (!closing) disconnected=true; });
    return {
        allow(origin) {
            const url=new URL(origin);
            assert.ok(url.protocol==='http:' && ['127.0.0.1','localhost','[::1]'].includes(url.hostname) && url.port && url.origin===origin,
                'fixture origin must be explicit local HTTP and port');
            allowed.add(origin);
        },
        get deniedRequests() { return denied; },
        async context(options={}) {
            assert.ok(!closing, 'browser owner is closed');
            assert.deepEqual(Object.keys(options).filter(key => key !== 'viewport'), [], 'unsupported context options');
            const context=await timed('browser.context-start',()=>browser.newContext({...options, colorScheme:null}));
            contexts.add(context);created++;
            await context.addInitScript(({origins}) => {
                const permitted = raw => {
                    try { return origins.includes(new URL(raw instanceof Request ? raw.url : raw, location.href).origin); }
                    catch { return true; }
                };
                const originalFetch=window.fetch;
                window.fetch=function(input,...args) {
                    if (!permitted(input)) return Promise.reject(new DOMException('Network target is not allowed','SecurityError'));
                    return originalFetch.call(this,input,...args);
                };
                const originalOpen=XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open=function(method,url,...args) {
                    if (!permitted(url)) throw new DOMException('Network target is not allowed','SecurityError');
                    return originalOpen.call(this,method,url,...args);
                };
            }, {origins:[...allowed]});
            context.once('close',()=>contexts.delete(context));
            return context;
        },
        async setTopLevelColorScheme(page, scheme) {
            assert.ok(contexts.has(page.context()), 'page must belong to this owner');
            assert.ok(scheme === 'light' || scheme === 'dark');
            const session = await page.context().newCDPSession(page);
            await session.send('Emulation.setEmulatedMedia', {features:[{name:'prefers-color-scheme', value:scheme}]});
        },
        close() {
            if (closePromise) return closePromise;
            closePromise = (async () => {
                const started=performance.now();
                const unexpected=disconnected; closing=true;
                const errors=[];
                for (const context of contexts) {
                    try { await context.close(); } catch (error) { errors.push(error); }
                }
                try { await browser.close(); } catch (error) { errors.push(error); }
                try { await closeProxy(); } catch (error) { errors.push(error); }
                emitTiming('browser.lifecycle',started,{contexts:created,deniedRequests:denied});
                if (unexpected) errors.push(new Error('Owned browser disconnected unexpectedly'));
                if (errors.length) throw new AggregateError(errors,'Owned browser cleanup failed');
            })();
            return closePromise;
        },
    };
}
