#!/usr/bin/env bash
set -euo pipefail

# HTTP throughput benchmark: Yo vs Bun vs Deno vs Node.js vs Go vs Rust
# Uses wrk to measure requests/sec for a "Hello, World!" HTTP server.

DURATION="${1:-10s}"
CONNECTIONS="${2:-100}"
THREADS="${3:-4}"
PORT=3000
RESULTS_FILE="benchmark_results.txt"
YO_CLI="${YO_CLI:-$( [ -x "$HOME/Workspace/Yo/yo-cli" ] && echo "$HOME/Workspace/Yo/yo-cli" || command -v yo )}"

echo "=== HTTP Throughput Benchmark ==="
echo "Duration: $DURATION | Connections: $CONNECTIONS | Threads: $THREADS"
echo ""

wait_for_server() {
  local retries="${1:-50}"
  while ! curl -s --max-time 1 "http://127.0.0.1:$PORT/" > /dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "  ERROR: Server failed to start"
      return 1
    fi
    sleep 0.2
  done
}

kill_port() {
  if command -v lsof &>/dev/null; then
    lsof -ti :"$PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
  elif command -v fuser &>/dev/null; then
    fuser -k "$PORT"/tcp 2>/dev/null || true
  fi
  sleep 0.2
}

run_wrk() {
  if command -v wrk &>/dev/null; then
    wrk -t$THREADS -c$CONNECTIONS -d$DURATION http://127.0.0.1:$PORT/
  elif command -v nix-shell &>/dev/null; then
    nix-shell -p wrk --run "wrk -t$THREADS -c$CONNECTIONS -d$DURATION http://127.0.0.1:$PORT/"
  else
    echo "ERROR: wrk not found. Install wrk or use nix-shell."
    exit 1
  fi
}

# Clean up on exit
trap 'kill_port' EXIT

> "$RESULTS_FILE"

# ── Yo ──────────────────────────────────────────────────────────────────
echo "--- Building Yo server ---"
kill_port
cd "$(dirname "$0")"
"$YO_CLI" build 2>&1 | tail -3
echo ""

# Detect binary path (use glob to handle any target triple)
YO_BIN=$(ls ./yo-out/*/bin/yo_http_benchmark 2>/dev/null | head -1)
if [ -z "$YO_BIN" ]; then
  echo "ERROR: Yo binary not found in yo-out/*/bin/"
  exit 1
fi

echo "--- Benchmarking: Yo ---"
"$YO_BIN" &
SERVER_PID=$!
wait_for_server
echo "  Server ready (PID $SERVER_PID)"
echo ""
echo "=== Yo ===" >> "$RESULTS_FILE"
run_wrk | tee -a "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
kill $SERVER_PID 2>/dev/null || true
kill_port
sleep 0.5
echo ""

# ── Bun ─────────────────────────────────────────────────────────────────
echo "--- Benchmarking: Bun ---"
kill_port
bun run server_bun.ts &
SERVER_PID=$!
wait_for_server
echo "  Server ready (PID $SERVER_PID)"
echo ""
echo "=== Bun ===" >> "$RESULTS_FILE"
run_wrk | tee -a "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
kill $SERVER_PID 2>/dev/null || true
kill_port
sleep 0.5
echo ""

# ── Deno ────────────────────────────────────────────────────────────────
echo "--- Benchmarking: Deno ---"
kill_port
if command -v deno &>/dev/null; then
  deno run --allow-net server_deno.ts &
  SERVER_PID=$!
elif command -v nix-shell &>/dev/null; then
  nix-shell -p deno --run "deno run --allow-net server_deno.ts" &
  SERVER_PID=$!
else
  SERVER_PID=""
fi
if [ -n "$SERVER_PID" ]; then
  wait_for_server
  echo "  Server ready (PID $SERVER_PID)"
  echo ""
  echo "=== Deno ===" >> "$RESULTS_FILE"
  run_wrk | tee -a "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
  kill $SERVER_PID 2>/dev/null || true
  kill_port
  sleep 0.5
else
  echo "  SKIP: deno not found"
  echo "=== Deno ===" >> "$RESULTS_FILE"
  echo "SKIPPED: deno not available" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
fi
echo ""

# ── Node.js ─────────────────────────────────────────────────────────────
echo "--- Benchmarking: Node.js ---"
kill_port
node server_node.mjs &
SERVER_PID=$!
wait_for_server
echo "  Server ready (PID $SERVER_PID)"
echo ""
echo "=== Node.js ===" >> "$RESULTS_FILE"
run_wrk | tee -a "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"
kill $SERVER_PID 2>/dev/null || true
kill_port
sleep 0.5
echo ""

# ── Go ───────────────────────────────────────────────────────────────────
echo "--- Benchmarking: Go ---"
kill_port
if command -v go &>/dev/null; then
  GO_CMD="go"
elif command -v nix-shell &>/dev/null; then
  GO_CMD="nix-shell -p go --run go"
else
  GO_CMD=""
fi
if [ -n "$GO_CMD" ]; then
  if command -v go &>/dev/null; then
    go run server_go.go &
  else
    nix-shell -p go --run "go run server_go.go" &
  fi
  SERVER_PID=$!
  wait_for_server 200
  echo "  Server ready (PID $SERVER_PID)"
  echo ""
  echo "=== Go ===" >> "$RESULTS_FILE"
  run_wrk | tee -a "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
  kill $SERVER_PID 2>/dev/null || true
  kill_port
  sleep 0.5
else
  echo "  SKIP: go not found"
  echo "=== Go ===" >> "$RESULTS_FILE"
  echo "SKIPPED: go not available" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
fi
echo ""

# ── Rust ────────────────────────────────────────────────────────────────
echo "--- Benchmarking: Rust ---"
kill_port
RUST_BIN="./server_rust/target/release/server_rust"
if [ ! -x "$RUST_BIN" ]; then
  echo "  Building Rust server (release)..."
  if command -v cargo &>/dev/null; then
    (cd server_rust && cargo build --release 2>&1 | tail -3)
  elif command -v nix-shell &>/dev/null; then
    nix-shell -p cargo rustc --run "cd server_rust && cargo build --release" 2>&1 | tail -3
  fi
fi
if [ -x "$RUST_BIN" ]; then
  "$RUST_BIN" &
  SERVER_PID=$!
  wait_for_server
  echo "  Server ready (PID $SERVER_PID)"
  echo ""
  echo "=== Rust (hyper) ===" >> "$RESULTS_FILE"
  run_wrk | tee -a "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
  kill $SERVER_PID 2>/dev/null || true
  kill_port
  sleep 0.5
else
  echo "  SKIP: rust toolchain not found"
  echo "=== Rust (hyper) ===" >> "$RESULTS_FILE"
  echo "SKIPPED: cargo not available" >> "$RESULTS_FILE"
  echo "" >> "$RESULTS_FILE"
fi
echo ""

# ── Summary ─────────────────────────────────────────────────────────────
echo "=========================================="
echo "          BENCHMARK SUMMARY"
echo "=========================================="
echo ""
cat "$RESULTS_FILE"
echo ""
echo "Full results saved to $RESULTS_FILE"
