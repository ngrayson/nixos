# Wake the Go3 wall panel on camera motion, as a companion to the input-based
# wake go3-idle-blank already provides.
#
# PRIVACY IS THE POINT, and it is structural rather than a policy note. Frames
# are streamed from libcamera into this process's memory, compared, and
# discarded. Nothing is ever written to disk, and nothing is ever sent
# anywhere. The camera is not a sensor this host records from; it is a motion
# switch that happens to be made of pixels. That was Nick's explicit condition
# for the camera being used at all.
#
# The camera runs ONLY while the panel is dim or off. A wake trigger is useless
# while the screen is already lit, so the duty cycle collapses to idle hours —
# which is also what answers the power objection, since the kernel flags
# ipu3_imgu as staging quality and an ISP pipeline is not free on a tablet.
# Measured on the box: running the pipeline costs +1-2°C and no measurable load.
#
# Integration: this does NOT write the backlight or /run/go3-display/state.
# go3-idle-blank owns the panel, and two writers is exactly the fight that file
# contract exists to prevent. Instead a motion line is pushed into a FIFO that
# idle-blank's event stream also reads, so a wave of the hand looks like input
# to the state machine that is already tested.
{pkgs, ...}: let
  stateDir = "/run/go3-display";
  motionFifo = "${stateDir}/motion";
  # Frames arrive on their own FIFO, never a file. See the long comment on
  # read_frame() for why this is a FIFO and not cam's stdout.
  framesFifo = "${stateDir}/frames";

  # The front sensor (ov5693, \_SB_.PCI0.I2C4.CAMF) is the one facing the room.
  # Verified on the box: index 2 in `cam --list`.
  camera = "2";

  go3-camera-wake = pkgs.writeShellApplication {
    name = "go3-camera-wake";
    runtimeInputs = [pkgs.coreutils pkgs.libcamera pkgs.python3];
    text = ''
      set -euo pipefail

      STATE_DIR="''${GO3_STATE_DIR:-${stateDir}}"
      FIFO="''${GO3_MOTION_FIFO:-${motionFifo}}"
      CAMERA="''${GO3_CAMERA:-${camera}}"
      # Mean absolute luma delta, 0-255, above which a frame counts as motion.
      # Low enough to catch someone walking past, high enough that sensor noise
      # on an uncalibrated IPA does not trip it. Tunable on the wall.
      THRESHOLD="''${GO3_MOTION_THRESHOLD:-6}"
      # Compare roughly this often. The sensor runs at ~30fps and we discard
      # the frames in between: a wake trigger does not need more.
      INTERVAL="''${GO3_MOTION_INTERVAL:-1.0}"
      # MUST match what the pipeline actually negotiates, because frames are
      # read as a fixed-size byte stream: if the real plane is smaller, every
      # read slips and consecutive "frames" are misaligned garbage, which reads
      # as constant motion. Asking for 160x120 silently produced 128x120 on
      # this sensor, so the request is 128x120 and --strict-formats makes any
      # future mismatch fail loudly instead of silently desynchronising.
      WIDTH="''${GO3_MOTION_WIDTH:-128}"
      HEIGHT="''${GO3_MOTION_HEIGHT:-120}"
      # Seconds of frames to throw away after starting the camera, before any
      # comparison. Neither sensor has a calibrated IPA tuning file, so
      # auto-exposure ramps hard over the first frames and the luma swings
      # enormously while it converges. Without this the FIRST comparison after
      # every start fired: observed a delta of 65.5 against a threshold of 6,
      # one second after the panel dimmed, which woke the panel and looped.
      WARMUP="''${GO3_MOTION_WARMUP:-4.0}"
      # Consecutive over-threshold comparisons required to call it motion. A
      # person stays in frame for more than one sample; a single-frame sensor
      # spike does not.
      HITS="''${GO3_MOTION_HITS:-2}"

      export GO3_STATE_DIR="$STATE_DIR" GO3_MOTION_FIFO="$FIFO" \
             GO3_CAMERA="$CAMERA" GO3_MOTION_THRESHOLD="$THRESHOLD" \
             GO3_MOTION_INTERVAL="$INTERVAL" GO3_MOTION_WIDTH="$WIDTH" \
             GO3_MOTION_HEIGHT="$HEIGHT" GO3_MOTION_WARMUP="$WARMUP" \
             GO3_MOTION_HITS="$HITS"
      export GO3_FRAMES_FIFO="''${GO3_FRAMES_FIFO:-${framesFifo}}"
      export GO3_CAM_BIN="${pkgs.libcamera}/bin/cam"

      exec python3 - <<'PY'
      import errno, os, signal, subprocess, sys, time

      state_file = os.path.join(os.environ["GO3_STATE_DIR"], "state")
      fifo = os.environ["GO3_MOTION_FIFO"]
      camera = os.environ["GO3_CAMERA"]
      threshold = float(os.environ["GO3_MOTION_THRESHOLD"])
      interval = float(os.environ["GO3_MOTION_INTERVAL"])
      width = int(os.environ["GO3_MOTION_WIDTH"])
      height = int(os.environ["GO3_MOTION_HEIGHT"])
      warmup = float(os.environ["GO3_MOTION_WARMUP"])
      hits_needed = int(os.environ["GO3_MOTION_HITS"])
      frames_fifo = os.environ["GO3_FRAMES_FIFO"]
      cam_bin = os.environ["GO3_CAM_BIN"]
      # NV12: full-resolution luma followed by half-height interleaved chroma.
      FRAME_BYTES = width * height * 3 // 2
      LUMA_BYTES = width * height

      # Stages the camera is allowed to run in. While awake the trigger would
      # be pointless, so the pipeline is torn down entirely rather than idled.
      WATCH_STAGES = ("dim", "off")


      def log(msg):
          print(msg, file=sys.stderr, flush=True)


      def stage():
          try:
              with open(state_file, encoding="utf-8") as fh:
                  return fh.read().strip()
          except OSError:
              # No state file yet: idle-blank has not started. Do not run the
              # camera on a guess — a camera that turns itself on when the
              # panel state is unknown is exactly what must not happen.
              return "awake"


      def open_fifo():
          """Non-blocking write end, or None when nothing is reading.

          Opening a FIFO for write blocks until a reader exists, which would
          wedge this service whenever idle-blank is restarting. O_NONBLOCK
          turns that into ENXIO, which we treat as "no one is listening yet".
          """
          try:
              return os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
          except OSError as exc:
              if exc.errno in (errno.ENXIO, errno.ENOENT):
                  return None
              raise


      def notify():
          fd = open_fifo()
          if fd is None:
              log("motion: nothing reading the fifo; dropping")
              return
          try:
              os.write(fd, b"camera-motion\n")
          except OSError as exc:
              log(f"motion: fifo write failed ({exc.errno})")
          finally:
              os.close(fd)


      def start_cam():
          """libcamera writing raw NV12 frames into our FIFO.

          A FIFO rather than cam's stdout, for two independent reasons found by
          measurement on the box:

          1. cam writes its own progress text to stdout, interleaved with the
             frame bytes ("cam0: Capture 2 frames", a per-frame timing line).
             Those lines are variable length, so a fixed-size reader on stdout
             slips and compares misaligned bytes — which reads as constant
             motion.
          2. cam opens the output path afresh per frame, so each open on the
             FIFO delivers a whole number of complete frames. Frame boundaries
             therefore come from the open/close cycle rather than from byte
             counting, and cannot drift.

          A FIFO is a kernel object, not stored data: frames pass through RAM
          and are never given a file on any filesystem.
          """
          return subprocess.Popen(
              [cam_bin, "-c", camera, "-C",
               "-s", f"role=viewfinder,width={width},height={height},pixelformat=NV12",
               # Fail loudly rather than silently negotiating a different size:
               # asking for 160x120 quietly produced 128x120, and a wrong size
               # is exactly what breaks frame alignment.
               "--strict-formats",
               f"--file={frames_fifo}"],
              stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL,
              # Own process group, so a stuck pipeline can be killed as a unit.
              start_new_session=True,
          )


      def read_frame():
          """Latest complete frame from the FIFO, or None.

          One open can carry more than one frame if the writer got ahead, so
          the newest complete frame is taken and any older one discarded — this
          is a wake trigger, and stale frames are worth nothing.
          """
          try:
              with open(frames_fifo, "rb") as fh:
                  buf = fh.read()
          except OSError:
              return None
          if len(buf) < FRAME_BYTES:
              return None
          usable = (len(buf) // FRAME_BYTES) * FRAME_BYTES
          last = buf[usable - FRAME_BYTES:usable]
          # Only luma is kept; chroma is never examined.
          return last[:LUMA_BYTES]


      def stop_cam(proc):
          if proc is None or proc.poll() is not None:
              return
          try:
              os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
              proc.wait(timeout=5)
          except Exception:
              try:
                  os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
              except Exception:
                  pass
          log("camera stopped")


      def watch():
          """Run the camera while blanked; emit a line when the view changes."""
          proc = None
          previous = None
          last_compare = 0.0
          settled_at = 0.0
          hits = 0
          try:
              while True:
                  current = stage()
                  if current not in WATCH_STAGES:
                      if proc is not None:
                          stop_cam(proc)
                          proc, previous = None, None
                      time.sleep(2)
                      continue

                  if proc is None:
                      log(f"panel {current}; starting camera")
                      proc = start_cam()
                      previous = None
                      last_compare = 0.0
                      hits = 0
                      # Nothing is compared until the sensor has settled.
                      settled_at = time.monotonic() + warmup

                  if proc.poll() is not None:
                      log("camera exited; restarting")
                      proc, previous = None, None
                      time.sleep(2)
                      continue

                  frame = read_frame()
                  if frame is None:
                      time.sleep(0.2)
                      continue

                  now = time.monotonic()
                  if now < settled_at:
                      # Still converging; discard without comparing, and do not
                      # keep it as a reference frame either.
                      continue
                  if now - last_compare < interval:
                      continue
                  last_compare = now

                  if previous is not None:
                      # Mean absolute difference over the luma plane. Sampled
                      # every 4th byte: at this resolution that is still ~4800
                      # points, plenty for "did the room change", and it keeps
                      # the comparison cheap on a machine that has just had its
                      # thermal budget clawed back.
                      total = 0
                      count = 0
                      for i in range(0, LUMA_BYTES, 4):
                          total += abs(frame[i] - previous[i])
                          count += 1
                      delta = total / count if count else 0.0
                      hits = hits + 1 if delta >= threshold else 0
                      if hits >= hits_needed:
                          log(f"motion: delta {delta:.1f} >= {threshold} "
                              f"on {hits} consecutive samples")
                          notify()
                          # The panel is being woken; drop straight back to the
                          # awake check rather than re-triggering on our own
                          # backlight change lighting up the room.
                          stop_cam(proc)
                          proc, previous = None, None
                          time.sleep(2)
                          continue
                  previous = frame
          finally:
              stop_cam(proc)


      def main():
          # A terminating unit must never leave the camera powered.
          def bye(signum, _frame):
              raise SystemExit(0)

          signal.signal(signal.SIGTERM, bye)
          signal.signal(signal.SIGINT, bye)
          watch()


      main()
      PY
    '';
  };

  # Merges the real input stream with the motion FIFO, so idle-blank's state
  # machine sees motion as just another input event and its tested unblank path
  # is reused rather than duplicated.
  #
  # Deliberately degrades to plain libinput: if the FIFO is missing or the
  # camera service is dead, input-based wake must keep working exactly as
  # before. The camera is an addition to that path, never a dependency of it.
  go3-idle-events = pkgs.writeShellApplication {
    name = "go3-idle-events";
    runtimeInputs = [pkgs.coreutils pkgs.libinput];
    text = ''
      set -uo pipefail

      FIFO="''${GO3_MOTION_FIFO:-${motionFifo}}"

      if [[ -p "$FIFO" ]]; then
        # cat returns on every writer close, so it is restarted in a loop —
        # otherwise the motion half would go quiet after the first wake while
        # libinput carried on, and nothing would say why.
        while true; do
          cat "$FIFO" 2>/dev/null || true
          sleep 1
        done &
        # Without this a wake leaves the reader orphaned, holding the FIFO
        # open against the next start of this unit.
        trap 'kill %1 2>/dev/null || true' EXIT
      fi

      exec libinput debug-events
    '';
  };
in {
  # `p` creates the FIFO. Same directory and ownership as the state contract
  # idle-blank and ambient-brightness already share.
  systemd.tmpfiles.rules = [
    "p ${motionFifo} 0660 wiz video -"
    "p ${framesFifo} 0600 wiz video -"
  ];

  systemd.services.go3-camera-wake = {
    description = "Wake the Go3 kiosk panel on camera motion";
    # Deliberately NOT bound to cage-tty1, for the same reason idle-blank is
    # not: that coupling made editing this file restart the kiosk and blank the
    # wall mid-deploy. See the long comment in idle-blank.nix.
    after = ["go3-idle-blank.service"];
    wantedBy = ["graphical.target"];
    serviceConfig = {
      ExecStart = "${go3-camera-wake}/bin/go3-camera-wake";
      User = "wiz";
      # `video` for the camera devices; wiz is already a member.
      SupplementaryGroups = ["video"];
      Restart = "always";
      RestartSec = "10s";
      # Nothing this service does should ever produce a file.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [stateDir];
    };
  };

  # Hand idle-blank the merged stream. Its own default stays plain libinput, so
  # the module is still standalone if this one is ever removed.
  systemd.services.go3-idle-blank.environment.GO3_EVENT_CMD = "${go3-idle-events}/bin/go3-idle-events";
}
