// Build a "what's on my plate" digest from Conveyor.
// Usage: node digest.mjs [--post]   → prints markdown; --post also sends it to Discord.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const env = { ...process.env };
// Local dev reads ./.env; on Hearth the systemd EnvironmentFile provides the same keys.
if (existsSync(join(here, ".env")))
  for (const line of readFileSync(join(here, ".env"), "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m && !env[m[1]]) env[m[1]] = m[2];
  }
for (const k of ["CONVEYOR_API_URL", "CONVEYOR_USER_TOKEN"]) if (!env[k]) throw new Error(`missing ${k}`);

const ME = "cmspfw8km0ael01s67umqsxjm";
// Statuses in pipeline order; anything not Complete/Cancelled is "live".
const ORDER = ["ReviewLive", "ReviewDev", "ReviewPR", "InProgress", "Planning", "Open"];
const LABEL = {
  ReviewLive: "verify live", ReviewDev: "review (dev)", ReviewPR: "review PR",
  InProgress: "in progress", Planning: "planning", Open: "open",
};

const transport = new StdioClientTransport({
  command: "node",
  args: ["-r", join(here, "preload.cjs"), join(here, "node_modules/@rallycry/conveyor-mcp/dist/cli.js")],
  env, stderr: "pipe",
});
const client = new Client({ name: "plate-digest", version: "0.1.0" });
await client.connect(transport);
const call = async (name, args = {}) => {
  const r = await client.callTool({ name, arguments: args });
  const t = (r.content || []).filter((c) => c.type === "text").map((c) => c.text).join("");
  try { return JSON.parse(t); } catch { return t; }
};

const projects = await call("list_projects");
const report = [];
for (const p of projects) {
  const mine = p.memberCount <= 1; // solo project → everything is mine
  const relevant = (t) => mine || t.assignedUserId === ME || (t.reviewers || []).some((r) => r.userId === ME);
  const buckets = {};
  for (const status of ORDER) {
    const tasks = await call("list_tasks", { projectId: p.id, status, limit: 50 });
    const rel = (Array.isArray(tasks) ? tasks : []).filter(relevant);
    if (rel.length) buckets[status] = rel;
  }
  const decisions = await call("list_decisions", { projectId: p.id, status: "open" });
  const incidents = await call("list_tasks", { projectId: p.id, typeFilters: ["incident"], limit: 50 });
  report.push({
    project: p, buckets,
    decisions: Array.isArray(decisions) ? decisions : (decisions?.decisions || []),
    incidents: (Array.isArray(incidents) ? incidents : []).filter((t) => relevant(t) && !["Complete", "Cancelled"].includes(t.status)),
  });
}
await client.close();

// ---- Notion: Nick's Tasks + Nick's Areas (official REST API; NOTION_TOKEN from env) ----
const NOTION_TASKS_DS = env.NOTION_TASKS_DS || "3e455378-c593-806e-a39b-000b64fe8273";
const NOTION_AREAS_DS = env.NOTION_AREAS_DS || "5b2a0194-1d20-4eb7-a602-38d35b5566a8";
const notion = { tasks: [], areas: [], enabled: !!env.NOTION_TOKEN };
if (notion.enabled) {
  const nq = async (ds, body = {}) => {
    const out = [];
    let cursor;
    do {
      const res = await fetch(`https://api.notion.com/v1/data_sources/${ds}/query`, {
        method: "POST",
        headers: { Authorization: `Bearer ${env.NOTION_TOKEN}`, "Notion-Version": "2025-09-03", "Content-Type": "application/json" },
        body: JSON.stringify({ ...body, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) }),
      });
      if (!res.ok) throw new Error(`notion ${res.status}: ${await res.text()}`);
      const j = await res.json();
      out.push(...j.results);
      cursor = j.has_more ? j.next_cursor : undefined;
    } while (cursor);
    return out;
  };
  const text = (p) => (p?.title || p?.rich_text || []).map((r) => r.plain_text).join("");
  const sel = (p) => p?.select?.name || p?.status?.name || null;
  const rows = await nq(NOTION_TASKS_DS, { filter: { property: "Status", status: { does_not_equal: "Done" } } });
  notion.tasks = rows.map((r) => ({
    id: r.id, url: r.url,
    title: text(r.properties.Name),
    status: sel(r.properties.Status),
    assignee: sel(r.properties.Assignee),
    priority: sel(r.properties.Priority),
    due: r.properties["Due Date"]?.date?.start || null,
    tags: (r.properties.Tags?.multi_select || []).map((t) => t.name),
    parent: (r.properties["Parent item"]?.relation || []).length > 0,
    updatedAt: r.last_edited_time,
  }));
  const areas = await nq(NOTION_AREAS_DS);
  notion.areas = areas.map((r) => ({
    name: text(r.properties.Name), status: sel(r.properties.Status),
    next: text(r.properties["Next action"]), notes: text(r.properties["Agent notes"]),
    touched: r.properties["Last touched"]?.date?.start || null,
  }));
}

