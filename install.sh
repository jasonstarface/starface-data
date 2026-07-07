#!/bin/bash
#
# Starface Data — one-paste setup for Claude Desktop (macOS).
#
# Users run this with a single Terminal command (no download, no Gatekeeper):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jasonstarface/starface-data/main/install.sh)"
#
# It installs everything needed (Homebrew, Node, gcloud), signs the user in with
# Google, and wires up Claude Desktop — all read-only. Safe to re-run.
#
set -euo pipefail

PROJECT_ID="disco-stock-489818-d4"
INSTALL_DIR="$HOME/.starface-bq-mcp"
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
REPO_TARBALL="https://codeload.github.com/jasonstarface/starface-data/tar.gz/refs/heads/main"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
step() { printf "\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$1"; }
ok()   { printf "\033[0;32m✓\033[0m %s\n" "$1"; }
warn() { printf "\033[0;33m!\033[0m %s\n" "$1"; }
die()  { printf "\033[0;31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

echo
bold "Starface Data — Claude Desktop setup"
echo "This connects Claude Desktop to Starface's data (read-only). It may ask for your"
echo "Mac password (to install software) and will open a browser to sign in with Google."

# ---------------------------------------------------------------------------
# 0. Get the connector code — from the local checkout (dev) or download it (curl install)
# ---------------------------------------------------------------------------
SRC=""
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  D="$(cd "$(dirname "$SELF")" && pwd)"
  [ -f "$D/dist/server.js" ] && SRC="$D"
fi
if [ -z "$SRC" ]; then
  step "Downloading the Starface connector"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$REPO_TARBALL" | tar xz -C "$TMP" || die "Download failed. Check your internet connection and try again."
  SRC="$TMP/starface-data-main"
  [ -f "$SRC/dist/server.js" ] || die "Download looks incomplete. Contact Jason."
  ok "Connector downloaded"
fi

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
step "Checking Homebrew (package installer)"
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)";
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
fi
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found — installing it (this can take a few minutes)."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)";
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
fi
command -v brew >/dev/null 2>&1 || die "Homebrew install failed. Contact Jason."
ok "Homebrew ready"

# ---------------------------------------------------------------------------
# 2. Node.js
# ---------------------------------------------------------------------------
step "Checking Node.js (runs the connector)"
if ! command -v node >/dev/null 2>&1; then
  warn "Node not found — installing."
  brew install node
fi
NODE_BIN="$(command -v node)"
command -v npm >/dev/null 2>&1 || die "npm not found after installing Node. Contact Jason."
ok "Node ready ($NODE_BIN, $(node -v))"

# ---------------------------------------------------------------------------
# 3. Google Cloud SDK (gcloud) — for signing in
# ---------------------------------------------------------------------------
step "Checking Google Cloud SDK (for sign-in)"
if ! command -v gcloud >/dev/null 2>&1; then
  if [ -f "/opt/homebrew/share/google-cloud-sdk/path.bash.inc" ]; then
    source "/opt/homebrew/share/google-cloud-sdk/path.bash.inc"
  fi
fi
if ! command -v gcloud >/dev/null 2>&1; then
  warn "gcloud not found — installing (this can take a few minutes)."
  brew install --cask google-cloud-sdk
  if [ -f "/opt/homebrew/share/google-cloud-sdk/path.bash.inc" ]; then
    source "/opt/homebrew/share/google-cloud-sdk/path.bash.inc"
  fi
fi
command -v gcloud >/dev/null 2>&1 || die "gcloud install failed. Contact Jason."
ok "Google Cloud SDK ready"

# ---------------------------------------------------------------------------
# 4. Install the connector to a stable location
# ---------------------------------------------------------------------------
step "Installing the Starface connector to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
for item in dist package.json package-lock.json; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$INSTALL_DIR/"
done
[ -d "$INSTALL_DIR/dist" ] || die "Connector files missing. Contact Jason."
( cd "$INSTALL_DIR" && npm install --omit=dev --no-audit --no-fund )
SERVER_JS="$INSTALL_DIR/dist/server.js"
[ -f "$SERVER_JS" ] || die "Connector build missing at $SERVER_JS. Contact Jason."
ok "Connector installed"

# ---------------------------------------------------------------------------
# 5. Google sign-in (ADC)
# ---------------------------------------------------------------------------
step "Signing in to Google"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  ok "Already signed in — skipping."
else
  echo "A browser window will open. Sign in with your Starface Google account."
  gcloud auth application-default login
fi
gcloud auth application-default set-quota-project "$PROJECT_ID" >/dev/null 2>&1 \
  && ok "Quota project set to $PROJECT_ID" \
  || warn "Could not set quota project (queries may still work). Ask Jason for access if you hit errors."

# ---------------------------------------------------------------------------
# 6. Wire up Claude Desktop
# ---------------------------------------------------------------------------
step "Connecting Claude Desktop"
node "$SRC/scripts/merge-config.mjs" "$NODE_BIN" "$SERVER_JS" "$CLAUDE_CONFIG"
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
