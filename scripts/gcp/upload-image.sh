#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 PROJECT BUCKET IMAGE_NAME [IMAGE_TAR_GZ]" >&2
  exit 2
}

[[ $# -ge 3 && $# -le 4 ]] || usage

project="$1"
bucket="${2#gs://}"
image_name="$3"
image_path="${4:-}"

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -z "$image_path" ]]; then
  shopt -s nullglob
  candidates=("$repo"/result-gcp/*.raw.tar.gz)
  ((${#candidates[@]} == 1)) || {
    echo "Expected one *.raw.tar.gz under $repo/result-gcp; pass its path explicitly." >&2
    exit 2
  }
  image_path="${candidates[0]}"
fi

[[ -f "$image_path" ]] || {
  echo "Image not found: $image_path" >&2
  exit 2
}

object="gs://$bucket/$(basename "$image_path")"

gcloud storage buckets describe "gs://$bucket" --project "$project" >/dev/null 2>&1 ||
  gcloud storage buckets create "gs://$bucket" --project "$project" --location=US

gcloud storage cp "$image_path" "$object" --project "$project"
gcloud compute images create "$image_name" \
  --project "$project" \
  --source-uri "$object" \
  --guest-os-features=UEFI_COMPATIBLE

printf 'Created image %s in project %s\n' "$image_name" "$project"
