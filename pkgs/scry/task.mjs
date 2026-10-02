// Scrying Orb — file one row in Nick's Tasks (Notion) from inbox-grammar text.
//   node task.mjs Replace COLD drive p2 #hearth due:fri @agent
// Tokens: p0-p3 · #area (a Nick's Areas name) · due:<2026-10-04|oct 4|fri|+3d|tomorrow> · @nick|@agent|@collab
// Prints only the new page's URL on stdout; on error prints "❌ <reason>" on stderr and exits 1.
// The functions are exported so the Discord bot (bot.mjs) shares one grammar and one Notion schema.
// Env: NOTION_TOKEN; optional NOTION_TASKS_DS / NOTION_AREAS_DS, ASSIGNEE_PROP, SCRY_TZ.
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const env = { ...process.env };
if (existsSync(join(here, ".env")))
  for (const line of readFileSync(join(here, ".env"), "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m && !env[m[1]]) env[m[1]] = m[2];
  }

export const TASKS_DS = env.NOTION_TASKS_DS || "3e455378-c593-806e-a39b-000b64fe8273";
export const AREAS_DS = env.NOTION_AREAS_DS || "5b2a0194-1d20-4eb7-a602-38d35b5566a8";
export const PRIORITIES = ["P0", "P1", "P2", "P3"];
export const WHO = ["Nick", "Agent", "Collaboration"];
// Host-local by default (the unit inherits Hearth's time.timeZone); SCRY_TZ overrides.
const TZ = env.SCRY_TZ || Intl.DateTimeFormat().resolvedOptions().timeZone;

// ---- Notion ----
export const notion = async (path, body) => {
  if (!env.NOTION_TOKEN) throw new Error("missing NOTION_TOKEN");
  const res = await fetch(`https://api.notion.com/v1/${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.NOTION_TOKEN}`, "Notion-Version": "2025-09-03", "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`notion ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.json();
};
let areaCache = { at: 0, rows: [] };
export const areas = async () => {
  if (Date.now() - areaCache.at > 10 * 60e3) {
    const j = await notion(`data_sources/${AREAS_DS}/query`, { page_size: 100 });
    areaCache = { at: Date.now(), rows: j.results.map((r) => ({ id: r.id, name: (r.properties.Name?.title || []).map((t) => t.plain_text).join("") })) };
  }
  return areaCache.rows;
};
export const createTask = async ({ title, priority, area, due, who }) => {
  const props = {
    Name: { title: [{ text: { content: title } }] },
    Status: { status: { name: "Not started" } },
    // Nick renamed "Assignee" → "Type" in Notion (digest.mjs reads the same); ASSIGNEE_PROP overrides.
    [env.ASSIGNEE_PROP || "Type"]: { select: { name: who || "Nick" } },
  };
  if (priority) props.Priority = { select: { name: priority } };
  if (due) props["Due Date"] = { date: { start: due } };
  if (area) {
    const row = (await areas()).find((a) => a.name.toLowerCase() === area.toLowerCase());
    if (!row) throw new Error(`unknown area "${area}" — one of: ${(await areas()).map((a) => a.name).join(", ")}`);
    props.Area = { relation: [{ id: row.id }] };
  }
  const page = await notion("pages", { parent: { data_source_id: TASKS_DS }, properties: props });
  return page.url;
};

// ---- date parsing: 2026-10-04 | oct 4 | fri | +3d | tomorrow ----
const today = () => new Date(new Date().toLocaleDateString("en-CA", { timeZone: TZ }));
const iso = (d) => d.toISOString().slice(0, 10);
export const parseDue = (s) => {
  if (!s) return null;
  s = s.trim().toLowerCase();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const t = today();
  if (s === "today") return iso(t);
  if (s === "tomorrow" || s === "tmr") return iso(new Date(t.getTime() + 864e5));
  let m = s.match(/^\+(\d+)([dw])$/);
  if (m) return iso(new Date(t.getTime() + Number(m[1]) * (m[2] === "w" ? 7 : 1) * 864e5));
  const days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
  const di = days.findIndex((d) => s.startsWith(d));
  if (di >= 0) { const delta = ((di - t.getUTCDay() + 7) % 7) || 7; return iso(new Date(t.getTime() + delta * 864e5)); }
  m = s.match(/^([a-z]{3,})\.?\s*(\d{1,2})$/);
  if (m) {
    const mi = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].indexOf(m[1].slice(0, 3));
    if (mi >= 0) { let d = new Date(Date.UTC(t.getUTCFullYear(), mi, Number(m[2]))); if (d < t) d = new Date(Date.UTC(t.getUTCFullYear() + 1, mi, Number(m[2]))); return iso(d); }
  }
  throw new Error(`can't read due date "${s}" — try 2026-10-04, oct 4, fri, +3d`);
};

// ---- inbox text: "Replace COLD drive p2 #hearth due:fri @agent" ----
export const parseInbox = (text) => {
  const out = { title: text, priority: null, area: null, due: null, who: null };
  const take = (re, f) => { const m = out.title.match(re); if (m) { f(m); out.title = out.title.replace(m[0], " "); } };
  take(/(?:^|\s)(p[0-3])(?=\s|$)/i, (m) => (out.priority = m[1].toUpperCase()));
  take(/(?:^|\s)#([a-z0-9-]+)/i, (m) => (out.area = m[1]));
  take(/(?:^|\s)due:(\S+(?:\s\d{1,2})?)/i, (m) => (out.due = parseDue(m[1])));
  take(/(?:^|\s)@(nick|agent|collab(?:oration)?)(?=\s|$)/i, (m) => (out.who = m[1].toLowerCase().startsWith("collab") ? "Collaboration" : m[1][0].toUpperCase() + m[1].slice(1).toLowerCase()));
  out.title = out.title.replace(/\s+/g, " ").trim();
  if (!out.title) throw new Error("no title left after parsing tokens");
  return out;
};

// ---- CLI (only when run directly, so `import` from bot.mjs does nothing) ----
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  try {
    const url = await createTask(parseInbox(process.argv.slice(2).join(" ")));
    console.log(url);
  } catch (e) {
    console.error(`❌ ${e.message}`);
    process.exit(1);
  }
}
