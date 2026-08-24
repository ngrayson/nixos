import { copyFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
for (const [src, dest] of [
  ["public/intranet-config.example.js", "public/intranet-config.js"],
  ["public/lan.example.js", "public/lan.js"],
]) {
  const from = join(root, src);
  const to = join(root, dest);
  if (!existsSync(to)) copyFileSync(from, to);
}
