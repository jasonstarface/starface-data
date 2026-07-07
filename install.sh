#!/bin/bash
#
# Starface Data — one-paste setup for Claude Desktop (macOS).
#
# Users run this with a single Terminal command (no download, no Gatekeeper):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jasonstarface/starface-data/main/install.sh)"
#
# Installs everything into the user's HOME folder — no admin rights, no sudo,
# no Homebrew — then signs the user in with Google and wires up Claude Desktop.
# Read-only. Safe to re-run.
#
set -euo pipefail

PROJECT_ID="disco-stock-489818-d4"
INSTALL_DIR="$HOME/.starface-bq-mcp"
RUNTIME_DIR="$INSTALL_DIR/runtime"
GCLOUD_DIR="$HOME/google-cloud-sdk"
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
REPO_TARBALL="https://codeload.github.com/jasonstarface/starface-data/tar.gz/refs/heads/main"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
step() { printf "\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
ok()   { printf "\033[0;32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[0;33m!\033[0m %s\n" "$1"; }
die()  { printf "\033[0;31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

# Resilient download: resume partial transfers and retry, so a flaky network or
# a mid-transfer "connection reset" recovers instead of failing the whole install.
dl() { # url  outfile
  local url="$1" out="$2" i
  for i in 1 2 3 4 5 6; do
    if curl -fSL -C - --connect-timeout 30 --speed-time 30 --speed-limit 2048 -o "$out" "$url"; then
      return 0
    fi
    printf "   …retry %s/6\n" "$i" >&2
    sleep 3
  done
  return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo
bold "Starface Data — Claude Desktop setup"
echo "This connects Claude Desktop to Starface's data (read-only). Everything installs"
echo "into your home folder — no admin password needed. A browser will open once so you"
echo "can sign in with your Starface Google account."

# ---------------------------------------------------------------------------
# 0. Get the connector code — local checkout (dev) or download it (curl install)
# ---------------------------------------------------------------------------
SRC=""
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  D="$(cd "$(dirname "$SELF")" && pwd)"
  [ -f "$D/dist/server.js" ] && SRC="$D"
fi
if [ -z "$SRC" ]; then
  step "Downloading the Starface connector"
  curl -fsSL "$REPO_TARBALL" | tar xz -C "$TMP" || die "Download failed. Check your internet connection and try again."
  SRC="$TMP/starface-data-main"
  [ -f "$SRC/dist/server.js" ] || die "Download looks incomplete. Contact Jason."
  ok "Connector downloaded"
fi

# ---------------------------------------------------------------------------
# 1. Node.js — reuse if present (>=18), else install to home folder (no admin)
# ---------------------------------------------------------------------------
step "Setting up Node.js (runs the connector)"
NODE_BIN=""
if command -v node >/dev/null 2>&1 && node -e 'process.exit(parseInt(process.versions.node)>=18?0:1)' 2>/dev/null; then
  NODE_BIN="$(command -v node)"
  ok "Using existing Node ($NODE_BIN, $("$NODE_BIN" -v))"
elif [ -x "$RUNTIME_DIR/node/bin/node" ]; then
  NODE_BIN="$RUNTIME_DIR/node/bin/node"
  ok "Using installed Node ($("$NODE_BIN" -v))"
else
  case "$(uname -m)" in
    arm64) NARCH="arm64" ;;
    x86_64) NARCH="x64" ;;
    *) die "Unsupported Mac chip: $(uname -m)" ;;
  esac
  BASE="https://nodejs.org/dist/latest-v22.x"
  FILE="$(curl -fsSL "$BASE/" | grep -oE "node-v22\.[0-9]+\.[0-9]+-darwin-$NARCH\.tar\.gz" | head -1)"
  [ -n "$FILE" ] || die "Couldn't find a Node download for your Mac. Contact Jason."
  warn "Installing Node into your home folder (~15 MB)…"
  dl "$BASE/$FILE" "$TMP/node.tar.gz" || die "Node download failed (network). Try again on a stronger connection."
  rm -rf "$RUNTIME_DIR/node" && mkdir -p "$RUNTIME_DIR/node"
  tar xzf "$TMP/node.tar.gz" -C "$RUNTIME_DIR/node" --strip-components=1
  NODE_BIN="$RUNTIME_DIR/node/bin/node"
  [ -x "$NODE_BIN" ] || die "Node install failed."
  ok "Node installed ($("$NODE_BIN" -v))"
fi
NODE_DIR="$(cd "$(dirname "$NODE_BIN")" && pwd)"

