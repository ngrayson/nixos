# NixOS on Framework — separate project

The **setup roadmap, phases, and notes** for NixOS on a Framework machine are **not** part of the Stellarium wrapper commit. They live in a **dedicated git repository** under the wrapper’s **`projects/`** tree (gitignored here), for example:

```text
projects/<category>/nixos-framework-setup/
```

Use any category folder that matches how you organize **`projects/`** (for example **`projects/documentation/`** if you add that layout). **`scripts/add-to-registry.sh`** looks for **`projects/*/<project-name>`**, so a **flat** path like **`projects/nixos-framework-setup/`** (no middle directory) will **not** be picked up by that script — either add a middle category directory or **edit `registry/projects.json` by hand** with the correct **`localPath`**.

Create or clone the repo locally, keep the markdown and snippets there, and **`git push`** to your own remote.

## Relationship to this wrapper

- **`os-rebuild.sh`** — lives **beside** these markdown files in **`projects/nixos-framework-setup/`**; you can `sudo install` it per Stellarium [quickstart](../../documentation/quickstart.md) (paths may be `scripts/os-rebuild.sh` at repo root in some checkouts). Behavior: **`NIXOS_CONFIG`** / **`NIXOS_DIR`**, `nixos-rebuild switch`, optional git diff/commit.
- **`~/.config/nixos`** — your **live system config** is a **separate git repo**. To version this roadmap with it, **copy the full `nixos-framework-setup/` tree** into that repo (see [README — How this relates](./README.md#how-this-relates-to-the-stellarium-wrapper-repo)); keep Stellarium’s copy in sync by hand if you use both.

## Registry

When you want this initiative listed alongside other work, add it to **`registry/projects.json`** using the normal [registry process](../processes/registry-process.md) (or edit the registry by hand with a suitable **`type`** / **`localPath`** if your tooling allows). The wrapper **never** commits project files under **`projects/`**; the registry only stores **metadata** pointing at your local path and remote.
