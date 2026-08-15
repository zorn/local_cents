#!/usr/bin/env bash
#
# One-command launcher for the offline-collaboration conflict demo (issue #235,
# ADR 0025). It automates the manual recipe in docs/two-peer-sync.md so the demo
# is a one-liner rather than a fragile sequence of hand-run steps.
#
# What it does, in order:
#   1. Seeds a fresh demo Book into peer A's throwaway books directory.
#   2. Forks that Book's bytes into peer B's directory, so the two peers start
#      from a genuine common Automerge ancestor (identical bytes and history),
#      so the operator never hand-copies a document between instances.
#   3. Boots peer B (the host): a plain Phoenix server on its own port, no Tauri
#      shell. The browser is peer B's always-online client.
#   4. Opens the browser to peer B.
#   5. Boots peer A (the dialer): the Tauri Mac app, which dials peer B's sync
#      Channel so the native Developer > offline toggle can force divergence.
#   6. Tears both instances down on exit, so repeated runs start clean.
#
# Both peers keep their own local .lcbook in their own throwaway directory, so
# the demo never touches your real ~/Library books (ADR 0007 stays deferred).
#
# Usage: scripts/two-peer-demo.sh
#   Quit the Mac app (or press Ctrl-C) to tear the whole demo down.

set -euo pipefail

# --- Configuration (override via the environment if a port is already taken) ---

PEER_B_PORT="${PEER_B_PORT:-4001}"          # peer A (Tauri) always takes the dev default, 4000
DEMO_ROOT="${DEMO_ROOT:-${TMPDIR:-/tmp}/localcents-two-peer-demo}"
PEER_A_DIR="$DEMO_ROOT/peer-a"
PEER_B_DIR="$DEMO_ROOT/peer-b"
SYNC_URL="ws://127.0.0.1:${PEER_B_PORT}/peer/websocket"

# Run from the repo root so `mix` and `cargo tauri` resolve, wherever this was called from.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PEER_B_PID=""

# --- Teardown --------------------------------------------------------------

# Reaps both peers and removes the throwaway directories. Runs on any exit — a
# clean quit, a Ctrl-C, or an error — so a repeated run always starts from
# nothing. Each `lsof` reap catches the BEAM that `mix`/`cargo tauri` spawns,
# which a bare `kill` on the wrapper can orphan. `-sTCP:LISTEN` keeps it to the
# server that owns the port, never a client connected to it (the browser, or peer
# A's link). Reaping port 4000 is safe because the trap is armed only after the
# preflight confirms both ports are free, so any listener we reap is one we booted.
cleanup() {
  trap - EXIT INT TERM
  echo
  echo "==> Tearing down the demo…"

  [ -n "$PEER_B_PID" ] && kill "$PEER_B_PID" 2>/dev/null || true
  lsof -ti "tcp:${PEER_B_PORT}" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
  lsof -ti "tcp:4000" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true

  rm -rf "$DEMO_ROOT"
  echo "==> Done."
}

# --- Preflight -------------------------------------------------------------

for tool in cargo mix open lsof curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' is not on PATH" >&2; exit 1; }
done

if lsof -ti "tcp:${PEER_B_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "error: port ${PEER_B_PORT} is already in use — stop that process or set PEER_B_PORT" >&2
  exit 1
fi

# Peer A is the Tauri app, which always binds the dev default 4000 (it is not
# configurable). Fail early rather than let the Mac app's BEAM crash on a taken port.
if lsof -ti "tcp:4000" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "error: port 4000 is already in use — stop your other dev server first (peer A needs it)" >&2
  exit 1
fi

# Arm teardown only now that preflight has passed. Armed earlier, a preflight
# failure would exit through cleanup and reap the foreign listener it was refusing
# to start against — killing the user's own server rather than protecting it.
trap cleanup EXIT INT TERM

# A stale directory from a crashed prior run would let peer A open the old Book;
# start from nothing so the seed below is the only ancestor.
rm -rf "$DEMO_ROOT"
mkdir -p "$PEER_A_DIR" "$PEER_B_DIR"

# --- 1. Seed a fresh demo Book into peer A ---------------------------------

