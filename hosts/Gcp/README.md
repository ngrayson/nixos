# GCP NixOS image

`nixosConfigurations.Gcp` is a minimal headless image. It imports only the server-safe base, the server profile, and NixOS's Google Compute image module.

Included:

- OpenSSH with password and root login disabled
- NixOS firewall allowing TCP 22
- GCP guest agent, metadata scripts, disk growth, and serial console
- Local `admin` account with passwordless sudo
- SSH key delivery through GCP instance metadata

The VPC firewall created by the helper allows SSH from `0.0.0.0/0`. Narrow the source range in `scripts/gcp/create-instance.sh` before deployment when a fixed administrative CIDR is available.

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
nix flake check --no-build
nix build .#nixosConfigurations.Gcp.config.system.build.toplevel
```