// ---- render ----
const age = (iso) => Math.round((Date.now() - new Date(iso)) / 864e5);
const isRelease = (t) => /^Release \d/.test(t.title);
const short = (t, n = 90) => (t.title.length > n ? t.title.slice(0, n - 1) + "…" : t.title);
const today = new Date().toLocaleDateString("en-CA", { timeZone: "America/Vancouver" });
const lines = [`**Plate — week of ${today}**`];

// Section 1: things only you can unblock.
const decisions = [], yours = [], verify = [], approve = [], releases = [];
for (const { project, buckets, decisions: ds, incidents } of report) {
  for (const d of ds) decisions.push({ project, d });
  for (const s of ["InProgress", "Planning", "Open"])
    for (const t of buckets[s] || []) if (!t.agentId) yours.push({ project, t, s });
  for (const t of buckets.ReviewLive || []) (isRelease(t) ? releases : verify).push({ project, t });
  for (const t of buckets.ReviewPR || []) approve.push({ project, t });
  for (const t of incidents) if (t.status === "Open" && !t.agentId) yours.push({ project, t, s: "incident" });
}
const byAge = (a, b) => new Date(a.t?.updatedAt || a.d?.updatedAt) - new Date(b.t?.updatedAt || b.d?.updatedAt);
yours.sort(byAge); verify.sort(byAge); approve.sort(byAge);

