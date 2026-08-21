# Phase 4: Touchpad palm rejection while typing

Goal: typing on the Surface Type Cover must not register palm/touchpad input
(cursor jumps, accidental clicks).

## Background

- libinput's disable-while-typing (dwt) is on by default **only when the
  device is classified as a touchpad**. Surface Type Covers are exposed via
  the linux-surface HID stack; on mainline kernels they can enumerate as a
  plain pointer, which silently disables dwt and palm detection. This is the
  most likely reason palm rejection "doesn't work" today under Plasma.
- The repo has zero touchpad configuration anywhere (`services.libinput.enable`
  only) — greenfield.

## Steps

1. **Diagnose first** (on the running Hearth session):

```bash
sudo libinput list-devices        # find the Type Cover touchpad entry
# Check: "Disable-w-typing: enabled"? Is the device a touchpad or a pointer?
sudo libinput debug-events --show-keycodes   # type + touch; watch for palm events
```

2. **Hyprland input config** — in the slim HM's Hyprland settings, Hearth-local
   (or shared if we decide Theseus benefits too; shared edit requires the
   parity guardrail):

```nix
input = {
  touchpad = {
    disable_while_typing = true;   # libinput dwt
    natural_scroll = true;         # match old Plasma feel (verify preference)
    tap-to-click = true;
    clickfinger_behavior = true;
  };
};
```

3. **If dwt still fails** (device misclassified or palm pressure thresholds
   wrong), add a libinput quirks override, e.g.:

```nix
environment.etc."libinput/local-overrides.quirks".text = ''
  [Surface Type Cover Touchpad]
  MatchName=*Type Cover*
  AttrPalmSizeThreshold=800
  AttrKeyboardIntegration=internal
'';
```

   (`MatchName` must be taken from the real device name in
   `libinput list-devices`; `AttrKeyboardIntegration=internal` tells libinput
   the keyboard and touchpad are one physical unit, which activates dwt.)

4. **Kernel dependency**: if diagnosis shows the touchpad isn't even exposed
   as a touchpad, the linux-surface patched kernel from
   `microsoft-surface-common` (phase 1) is the fix — prioritize getting that
   kernel built (remote build from Tawa if needed) before tuning quirks.

## Verification

Type a paragraph in kitty with palms resting on the Type Cover: no cursor
movement, no stray clicks. `libinput debug-events` shows touchpad events
suppressed during typing and for ~200ms after.
