# NixOS on Framework — separate project

The **setup roadmap, phases, and notes** for NixOS on a Framework machine are **not** part of the Stellarium wrapper commit. They live in a **dedicated git repository** under the wrapper’s **`projects/`** tree (gitignored here), for example:

```text
projects/<category>/nixos-framework-setup/
```

Use any category folder that matches how you organize **`projects/`** (for example **`projects/documentation/`** if you add that layout). **`scripts/add-to-registry.sh`** looks for **`projects/*/<project-name>`**, so a **flat** path like **`projects/nixos-framework-setup/`** (no middle directory) will **not** be picked up by that script — either add a middle category directory or **edit `registry/projects.json` by hand** with the correct **`localPath`**.

Create or clone the repo locally, keep the markdown and snippets there, and **`git push`** to your own remote.

## Relationship to `~/.config/nixos` (this archive)

- **`os-rebuild.sh`** — the copy used on **Tawa** lives next to this **`archive/`** folder: **[`../os-rebuild.sh`](../os-rebuild.sh)**. Behavior: **`NIXOS_CONFIG`** / **`NIXOS_DIR`**, `nixos-rebuild switch`, optional git diff/commit.
- **Roadmap markdown** — these files are **archived**; current docs are **[`../../../MIGRATION.md`](../../../MIGRATION.md)** and **[`../../../home/`](../../../home/)**. See **[`../README.md`](../README.md)** (folder stub) and **[`README.md`](./README.md)** (this archive).

## Registry (Stellarium wrapper)

When this content lived under Stellarium’s **`projects/`** tree, you could register it in **`registry/projects.json`** per that repo’s process. The wrapper **never** commits project files under **`projects/`** by default; the registry only stores **metadata** pointing at your local path and remote.
