# Conveyor Personal Compute on Tawa

This page records how Conveyor build pods run on our own hardware instead of cloud codespaces: what we chose, why, and how to run it. The investigation was done on 2026-10-05, on the card "Link Tawa as a Conveyor Personal Compute VM and decide which projects use it". Upstream guides:
[managed personal compute](https://conveyor.rallycryapp.com/docs/guides/managed-personal-compute)
and [project prebake](https://conveyor.rallycryapp.com/docs/guides/project-prebake).

## Decisions

**Runtime: the VM runtime on Tawa.** Conveyor has two runtimes:

| Runtime | What it is | Requirements |
|---|---|---|
| **VM** | A Lima + QEMU guest on a personal computer | Lima ≥ 2.2 |
| **Host** | Bare k3s on a dedicated server | Ubuntu 24.04+ or Debian 12+, with `apt` and `systemd` |

Every host in this flake is NixOS, including the planned Gcp, so the Host runtime is out. Tawa has room for the VM: a 13700K with 24 threads and VT-x, 31 GiB of RAM (about 16 GiB of it in daily use), and 2.5 TB free on `/`.

**Timing: now, not after the GCP server.** The Gcp host is specced as an `e2-small` (2 vCPU, 2 GiB; see `scripts/gcp/create-instance.sh`), but a single Small pod needs 7 GiB. A box big enough to host pods costs about $50 a month always-on, and it would still have to run Debian to use the Host runtime.

**Projects**

| Project | Use it? | Why |
|---|---|---|
| **WizOs** | Yes, first | Its cloud codespace path is already broken ("machine type is not available for this repository"). |
| **Under the Stars** | Yes, second | Private repo with no toolchain, so a Small pod is plenty. |
| **foundation** | Not ours to switch | The repo is Logan's, and it bakes on his self-hosted runner. If the image is in GHCR, enabling the project on our instance is enough. If it is a Bake-Locally image, Logan shares his instance instead. |
| **Sunfall** | No | There's no Conveyor project yet. |

**Pods cannot deploy hosts.** A pod is isolated from Tawa's home directory, SSH keys and compositor by design. That makes pods suitable for evaluation, docs and script cards gated by `nix flake check`. Any card verified by `os-rebuild switch`, `hearth-deploy`, `go3-deploy` or a Quickshell reload stays with the local loop (`/convey-her-watch`) on Tawa.

## Costs and risks

- **Unqualified CLI.** The CLI is a "development bootstrap" and isn't release-qualified. A VM escape would reach Nick's daily driver, so enroll only Nick's own projects.
- **Memory.** A 12 GiB VM plus about 16 GiB of daily use leaves little headroom while gaming. Turn **Accept new work** off on the instance before a session.
- **Egress.** Pods sit behind an egress allowlist, so Nix fetches fail silently until `cache.nixos.org` and the other needed hosts are approved.
- **Billing.** Claude usage in a pod bills the project agent's credential, not the local Claude Code subscription. Check this in Project Settings → Cloud.
- **Commits to `main`.** Saving the bake settings makes Conveyor commit `.github/workflows/conveyor-prebake.yml` to both `main` and `dev`. That's expected; don't revert it.

## What the flake provides

- `common/conveyor-k3.nix`, imported by Tawa only, provides:
  - Lima from `nixpkgs-unstable` (2.2.0, where the pin has 2.1.3). QEMU comes along on `limactl`'s PATH.
  - User linger, so the VM service runs without a login session.
  - The `kvm` group.

  To add Theseus later, import the same file.
- `home/programs/conveyor-k3.nix` sets `NPM_CONFIG_PREFIX=~/.npm-global` and puts its `bin` on PATH. Nix's own npm prefix is a read-only store path. The CLI itself stays npm-installed, because Conveyor's update timer re-pins it.

## Per-project checklist

1. **Install and link.** This needs Nick at a browser, because pairing codes expire in 10 minutes.
   ```sh
   npm install -g @rallycry/conveyor-k3@<version from Profile → Integrations → Personal Compute → Link a machine>
   conveyor-k3 vm setup --instance=tawa --cpus=6 --memory=12 --disk=100
   conveyor-k3 vm link --instance=tawa
   ```
   In the browser, name the machine `Tawa`, allow **WizOs** and **Under the Stars** only, and set **Max concurrent builds** to 1. Then install it as a service so it survives reboots:
   ```sh
   conveyor-k3 vm stop --instance=tawa
   conveyor-k3 vm service install --instance=tawa
   ```
   Its storage is `~/.local/share/conveyor-k3-vms/tawa`.
2. **Egress allowlist.** Do this with the VM stopped. Run `conveyor-k3 vm allow --host=<h> --port=443` for each host that `vm setup` hasn't already approved, then `conveyor-k3 vm refresh`. The hosts to check are `cache.nixos.org`, `channels.nixos.org`, `github.com`, `api.github.com`, `objects.githubusercontent.com`, `registry.npmjs.org` and `ghcr.io`.
3. **Project settings.** In Project Settings → Cloud, set:
   - **Compute:** Personal Compute.
   - **Image Bake Runner:** GitHub Actions, with an empty registry (GHCR) and an empty runner label.
   - **Setup Command:** `.devcontainer/conveyor/setup.sh`.

   Bound the bake cadence with `bakeMaxStalenessHours: 24`, `bakeScheduleHourUtc: 9` and `bakeTriggerPaths: ["flake.lock", ".devcontainer/conveyor/**"]`.

   Saving needs the **Workflows** and **Packages** permissions on the Conveyor GitHub App. Then press **Bake now** and wait for a green `conveyor-prebake` run.
4. **Prove it.** Build one doc-only card and check that its pod is placed on Tawa and reaches a PR.

## Operating the instance

| Task | Command |
|---|---|
| Lifecycle | `conveyor-k3 vm start\|stop\|status\|update --instance=tawa` |
| Service logs | `journalctl --user -u conveyor-k3-vm@tawa -f` |
| Disk | `conveyor-k3 registry gc` |
| Pause before gaming | Instance panel → **Accept new work** off. Running pods are untouched. |

Never run `limactl stop` on the instance directly. Use `conveyor-k3 vm stop`.
