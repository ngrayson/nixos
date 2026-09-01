# Hearth GitOps — why push-based, and why not comin

Historical detail moved out of [`hosts/Hearth/plan.md`](../hosts/Hearth/plan.md)
H7 on 2026-08-31, when that file outgrew Conveyor's 32,000-character overview
cap for the `hearth` tag. **The decision itself is unchanged** and still lives
in plan.md (decision 21 and H7): push-based `hearth-deploy` from the
`deploy/hearth` pin; comin cancelled. This file keeps the full reasoning, so
the analysis is not lost and does not have to be redone if a puller is ever
reconsidered.

**Why not comin (2026-08-25).** `hearth-deploy` already satisfies all five
guardrails; comin satisfies one (polling a dedicated branch). It has no path
filtering, its `operation` is a static `switch`/`test`/`boot` per branch rather
than conditional on what changed, and health-check plus rollback would have to
be hand-written in `postDeploymentCommand`. Its only real gain is applying
changes with Tawa asleep — but the filter works *because* the pin only advances
through `hearth-deploy`, so promoting from a phone or the GitHub UI (the whole
point) would bypass it and auto-apply shared-tree changes. Kernel bumps arrive
via `flake.lock`, so guardrail 3 falls with guardrail 2. Comin is also absent
from the pinned nixpkgs, so it needs a `flake.nix`/`flake.lock` input that the
filter itself blocks, and it evaluates and builds on the target with no
`--build-host`, which would run the intranet's `buildNpmPackage` on the media
host and contradict guardrail 4. **Prerequisite for revisiting any puller:**
enforce the path filter server-side on `deploy/hearth` (branch protection plus
a required check running `refuse_shared_deploy_paths` logic). With that in
place, `nixos-autodeploy` is the better candidate — `switchMode = "smart"`
boots on kernel/initrd/module changes and switches otherwise, and its dirty
flag suspends auto-updates after a manual push deploy — at the cost of a binary
cache plus CI publishing a system path, which also restores build-on-Tawa.
