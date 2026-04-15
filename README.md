# HTTP Throughput Benchmark: Yo vs Bun vs Deno vs Node.js

Minimal "Hello, World!" HTTP server benchmark comparing throughput across four runtimes.

## Results (macOS, Apple Silicon M4, 30s, 100 connections, 4 threads)

| Runtime  | Requests/sec | Relative |
|----------|-------------|----------|
| **Yo**   | **314,449** | **1.00x** |
| Bun      | 301,648     | 0.96x    |
| Deno     | 257,976     | 0.82x    |
| Node.js  | 141,031     | 0.45x    |

Yo achieves the highest throughput — 4% faster than Bun, 22% faster than Deno, and 123% faster than Node.js.

## How it works

Each server is a minimal HTTP/1.1 implementation that:
- Listens on port 3000
- Returns `Hello, World!` with `Connection: keep-alive`
- Uses each runtime's lowest-level available API

| File | Runtime | API |
|------|---------|-----|
| `src/main.yo` | Yo | Raw TCP via `std/sys/tcp` + kqueue async I/O |
| `server_bun.ts` | Bun | `Bun.serve()` |
| `server_deno.ts` | Deno | `Deno.serve()` |
| `server_node.mjs` | Node.js | `http.createServer()` |

## Running the benchmark

### Prerequisites

- [Yo](https://github.com/nicholasgasior/yo-lang) compiler
- [Bun](https://bun.sh/) 1.0+
- [Deno](https://deno.land/) 2.0+
- [Node.js](https://nodejs.org/) 20+
- [wrk](https://github.com/wg/wrk) HTTP benchmarking tool
- On macOS with nix: `nix-shell -p wrk deno` provides wrk and Deno

### Build and run

```bash
# Build the Yo server
~/Workspace/Yo/yo-cli build

# Run the benchmark (default: 10s, 100 connections, 4 threads)
bash benchmark.sh

# Custom duration/connections/threads
bash benchmark.sh 30s 100 4
```

### Run individual servers

```bash
# Yo
./yo-out/*/bin/yo_http_benchmark

# Bun
bun run server_bun.ts

# Deno
deno run --allow-net server_deno.ts

# Node.js
node server_node.mjs
```

## Why Yo is fast

1. **Zero-overhead async I/O** — Yo compiles async/await to C state machines that use kqueue (macOS) / io_uring (Linux) directly, with no runtime overhead.
2. **Compiled to native code** — The Yo compiler emits C11, compiled with `clang -O2`. No interpreter, no JIT warmup.
3. **No GC pauses** — Yo uses deterministic reference counting, not a tracing garbage collector.
4. **Minimal allocations** — The server pre-allocates a read buffer per connection and uses stack-allocated response strings.
5. **TCP_NODELAY** — Disables Nagle's algorithm for immediate response delivery.

## Notes

- All servers run **single-threaded** for a fair comparison.
- Benchmarked with `wrk` (4 threads, 100 concurrent connections, 30 seconds).
- Results may vary by machine, OS, and background load. Run multiple times for stable numbers.