lines.push(`\n**Waiting on you**`);
if (decisions.length) {
  lines.push(`*Decisions open (${decisions.length})*`);
  for (const { project, d } of decisions) lines.push(`• ${project.name}: ${d.title || d.question || JSON.stringify(d).slice(0, 80)}`);
}
if (yours.length) {
  lines.push(`*Your tasks — no agent can move these (${yours.length})*`);
  for (const { project, t, s } of yours) lines.push(`• ${project.name}: ${short(t)}${s === "incident" ? " ⚠ incident" : ""} · ${age(t.updatedAt)}d`);
}
if (verify.length || approve.length) {
  lines.push(`*Verify / approve (${verify.length + approve.length})*`);
  for (const { project, t } of verify) lines.push(`• ${project.name}: verify live — ${short(t, 70)}${t.githubPRNumber ? ` (#${t.githubPRNumber})` : ""} · ${age(t.updatedAt)}d`);
  for (const { project, t } of approve) lines.push(`• ${project.name}: approve PR — ${short(t, 70)}${t.githubPRNumber ? ` (#${t.githubPRNumber})` : ""} · ${age(t.updatedAt)}d`);
}
// Notion tasks: yours/collab, not done. Overdue → due soon → by priority.
const PRI = { P0: 0, P1: 1, P2: 2, P3: 3 };
const dayDiff = (d) => Math.round((new Date(d) - new Date(today)) / 864e5);
const ntasks = notion.tasks
  .filter((t) => t.assignee !== "Agent" && !t.parent)
  .sort((a, b) => {
    const da = a.due ? dayDiff(a.due) : 9e9, db = b.due ? dayDiff(b.due) : 9e9;
    const oa = da <= 7 ? da : 1e6 + (PRI[a.priority] ?? 9), ob = db <= 7 ? db : 1e6 + (PRI[b.priority] ?? 9);
    return oa - ob;
  });
const agentQueue = notion.tasks.filter((t) => t.assignee === "Agent").length;
if (ntasks.length) {
  lines.push(`*Notion tasks (${ntasks.length})*`);
  for (const t of ntasks.slice(0, 10)) {
    const d = t.due ? dayDiff(t.due) : null;
    const when = d === null ? "" : d < 0 ? ` ⚠ ${-d}d overdue` : d === 0 ? " · due today" : d <= 7 ? ` · due in ${d}d` : ` · due ${t.due}`;
    const bits = [t.priority, t.status === "Waiting" ? "waiting" : null, t.assignee === "Collaboration" ? "collab" : null, t.tags.join("/") || null].filter(Boolean).join(" · ");
    lines.push(`• ${t.title}${bits ? ` [${bits}]` : ""}${when}`);
  }
  if (ntasks.length > 10) lines.push(`• …and ${ntasks.length - 10} more`);
}
if (releases.length) {
  const oldest = Math.max(...releases.map(({ t }) => age(t.updatedAt)));
  lines.push(`• ${releases.length} release cards in verify-live (oldest ${oldest}d) — batch-close?`);
}
if (!decisions.length && !yours.length && !verify.length && !approve.length && !releases.length && !ntasks.length) lines.push("• nothing — you're clear");

// Section 2: one line per project.
lines.push(`\n**Projects**`);
for (const { project, buckets, incidents } of report) {
  const n = (s) => buckets[s]?.length || 0;
  const live = ORDER.reduce((a, s) => a + n(s), 0);
  if (!live && !incidents.length) continue;
  const parts = [];
  if (n("InProgress")) parts.push(`${n("InProgress")} in progress`);
  if (n("ReviewDev")) parts.push(`${n("ReviewDev")} review-dev`);
  if (n("ReviewPR")) parts.push(`${n("ReviewPR")} review-pr`);
  if (n("ReviewLive")) parts.push(`${n("ReviewLive")} verify-live`);
  const backlog = n("Planning") + n("Open");
  if (backlog) parts.push(`${backlog} backlog`);
  if (incidents.length) parts.push(`${incidents.length} incident${incidents.length > 1 ? "s" : ""}`);
  lines.push(`• __${project.name}__ — ${parts.join(" · ")}`);
}
// Section 3: areas (Notion) — status, next action, agent notes needing attention.
if (notion.enabled && notion.areas.length) {
  lines.push(`\n**Areas**`);
  for (const a of notion.areas.filter((a) => a.status !== "Archived")) {
    const stale = a.touched ? Math.max(0, -dayDiff(a.touched)) : null;
    const bits = [a.status, a.next ? `next: ${a.next}` : "no next action", stale !== null && stale > 14 ? `${stale}d quiet` : null, a.notes ? "📝 agent notes" : null].filter(Boolean);
    lines.push(`• __${a.name}__ — ${bits.join(" · ")}`);
  }
  if (agentQueue) lines.push(`• ${agentQueue} task${agentQueue > 1 ? "s" : ""} queued for agents`);
} else if (!notion.enabled) lines.push(`\n_(Notion not configured — set NOTION_TOKEN)_`);
const md = lines.join("\n");
const outDir = env.PLATE_OUT || process.cwd();
try {
  writeFileSync(join(outDir, "digest.md"), md);
  writeFileSync(join(outDir, "digest.json"), JSON.stringify(report, null, 2));
} catch { /* read-only location (e.g. nix store) — stdout is enough */ }
console.log(md);

if (process.argv.includes("--post")) {
  if (!env.DISCORD_WEBHOOK_URL) throw new Error("missing DISCORD_WEBHOOK_URL");
  // Discord caps messages at 2000 chars; split on line boundaries.
  const chunks = [];
  let cur = "";
  for (const line of md.split("\n")) {
    if ((cur + "\n" + line).length > 1900) { chunks.push(cur); cur = line; } else cur = cur ? cur + "\n" + line : line;
  }
  chunks.push(cur);
  for (const content of chunks) {
    const res = await fetch(env.DISCORD_WEBHOOK_URL, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content, username: "Plate" }),
    });
    if (!res.ok) throw new Error(`discord ${res.status}: ${await res.text()}`);
  }
  console.error(`posted ${chunks.length} message(s)`);
}
