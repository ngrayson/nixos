// Make every https request (incl. ws/socket.io) go through the session's HTTPS proxy.
const https = require("node:https");
const { HttpsProxyAgent } = require("https-proxy-agent");
if (process.env.HTTPS_PROXY) {
  const agent = new HttpsProxyAgent(process.env.HTTPS_PROXY);
  const orig = https.request;
  https.request = function (a, b, c) {
    if (typeof a === "string" || a instanceof URL) { b = { ...(b || {}) }; if (!b.agent) b.agent = agent; return orig.call(this, a, b, c); }
    a = { ...(a || {}) }; if (!a.agent) a.agent = agent; return orig.call(this, a, b, c);
  };
  https.get = function (a, b, c) { const r = https.request(a, b, c); r.end(); return r; };
}