# ---------------------------------------------------------------------------
# 2. Google sign-in tool (gcloud) — reuse if present, else install to home.
#    gcloud is written in Python, and macOS ships none by default, so we also
#    install a small standalone Python and point gcloud at it. No admin needed.
# ---------------------------------------------------------------------------
step "Setting up Google sign-in tool"
GCLOUD=""
if command -v gcloud >/dev/null 2>&1; then
  GCLOUD="$(command -v gcloud)"
  ok "Using existing gcloud"
else
  # 2a. Standalone Python (only if we don't already have one).
  if [ ! -x "$RUNTIME_DIR/python/bin/python3" ]; then
    case "$(uname -m)" in
      arm64) PYARCH="aarch64-apple-darwin" ;;
      x86_64) PYARCH="x86_64-apple-darwin" ;;
      *) die "Unsupported Mac chip: $(uname -m)" ;;
    esac
    PYURL="$("$NODE_BIN" "$SRC/scripts/pick-python-asset.mjs" "$PYARCH")" \
      || die "Couldn't find a Python download for your Mac. Contact Jason."
    warn "Installing a small Python into your home folder (~25 MB)…"
    dl "$PYURL" "$TMP/python.tar.gz" || die "Python download failed (network). Try again on a stronger connection."
    mkdir -p "$RUNTIME_DIR"
    tar xzf "$TMP/python.tar.gz" -C "$RUNTIME_DIR"   # -> $RUNTIME_DIR/python/bin/python3
    [ -x "$RUNTIME_DIR/python/bin/python3" ] || die "Python install failed."
  fi
  export CLOUDSDK_PYTHON="$RUNTIME_DIR/python/bin/python3"

  # 2b. gcloud SDK (only if we don't already have it). Extract-and-run — we never
  #     run its install.sh, so no system Python is ever required.
  if [ ! -x "$GCLOUD_DIR/bin/gcloud" ]; then
    warn "Installing the Google sign-in tool into your home folder (~45 MB — this can take a minute)…"
    dl "https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-sdk.tar.gz" "$TMP/gcloud.tar.gz" \
      || die "Google sign-in tool download failed (network). Try again on a stronger connection."
    rm -rf "$GCLOUD_DIR"
    tar xzf "$TMP/gcloud.tar.gz" -C "$HOME"   # -> $HOME/google-cloud-sdk
  fi
  GCLOUD="$GCLOUD_DIR/bin/gcloud"
  [ -x "$GCLOUD" ] || die "Google sign-in tool install failed. Contact Jason."
  ok "Google sign-in tool ready"
fi

# ---------------------------------------------------------------------------
# 3. Install the connector to a stable location
# ---------------------------------------------------------------------------
step "Installing the Starface connector to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
for item in dist package.json package-lock.json; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$INSTALL_DIR/"
done
[ -d "$INSTALL_DIR/dist" ] || die "Connector files missing. Contact Jason."
( cd "$INSTALL_DIR" && PATH="$NODE_DIR:$PATH" "$NODE_DIR/npm" install --omit=dev --no-audit --no-fund )
SERVER_JS="$INSTALL_DIR/dist/server.js"
[ -f "$SERVER_JS" ] || die "Connector build missing at $SERVER_JS. Contact Jason."
ok "Connector installed"

# ---------------------------------------------------------------------------
# 4. Google sign-in (ADC)
# ---------------------------------------------------------------------------
step "Signing in to Google"
if "$GCLOUD" auth application-default print-access-token >/dev/null 2>&1; then
  ok "Already signed in — skipping."
else
  echo "A browser window will open. Sign in with your Starface Google account."
  "$GCLOUD" auth application-default login
fi
"$GCLOUD" auth application-default set-quota-project "$PROJECT_ID" >/dev/null 2>&1 \
  && ok "Quota project set to $PROJECT_ID" \
  || warn "Could not set quota project (queries may still work). Ask Jason for access if you hit errors."

# ---------------------------------------------------------------------------
# 5. Wire up Claude Desktop
# ---------------------------------------------------------------------------
step "Connecting Claude Desktop"
"$NODE_BIN" "$SRC/scripts/merge-config.mjs" "$NODE_BIN" "$SERVER_JS" "$CLAUDE_CONFIG"
ok "Claude Desktop configured"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
bold "✅ All set!"
echo
echo "Last step: QUIT Claude Desktop completely (Cmd+Q) and reopen it."
echo "Then ask it something like:  \"What was DTC net revenue last week?\""
echo
echo "Questions or access errors? Contact Jason (jason@starfaceworld.com)."
echo
