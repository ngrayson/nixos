#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 PROJECT ZONE INSTANCE_NAME IMAGE_NAME ADMIN_PUBLIC_KEY" >&2
  exit 2
}

[[ $# -eq 5 ]] || usage

project="$1"
zone="$2"
instance_name="$3"
image_name="$4"
public_key_file="$5"

[[ -f "$public_key_file" ]] || {
  echo "Public key not found: $public_key_file" >&2
  exit 2
}

public_key="$(<"$public_key_file")"
[[ "$public_key" == ssh-* ]] || {
  echo "Expected an OpenSSH public key in $public_key_file" >&2
  exit 2
}

# Defense in depth: GCP's VPC rule and the NixOS host firewall both restrict
# ingress to SSH. Narrow --source-ranges before use if 0.0.0.0/0 is unsuitable.
if ! gcloud compute firewall-rules describe allow-ssh \
  --project "$project" >/dev/null 2>&1; then
  gcloud compute firewall-rules create allow-ssh \
    --project "$project" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=ssh
fi

gcloud compute instances create "$instance_name" \
  --project "$project" \
  --zone "$zone" \
  --machine-type=e2-small \
  --boot-disk-size=20GB \
  --image="$image_name" \
  --image-project="$project" \
  --tags=ssh \
  --metadata=enable-oslogin=FALSE \
  --metadata="ssh-keys=admin:$public_key"

printf 'Connect with: gcloud compute ssh admin@%s --project %s --zone %s\n' \
  "$instance_name" "$project" "$zone"