echo "==> Seeding a demo Book into peer A…"

# `mix run` starts the app (so the tracking runtime is up) but not the HTTP
# listener, so this never collides with the servers booted below. The Book is
# created through the ordinary public API and closed so its bytes are flushed to
# disk before the fork. It prints its id on a marked line we parse back out.
SEED_OUTPUT="$(
  LOCAL_CENTS_BOOKS_DIR="$PEER_A_DIR" mix run -e '
    alias LocalCents.Tracking
    {:ok, book} = Tracking.create_book("Sync Demo")
    {:ok, _} = Tracking.add_expense(book.id, %{description: "Coffee", cost: "4.50"})
    {:ok, _} = Tracking.add_expense(book.id, %{description: "Lunch", cost: "12.00"})
    :ok = Tracking.close_book(book.id)
    IO.puts("LC_BOOK_ID=" <> book.id)
  '
)"

BOOK_ID="$(printf '%s\n' "$SEED_OUTPUT" | sed -n 's/^LC_BOOK_ID=//p')"
if [ -z "$BOOK_ID" ]; then
  echo "error: seeding did not report a Book id" >&2
  printf '%s\n' "$SEED_OUTPUT" >&2
  exit 1
fi

# --- 2. Fork the Book into peer B (the common ancestor) --------------------

# Both peers keep the same Book id — the rendezvous topic the two BEAMs agree on
# (see LOCAL_CENTS_SYNC_BOOK_ID below), and the shared bytes make them one
# document rather than concurrent siblings, so the sync link keeps them converged.
echo "==> Forking the Book into peer B…"
cp "$PEER_A_DIR/${BOOK_ID}.lcbook" "$PEER_B_DIR/${BOOK_ID}.lcbook"

# --- 3. Boot peer B (the host) ---------------------------------------------

echo "==> Booting peer B (host) on port ${PEER_B_PORT}…"
LOCAL_CENTS_BOOKS_DIR="$PEER_B_DIR" PORT="$PEER_B_PORT" mix phx.server &
PEER_B_PID=$!

# Wait until peer B answers before dialing it, so peer A's client connects on its
# first try rather than backing off. Give it generous time for a cold compile.
ready=false
echo -n "==> Waiting for peer B to come up"
for _ in {1..60}; do
  if curl -sf -o /dev/null "http://127.0.0.1:${PEER_B_PORT}/"; then
    echo " — ready."
    ready=true
    break
  fi
  if ! kill -0 "$PEER_B_PID" 2>/dev/null; then
    echo
    echo "error: peer B exited before it came up" >&2
    exit 1
  fi
  echo -n "."
  sleep 1
done

# Do not let a timeout pass silently. Peer A's client tolerates an unreachable
# peer and reconnects, so the demo can still recover — but say so rather than
# boot on as if peer B were up.
if [ "$ready" = false ]; then
  echo
  echo "warning: peer B did not answer on port ${PEER_B_PORT} within 60s — it may still be" >&2
  echo "         compiling. Peer A will keep retrying the link; if the browser cannot reach" >&2
  echo "         peer B, quit and re-run (a warm build comes up fast)." >&2
fi

# --- 4. Open the browser to peer B -----------------------------------------

echo "==> Opening the browser to peer B…"
open "http://localhost:${PEER_B_PORT}/"

# --- 5. Boot peer A (the dialer) in the foreground -------------------------

# `cargo tauri dev` runs `mix phx.server` for peer A's BEAM and inherits this
# shell's environment, so the sync vars below reach it: it dials peer B's socket
# and reconciles the shared Book. This runs in the foreground and owns the demo —
# quitting the Mac app (or Ctrl-C) returns here and fires the teardown trap.
echo "==> Booting peer A (Tauri Mac app)…"
echo "    Open the 'Sync Demo' Book in both windows, then use the Mac app's"
echo "    Developer menu to toggle offline and force a divergence."
echo

LOCAL_CENTS_BOOKS_DIR="$PEER_A_DIR" \
  LOCAL_CENTS_SYNC_URL="$SYNC_URL" \
  LOCAL_CENTS_SYNC_BOOK_ID="$BOOK_ID" \
  cargo tauri dev
