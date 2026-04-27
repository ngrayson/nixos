# Was NixOS `programs.git` + `GIT_CONFIG_SYSTEM`; now `~/.config/git/config` via HM.
{pkgs, ...}: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "wiz";
        email = "windows@example.com";
      };
      core = {
        editor = "micro";
        autocrlf = "input";
      };
      init.defaultBranch = "main";
      pull.rebase = false;
      push.default = "simple";
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
      };
      credential = {
        "https://github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!${pkgs.gh}/bin/gh auth git-credential"
        ];
      };
    };
  };
}
