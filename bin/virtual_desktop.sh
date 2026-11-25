#!/bin/bash
# A headless Linux desktop an agent can drive: an X display it can type into,
# click on and screenshot, for checking a GUI app the way a person would see it.
# Linux containers only; nothing here touches a real screen.
#
#   virtual_desktop.sh start   install what is missing, start the display
#   virtual_desktop.sh shot F  save a PNG of the whole screen to F
#   virtual_desktop.sh stop    stop the display and its window manager
#   virtual_desktop.sh missing list the packages start would install
#
# Packages install on first use rather than in the environment's setup script:
# few sessions need a screen, and the setup script delays every session.
#
# After `start`: export DISPLAY=:99, run the app, drive it with xdotool
# (`xdotool search --onlyvisible --class NAME`, `type`, `mousemove ... click 1`).

set -euo pipefail

DISPLAY_NUM=${VIRTUAL_DESKTOP_DISPLAY:-:99}
# 1280x800 is a small laptop screen: a layout that fits here fits most.
GEOMETRY=${VIRTUAL_DESKTOP_GEOMETRY:-1280x800x24}

# missing_packages: the apt packages whose tool is absent, one per line.
missing_packages() {
  command -v Xvfb >/dev/null 2>&1 || echo xvfb
  command -v openbox >/dev/null 2>&1 || echo openbox
  command -v xdotool >/dev/null 2>&1 || echo xdotool
  command -v import >/dev/null 2>&1 || echo imagemagick
  # Without a CJK font, Japanese UI text renders as boxes and looks like a bug.
  if ! fc-list :lang=ja 2>/dev/null | grep -q .; then
    echo fonts-noto-cjk
  fi
}

display_running() {
  xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1 ||
    DISPLAY=$DISPLAY_NUM xdotool getdisplaygeometry >/dev/null 2>&1
}

start() {
  local pkgs
  mapfile -t pkgs < <(missing_packages)
  if [ "${#pkgs[@]}" -gt 0 ]; then
    echo "[virtual_desktop] installing: ${pkgs[*]}" >&2
    # A fresh container's package lists may be stale; refresh only on a miss.
    apt-get install -y -q "${pkgs[@]}" >/dev/null || {
      apt-get update -q >/dev/null && apt-get install -y -q "${pkgs[@]}" >/dev/null
    }
  fi
  if display_running; then
    echo "[virtual_desktop] $DISPLAY_NUM already running" >&2
  else
    nohup Xvfb "$DISPLAY_NUM" -screen 0 "$GEOMETRY" >/dev/null 2>&1 &
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      display_running && break
      [ "$i" = 10 ] && { echo "x Xvfb did not come up on $DISPLAY_NUM" >&2; exit 1; }
      sleep 0.2
    done
    # A window manager gives windows focus and titles, so xdotool can find them.
    DISPLAY=$DISPLAY_NUM nohup openbox >/dev/null 2>&1 &
  fi
  echo "export DISPLAY=$DISPLAY_NUM"
}

case "${1:-}" in
  start) start ;;
  shot)
    [ -n "${2:-}" ] || { echo "usage: $0 shot FILE.png" >&2; exit 2; }
    import -display "$DISPLAY_NUM" -window root "$2"
    ;;
  stop)
    pkill -x openbox 2>/dev/null || true
    pkill -f "^Xvfb $DISPLAY_NUM" 2>/dev/null || true
    ;;
  missing) missing_packages ;;
  *) echo "usage: $0 start|shot FILE|stop|missing" >&2; exit 2 ;;
esac
