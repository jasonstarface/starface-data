import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const p = spawn("node", [join(root, "dist/server.js")]);
let out = "";
p.stdout.on("data", (c) => (out += c));
p.on("close", () => {
  out.trim().split(/\n/).forEach((l) => {
    try {
      const j = JSON.parse(l);
      if (j.id >= 10) {
        const t = j.result?.content?.[0]?.text || "";
        console.log(`[id ${j.id}] isError=${!!j.result?.isError} :: ${t.slice(0, 300).replace(/\n/g, " ")}`);
      }
    } catch {}
  });
});
const call = (id, name, args) =>
  JSON.stringify({ jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } });
const send = (s) => p.stdin.write(s + "\n");
send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "t", version: "1" } } }));
send(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }));
send(call(10, "query", { sql: "SELECT sales_channel, ROUND(SUM(net_revenue)) AS rev FROM `disco-stock-489818-d4.mart.orders` WHERE date >= '2026-06-01' GROUP BY 1 ORDER BY rev DESC" }));
send(call(11, "list_tables", { dataset: "mart" }));
send(call(12, "describe_table", { dataset: "mart", table: "orders" }));
send(call(13, "query", { sql: "WITH x AS (SELECT 1 AS n) SELECT n*2 AS doubled FROM x" }));
setTimeout(() => p.stdin.end(), 25000);
