#!/usr/bin/env bash
set -euo pipefail

# HTTP throughput benchmark: Yo vs Bun vs Deno vs Node.js
# Uses wrk to measure requests/sec for a "Hello, World!" HTTP server.

DURATION="${1:-10s}"
CONNECTIONS="${2:-100}"
THREADS="${3:-4}"
PORT=3000
RESULTS_FILE="benchmark_results.txt"
YO_CLI="${YO_CLI:-$(command -v yo 2>/dev/null || echo "$HOME/Workspace/Yo/yo-cli")}"

echo "=== HTTP Throughput Benchmark ==="
echo "Duration: $DURATION | Connections: $CONNECTIONS | Threads: $THREADS"
echo ""

wait_for_server() {
  local retries=30
  while ! curl -s "http://127.0.0.1:$PORT/" > /dev/null 2>&1; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "  ERROR: Server failed to start"
      return 1
    fi
    sleep 0.1
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

# Detect platform for binary path
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) YO_BIN="./yo-out/aarch64-macos/bin/yo_http_benchmark" ;;
  Darwin-x86_64) YO_BIN="./yo-out/x86_64-macos/bin/yo_http_benchmark" ;;
  Linux-x86_64) YO_BIN="./yo-out/x86_64-linux/bin/yo_http_benchmark" ;;
  Linux-aarch64) YO_BIN="./yo-out/aarch64-linux/bin/yo_http_benchmark" ;;
  *) echo "Unsupported platform: $(uname -s)-$(uname -m)"; exit 1 ;;
esac

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

# ── Summary ─────────────────────────────────────────────────────────────
echo "=========================================="
echo "          BENCHMARK SUMMARY"
echo "=========================================="
echo ""
cat "$RESULTS_FILE"
echo ""
echo "Full results saved to $RESULTS_FILE"
