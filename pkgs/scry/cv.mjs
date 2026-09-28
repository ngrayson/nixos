// Minimal CLI to drive the Conveyor MCP server over stdio.
// Usage: node cv.mjs list | node cv.mjs call <tool> '<json-args>'
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const env = { ...process.env, GLOBAL_AGENT_HTTPS_PROXY: process.env.HTTPS_PROXY, GLOBAL_AGENT_HTTP_PROXY: process.env.HTTPS_PROXY };
for (const line of readFileSync(join(here, ".env"), "utf8").split("\n")) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2];
}

const transport = new StdioClientTransport({
  command: "node",
  args: ["-r", join(here, "preload.cjs"), join(here, "node_modules/@rallycry/conveyor-mcp/dist/cli.js")],
  env,
  stderr: "pipe",
});
const client = new Client({ name: "cowork-cv", version: "0.1.0" });
await client.connect(transport);

const [cmd, tool, argsJson] = process.argv.slice(2);
try {
  if (cmd === "list") {
    const { tools } = await client.listTools();
    for (const t of tools) console.log(`${t.name}: ${(t.description || "").split("\n")[0]}`);
  } else if (cmd === "schema") {
    const { tools } = await client.listTools();
    console.log(JSON.stringify(tools.find((t) => t.name === tool), null, 2));
  } else if (cmd === "call") {
    const res = await client.callTool({ name: tool, arguments: argsJson ? JSON.parse(argsJson) : {} });
    for (const c of res.content || []) console.log(c.type === "text" ? c.text : JSON.stringify(c));
    if (res.isError) process.exitCode = 1;
  }
} finally {
  await client.close();
}
