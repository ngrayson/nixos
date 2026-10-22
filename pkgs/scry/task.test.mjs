// node --test pkgs/scry/task.test.mjs  (flake check: scry-task-tests)
// Pure parsing only: importing task.mjs touches no network or Notion.
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseDue, parseInbox } from "./task.mjs";

test("an issue or PR number stays in the title, not taken as an area", () => {
  const t = parseInbox("Review PR #482 p1");
  assert.equal(t.area, null);
  assert.equal(t.title, "Review PR #482");
  assert.equal(t.priority, "P1");
});

test("a letter-first #tag is still an area", () => {
  const t = parseInbox("Replace COLD drive p2 #hearth due:2026-11-03 @agent");
  assert.deepEqual(t, { title: "Replace COLD drive", priority: "P2", area: "hearth", due: "2026-11-03", who: "Agent" });
});

test("impossible dates are refused, not rolled over", () => {
  assert.throws(() => parseDue("feb 30"), /can't read due date/);
  assert.throws(() => parseDue("oct 32"), /can't read due date/);
  assert.throws(() => parseDue("2026-02-30"), /no such day/);
});

test("real dates still parse", () => {
  assert.equal(parseDue("2028-02-29"), "2028-02-29");
  assert.match(parseDue("feb 28"), /^\d{4}-02-28$/);
  assert.match(parseDue("+3d"), /^\d{4}-\d{2}-\d{2}$/);
});
