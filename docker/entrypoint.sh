#!/usr/bin/env bash
set -euo pipefail

XVFB_DISPLAY=${DISPLAY:-:99}
XVFB_RESOLUTION=${XVFB_RESOLUTION:-1920x1080x24}
XVFB_ARGS=${XVFB_ARGS:--nolisten tcp -ac}
VNC_PORT=${VNC_PORT:-5900}
NOVNC_PORT=${NOVNC_PORT:-6080}
WORKDIR=${FLUTTER_WEB_INTEGRATION_HOME:-/workspace}

cleanup() {
  local exit_code=$?
  if [[ -n "${WEBSOCKIFY_PID:-}" ]] && kill -0 "${WEBSOCKIFY_PID}" 2>/dev/null; then
    kill "${WEBSOCKIFY_PID}" || true
  fi
  if [[ -n "${X11VNC_PID:-}" ]] && kill -0 "${X11VNC_PID}" 2>/dev/null; then
    kill "${X11VNC_PID}" || true
  fi
  if [[ -n "${FLUXBOX_PID:-}" ]] && kill -0 "${FLUXBOX_PID}" 2>/dev/null; then
    kill "${FLUXBOX_PID}" || true
  fi
  if [[ -n "${XVFB_PID:-}" ]] && kill -0 "${XVFB_PID}" 2>/dev/null; then
    kill "${XVFB_PID}" || true
  fi
  wait || true
  exit $exit_code
}
trap cleanup EXIT INT TERM

# Start virtual display
Xvfb "$XVFB_DISPLAY" -screen 0 "$XVFB_RESOLUTION" $XVFB_ARGS &
XVFB_PID=$!

# Lightweight window manager for better Chrome behaviour
fluxbox >/tmp/fluxbox.log 2>&1 &
FLUXBOX_PID=$!

# Start VNC server attached to Xvfb
x11vnc \
  -display "$XVFB_DISPLAY" \
  -rfbport "$VNC_PORT" \
  -shared \
  -nopw \
  -forever \
  -o /tmp/x11vnc.log &
X11VNC_PID=$!

# Start websockify/noVNC
websockify --web=/usr/share/novnc/ "$NOVNC_PORT" localhost:"$VNC_PORT" >/tmp/websockify.log 2>&1 &
WEBSOCKIFY_PID=$!

cd "$WORKDIR"

# Ensure mounted directories exist
mkdir -p test_dsl test_target

# copy ssh files for git dependencies
if [ -d /ssh-host ]; then
  rm -rf /root/.ssh
  mkdir -p /root/.ssh
  cp -rT /ssh-host /root/.ssh
  chown -R root:root /root/.ssh
  chmod 700 /root/.ssh
  find /root/.ssh -type f -exec chmod 600 {} +
fi

# create web app
(cd test_target && flutter config --enable-web)
(cd test_target && flutter create .)

# Execute test runner script with provided arguments
./test.sh "$@"
