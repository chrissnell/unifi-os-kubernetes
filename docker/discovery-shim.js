// uos-discovery-client ships as a stub binary that exits immediately, so
// nothing ever listens on port 11002 (the discoveryClientUrl that
// unifi-core polls). Without a listener, unifi-core logs two recurring
// warnings every few seconds:
//
//   [system] Failed to fetch network interfaces from discovery agent
//   [discovery.client] Error on client scan: ECONNREFUSED 127.0.0.1:11002
//
// This shim is a minimal HTTP server that satisfies those calls so the
// log spam stops and unifi-core gets a chance to resolve its lanIp:
//
//   GET /scan        → []                    (no UDP broadcast in a pod)
//   GET <anything>   → os.networkInterfaces() (matches unifi-core's
//                                              ZodRecord schema)
//   HEAD /healthz    → 200
//
// Runs under systemd as uos-discovery-shim.service. Uses only Node
// standard library — Node is already in the image (unifi-core is Node).

const http = require("http");
const os = require("os");

const PORT = Number(process.env.DISCOVERY_SHIM_PORT || 11002);
const HOST = process.env.DISCOVERY_SHIM_HOST || "127.0.0.1";

function writeJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  const method = req.method || "GET";
  const url = req.url || "/";

  if (method === "HEAD" && (url === "/" || url === "/healthz")) {
    res.statusCode = 200;
    return res.end();
  }

  if (url.startsWith("/scan")) {
    return writeJson(res, 200, []);
  }

  if (method === "GET") {
    return writeJson(res, 200, os.networkInterfaces());
  }

  return writeJson(res, 404, {});
});

server.listen(PORT, HOST, () => {
  console.log(`uos-discovery-shim listening on ${HOST}:${PORT}`);
});
