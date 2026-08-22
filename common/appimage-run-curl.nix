# appimage-run with libcurl that provides CURL_OPENSSL_4 (Slippi / other AppImages).
# Used by profiles/workstation.nix and profiles/media-desktop.nix.
{pkgs}:
  pkgs.appimage-run.override {
    extraPkgs = p: [p.curl];
  }
