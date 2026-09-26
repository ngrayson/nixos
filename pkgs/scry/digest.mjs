// Scrying Orb: build the weekly "scry" digest from Conveyor + Notion.
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
const client = new Client({ name: "scry-digest", version: "0.1.0" });
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
  const areas = await nq(NOTION_AREAS_DS);
  notion.areas = areas.map((r) => ({
    id: r.id, name: text(r.properties.Name), status: sel(r.properties.Status),
    next: text(r.properties["Next action"]), notes: text(r.properties["Agent notes"]),
    touched: r.properties["Last touched"]?.date?.start || null,
  }));
  const areaName = new Map(notion.areas.map((a) => [a.id, a.name]));
  const rows = await nq(NOTION_TASKS_DS, { filter: { property: "Status", status: { does_not_equal: "Done" } } });
  notion.tasks = rows.map((r) => ({
    id: r.id, url: r.url,
    title: text(r.properties.Name),
    status: sel(r.properties.Status),
    assignee: sel(r.properties[env.ASSIGNEE_PROP || "Type"] || r.properties.Assignee),
    priority: sel(r.properties.Priority),
    due: r.properties["Due Date"]?.date?.start || null,
    // Tags were folded into the Area relation; resolve ids → names via the areas fetched above.
    tags: (r.properties.Area?.relation || []).map((rel) => areaName.get(rel.id)).filter(Boolean),
    parent: (r.properties["Parent item"]?.relation || []).length > 0,
    updatedAt: r.last_edited_time,
  }));
}

// ---- render ----
const age = (iso) => Math.round((Date.now() - new Date(iso)) / 864e5);
const isRelease = (t) => /^Release \d/.test(t.title);
const short = (t, n = 90) => (t.title.length > n ? t.title.slice(0, n - 1) + "…" : t.title);
const today = new Date().toLocaleDateString("en-CA", { timeZone: "America/Vancouver" });
const lines = [`# 🔮 Scrying Orb — ${today}`];

// SCRY_MAX_ITEMS (PLATE_MAX_ITEMS still accepted): cap per group before "…and N more" (default 4).
const MAX = Math.max(1, parseInt(env.SCRY_MAX_ITEMS || env.PLATE_MAX_ITEMS || "4", 10) || 4);
const capped = (items, render) => {
  for (const it of items.slice(0, MAX)) lines.push(render(it));
  if (items.length > MAX) lines.push(`-# …and ${items.length - MAX} more`);
};

// Section 1: things only you can unblock — grouped by project, oldest first within a group.
const byAge = (a, b) => new Date(a.t?.updatedAt || a.d?.updatedAt || 0) - new Date(b.t?.updatedAt || b.d?.updatedAt || 0);
const groups = [];
let releases = [];
for (const { project, buckets, decisions: ds, incidents } of report) {
  const items = [];
  for (const d of ds) items.push({ d, kind: "decide" });
  for (const s of ["InProgress", "Planning", "Open"])
    for (const t of buckets[s] || []) if (!t.agentId) items.push({ t, kind: "yours" });
  for (const t of incidents) if (t.status === "Open" && !t.agentId) items.push({ t, kind: "incident" });
  for (const t of buckets.ReviewLive || []) (isRelease(t) ? releases : items).push(isRelease(t) ? { project, t } : { t, kind: "verify" });
  for (const t of buckets.ReviewPR || []) items.push({ t, kind: "approve" });
  if (items.length) groups.push({ name: project.name, slug: project.slug, items: items.sort(byAge) });
}
const cardUrl = (slug, t) => `https://conveyor.rallycryapp.com/projects/${slug}/cards/${t.slug}`;
const link = (text, url) => (url ? `[${text.replace(/[\[\]]/g, "\\$&")}](${url})` : text);
const renderItem = (slug) => ({ t, d, kind }) => {
  if (kind === "decide") return `- ❓ decide: ${link(d.title || d.question || JSON.stringify(d).slice(0, 80), d.slug && cardUrl(slug, d))}`;
  const pr = t.githubPRNumber ? ` ([#${t.githubPRNumber}](${t.githubPRUrl}))` : "";
  const tag = { yours: "", incident: " ⚠ incident", verify: " — verify live", approve: " — approve PR" }[kind];
  return `- ${link(short(t), t.slug && cardUrl(slug, t))}${pr}${tag} · ${age(t.updatedAt)}d`;
};

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
const renderNotion = (t) => {
  const d = t.due ? dayDiff(t.due) : null;
  const when = d === null ? "" : d < 0 ? ` ⚠ ${-d}d overdue` : d === 0 ? " · due today" : d <= 7 ? ` · due in ${d}d` : ` · due ${t.due}`;
  const bits = [t.priority, t.status === "Waiting" ? "waiting" : null, t.assignee === "Collaboration" ? "collab" : null, t.tags.join("/") || null].filter(Boolean).join(" · ");
  return `- ${link(t.title, t.url)}${bits ? ` [${bits}]` : ""}${when}`;
};

// # General — Notion tasks (yours / collab), at the top.
if (ntasks.length || !notion.enabled) {
  lines.push(`# General`);
  if (ntasks.length) capped(ntasks, renderNotion);
  else lines.push(`-# Notion not configured — set NOTION_TOKEN`);
}

// # Projects — one ## per Conveyor project: linked name + counts, then the items waiting on you.
lines.push(`# Projects`);
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
  const url = `https://conveyor.rallycryapp.com/projects/${project.slug}/cards`;
  lines.push(`## [${project.name}](${url}) — ${parts.join(" · ")}`);
  const g = groups.find((g) => g.name === project.name);
  if (g) capped(g.items, renderItem(project.slug));
  const rel = releases.filter((r) => r.project.id === project.id);
  if (rel.length) {
    const oldest = Math.max(...rel.map(({ t }) => age(t.updatedAt)));
    lines.push(`-# ${rel.length} release cards in verify-live (oldest ${oldest}d) — batch-close?`);
  }
}

// Notion areas are fetched (for future use / digest.json) but not rendered.
if (agentQueue) lines.push(`-# ${agentQueue} task${agentQueue > 1 ? "s" : ""} queued for agents`);
const md = lines.join("\n");
const outDir = env.SCRY_OUT || env.PLATE_OUT || process.cwd();
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
      // flags 4 = SUPPRESS_EMBEDS: linked titles must not spawn a link preview per line.
      body: JSON.stringify({ content, username: "Scrying Orb", flags: 4 }),
    });
    if (!res.ok) throw new Error(`discord ${res.status}: ${await res.text()}`);
  }
  console.error(`posted ${chunks.length} message(s)`);
}
