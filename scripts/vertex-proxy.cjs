const http = require('http');
const https = require('https');
const fs = require('fs');

const CONFIG_PATH = '/data/data/com.termux/files/home/.moltbot/moltbot.json';
const PORT = 19000;
const TARGET_HOST = 'aiplatform.googleapis.com';
const TARGET_PREFIX = '/v1/publishers/google';

// Increase global agent limits to prevent bottlenecks
https.globalAgent.maxSockets = 50;

function getKey() {
    try {
        const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
        const config = JSON.parse(raw);
        return config.env?.vars?.VERTEX_API_KEY;
    } catch (e) {
        console.error("Failed to read key:", e);
        return null;
    }
}

const server = http.createServer((req, res) => {
    // 1. Basic Setup & Key Check
    const key = getKey();
    if (!key) {
        res.writeHead(500);
        res.end("VERTEX_API_KEY not found");
        return;
    }

    const finalPath = TARGET_PREFIX + req.url;
    const targetUrl = new URL(`https://${TARGET_HOST}${finalPath}`);
    targetUrl.searchParams.append("key", key);

    // Logging (Masked Key)
    const logUrl = new URL(targetUrl.toString());
    logUrl.searchParams.set("key", "HIDDEN");
    console.log(`[Proxy] ${req.method} ${logUrl.pathname}${logUrl.search}`);

    // 2. Header Cleaning
    const cleanHeaders = {};
    const allowedHeaders = ['content-type', 'accept', 'user-agent'];
    Object.keys(req.headers).forEach(h => {
        if (allowedHeaders.includes(h.toLowerCase())) {
            cleanHeaders[h.toLowerCase()] = req.headers[h];
        }
    });
    cleanHeaders['host'] = TARGET_HOST;
    // Force connection close to avoid hanging sockets in simple proxy
    cleanHeaders['connection'] = 'close'; 

    const options = {
        method: req.method,
        headers: cleanHeaders,
        timeout: 60000 // 60s timeout for outgoing request
    };

    // 3. Request Forwarding with improved Error Handling
    const proxyReq = https.request(targetUrl, options, (proxyRes) => {
        res.writeHead(proxyRes.statusCode, proxyRes.headers);
        proxyRes.pipe(res);
    });

    // Ensure we pipe the body from client to target
    req.pipe(proxyReq);

    // 4. Timeouts & Errors
    proxyReq.on('timeout', () => {
        console.error("[Proxy Timeout] Request timed out");
        proxyReq.destroy();
        if (!res.headersSent) {
            res.writeHead(504);
            res.end("Gateway Timeout");
        }
    });

    proxyReq.on('error', (e) => {
        console.error("[Proxy Error]", e.message);
        if (!res.headersSent) {
            res.writeHead(502);
            res.end("Bad Gateway");
        }
    });

    req.on('error', (e) => {
        console.error("[Client Error]", e.message);
        proxyReq.destroy();
    });
});

// Server level timeout
server.setTimeout(65000);

server.listen(PORT, () => {
    console.log(`Vertex AI Proxy (Robust) running on http://127.0.0.1:${PORT}`);
});
