# VS Code reads /etc/vscode/policy.json on Linux (1.96+; the path is hard-coded in
# 1.119.0's main.js). It is root-owned, so a user-level process — all the
# 2026-10-30 anthropic.claude-code 2.1.313 backdoor had — cannot loosen it the
# way it could ~/.config/Code/User/settings.json. AllowedExtensions is the
# `extensions.allowed` object as a JSON string: id -> exact versions. Anything
# else is refused on install and disabled if already present. To update an
# extension: bump the version here, switch, then update it in VS Code.
{...}: let
  allowed = {
    # Nix-built by home/theme/apps.nix (vscodeThemeExtension); any version.
    "stellarium.desktop-theme" = true;
    "adam-bender.commit-message-editor" = ["0.25.0"];
    "alefragnani.project-manager" = ["13.0.1" "13.1.0"];
    "anthropic.claude-code" = ["2.1.314"];
    "bbenoist.nix" = ["1.0.1"];
    "bierner.github-markdown-preview" = ["0.3.0" "0.4.0"];
    "bierner.markdown-checkbox" = ["0.4.0"];
    "bierner.markdown-emoji" = ["0.3.1"];
    "bierner.markdown-footnotes" = ["0.1.1"];
    "bierner.markdown-mermaid" = ["1.32.0" "1.32.1"];
    "bierner.markdown-preview-github-styles" = ["2.2.0"];
    "bierner.markdown-yaml-preamble" = ["0.1.0" "0.1.1"];
    "catppuccin.catppuccin-vsc" = ["3.18.1"];
    "codezombiech.gitignore" = ["0.10.0"];
    "daltonmenezes.aura-theme" = ["2.1.2"];
    "donjayamanne.git-extension-pack" = ["0.1.3"];
    "donjayamanne.githistory" = ["0.6.20"];
    "drewxs.tokyo-night-dark" = ["0.3.3"];
    "eamodio.gitlens" = ["17.10.2" "19.5.0"];
    "editorconfig.editorconfig" = ["0.18.1" "0.18.2"];
    "enkia.tokyo-night" = ["1.1.2"];
    "esbenp.prettier-vscode" = ["12.3.0" "12.4.0"];
    "github.codespaces" = ["1.18.16" "1.18.5"];
    "github.copilot-chat" = ["0.18.2"];
    "jovejonovski.ocean-green" = ["1.1.2"];
    "medo64.render-crlf" = ["1.9.10" "1.9.3"];
    "ms-python.debugpy" = ["2025.18.0" "2026.6.0"];
    "ms-python.isort" = ["2025.0.0" "2026.6.0"];
    "ms-python.python" = ["2026.10.0" "2026.2.0"];
    "ms-python.vscode-pylance" = ["2026.1.1" "2026.4.1"];
    "ms-python.vscode-python-envs" = ["1.20.1" "1.40.0"];
    "ms-vscode.cmake-tools" = ["1.22.28" "1.24.42"];
    "ms-vscode.cpp-devtools" = ["0.6.18"];
    "ms-vscode.cpptools" = ["1.30.5" "1.34.4"];
    "ms-vscode.cpptools-extension-pack" = ["1.5.1"];
    "ms-vscode.cpptools-themes" = ["2.0.0"];
    "ms-vscode.live-server" = ["0.4.17" "0.4.20"];
    "ms-vscode.makefile-tools" = ["0.12.17"];
    "ms-vscode.remote-explorer" = ["0.5.0"];
    "ms-vscode-remote.remote-ssh" = ["0.122.0" "0.124.0"];
    "ms-vscode-remote.remote-ssh-edit" = ["0.87.0"];
    "ritwickdey.liveserver" = ["5.7.10"];
    "ryanluker.vscode-coverage-gutters" = ["2.14.0" "2.15.0"];
    "sainnhe.everforest" = ["0.3.0"];
    "s-nlf-fh.glassit" = ["0.2.6"];
    "spadin.zmk-tools" = ["1.5.0"];
    "svelte.svelte-vscode" = ["109.14.2" "110.3.2"];
    "tamasfe.even-better-toml" = ["0.21.2"];
    "twxs.cmake" = ["0.0.17"];
    "ziyasal.vscode-open-in-github" = ["1.3.6"];
  };
in {
  environment.etc."vscode/policy.json".text = builtins.toJSON {
    AllowedExtensions = builtins.toJSON allowed;
  };
}
