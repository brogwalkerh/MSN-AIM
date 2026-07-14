#!/usr/bin/env bash
# Build and run a local Open OSCAR Server (formerly Retro AIM Server) from
# source via the Go module proxy — no docker or GitHub access required.
# Serves OSCAR on 127.0.0.1:5190 with auth disabled (accounts auto-create).
set -euo pipefail

DATA_DIR="${OSCAR_DATA_DIR:-$HOME/.msn-aim/oscar-server}"
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

if ! command -v go >/dev/null; then
  echo "error: the Go toolchain is required (https://go.dev/dl/)" >&2
  exit 1
fi

BIN="$(go env GOPATH)/bin/server"
if [ ! -x "$BIN" ]; then
  echo "Building Open OSCAR Server…"
  go install github.com/mk6i/open-oscar-server/cmd/server@latest
fi

export API_LISTENER="${API_LISTENER:-127.0.0.1:8080}"
export OSCAR_ADVERTISED_LISTENERS_PLAIN="${OSCAR_ADVERTISED_LISTENERS_PLAIN:-LOCAL://127.0.0.1:5190}"
export OSCAR_LISTENERS="${OSCAR_LISTENERS:-LOCAL://0.0.0.0:5190}"
export TOC_LISTENERS="${TOC_LISTENERS:-0.0.0.0:9898}"
export DISABLE_AUTH="${DISABLE_AUTH:-true}"
export DB_PATH="${DB_PATH:-$DATA_DIR/oscar.sqlite}"
export LOG_LEVEL="${LOG_LEVEL:-info}"

echo "Open OSCAR Server on $OSCAR_LISTENERS (auth disabled: $DISABLE_AUTH)"
exec "$BIN"
