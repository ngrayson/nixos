import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, writeFileSync } from "node:fs";
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

function evalNix(rel) {
  const path = join(root, rel);
  if (!existsSync(path)) return null;
  try {
    const json = execFileSync(
      "nix-instantiate",
      ["--eval", "--json", "--strict", "--expr", `import ${JSON.stringify(path)}`],
      { encoding: "utf8" },
    );
    return JSON.parse(json);
  } catch {
    return null;
  }
}

const cfg = {
  weather: { locations: [], temperatureUnit: "F" },
  transit: { busStops: [], mapQuery: "", mapZoom: 10, mapProvider: "waze" },
};

const weather = evalNix("config/weather/config.nix");
if (weather) {
  cfg.weather.temperatureUnit = weather.temperatureUnit || "F";
  cfg.weather.locations = Array.isArray(weather.locations) ? weather.locations : [];
}

const transit = evalNix("config/transit/config.nix");
if (transit) {
  cfg.transit.mapQuery = transit.mapQuery || "";
  cfg.transit.mapZoom = transit.mapZoom || 10;
  cfg.transit.mapProvider = transit.mapProvider || "waze";
  cfg.transit.busStops = Array.isArray(transit.busStops)
    ? transit.busStops.map((stop) => ({
        id: stop.id,
        name: stop.name || "",
        skip: Boolean(stop.skip),
      }))
    : [];
}

writeFileSync(
  join(root, "public/intranet-config.js"),
  "window.hearthIntranet = " + JSON.stringify(cfg, null, 2) + ";\n",
);
