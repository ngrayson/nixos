# GCP NixOS image

`nixosConfigurations.Gcp` is a minimal headless image. It imports only the server-safe base, the server profile, and NixOS's Google Compute image module.

Included:

- OpenSSH with password and root login disabled
- NixOS firewall allowing TCP 22
- GCP guest agent, metadata scripts, disk growth, and serial console
- Local `admin` account with passwordless sudo
- SSH key delivery through GCP instance metadata

The VPC firewall created by the helper allows SSH from `0.0.0.0/0`. Narrow the source range in `scripts/gcp/create-instance.sh` before deployment when a fixed administrative CIDR is available.

## Network exposure (audit 2026-09-05)

Gcp is the only genuinely internet-facing host in the flake: it has a public address and, unlike the LAN machines, no `tailscale0` entry in `trustedInterfaces`, so `profiles/server.nix`'s `allowedTCPPorts = [22]` sits on the public interface. sshd is key-only (`PasswordAuthentication` and `PermitRootLogin` off), so this is not an open door, but it should be gated. Because the host does not exist yet, the decision is staged rather than applied — see the comment in `host.nix`:

- **Preferred, once Gcp is on the tailnet:** mirror Tawa — `services.openssh.openFirewall = false`, drop `22` from `allowedTCPPorts`, and trust `tailscale0`. Only after confirming tailnet reachability, or you lock yourself out with no console to walk to.
- **Until then:** the GCP VPC firewall is the real control — narrow the SSH source range (above) rather than leaning on the OS firewall alone.

## Build

The image build uses a temporary VM, so `/dev/kvm` must be available:

```bash
scripts/gcp/build-image.sh
```

The output is linked at `result-gcp/` by default.

## Upload and register

Authenticate `gcloud` first, then choose a globally unique bucket:

```bash
scripts/gcp/upload-image.sh PROJECT BUCKET nixos-2605
```

## Create an instance

Pass an existing OpenSSH public key. The private key never enters the Nix store or repository.

```bash
scripts/gcp/create-instance.sh \
  PROJECT us-west1-b nixos-1 nixos-2605 ~/.ssh/id_ed25519.pub
```

The script disables OS Login on the instance because this profile deliberately uses the metadata-managed `admin` account. To use organization-wide OS Login instead, remove the SSH metadata, enable OS Login in `host.nix`, and grant IAM roles outside this repository.

## Validate without building the image

```bash
# Evaluates all four host module graphs (hostname checks). Not formatter-only.
nix flake check --no-build
# Real image-build path:
nix build .#nixosConfigurations.Gcp.config.system.build.toplevel
```
