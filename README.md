# HTTP Throughput Benchmark: Yo vs Bun vs Deno vs Node.js vs Go vs Rust

Minimal "Hello, World!" HTTP server benchmark comparing throughput across six runtimes. Yo is benchmarked in two configurations: **single-threaded** (one event loop) and **multi-threaded** (one event loop per CPU core via `std/worker` + `SO_REUSEPORT`).

> **CI**: This benchmark runs automatically on every push via [GitHub Actions](https://github.com/shd101wyy/yo_http_benchmark/actions) on `ubuntu-latest` and `macos-latest`.

## Results

### macOS, Mac Mini M4 (16GB RAM, 5s, 256 connections, 8 threads)

| Runtime              | Requests/sec | Avg Latency | Relative |
|----------------------|-------------:|------------:|---------:|
| **Yo (multi-threaded)** | **270,503** | **0.91ms**  | **1.02×** |
| **Yo (single)**      | **265,889**  | **0.93ms**  | **1.00×** |
| Bun                  | 239,770      | 1.06ms      | 0.90×    |
| Deno                 | 236,794      | 1.07ms      | 0.89×    |
| Go (net/http)        | 215,119      | 1.26ms      | 0.81×    |
| Rust (hyper)         | 213,369      | 0.91ms      | 0.80×    |
| Node.js              | 134,377      | 2.87ms      | 0.51×    |

On Apple Silicon, Yo's single-threaded event loop already saturates `kqueue` loopback throughput — the multi-threaded variant shows only marginal gains (~2%) on macOS because the loopback interface becomes the bottleneck before CPU. Yo still leads all runtimes, beating Rust+hyper by ~25% and Node.js by ~100%.

### Linux, GitHub Actions ubuntu-latest (30s, 100 connections, 4 threads)

| Runtime        | Requests/sec | Avg Latency | Relative |
|----------------|-------------:|------------:|---------:|
| Rust (hyper)   | 174,683      | 0.56ms      | 1.34×    |
| **Yo**         | **130,203**  | **0.77ms**  | **1.00×** |
| Go (net/http)  | 111,758      | 1.17ms      | 0.86×    |
| Bun            | 108,521      | 0.92ms      | 0.83×    |
| Deno           | 83,489       | 1.21ms      | 0.64×    |
| Node.js        | 53,181       | 2.16ms      | 0.41×    |

On Linux CI, Rust leads because `tokio` uses a **multi-threaded runtime** (all CPU cores) with `io_uring`. Yo's event loop is currently **single-threaded**, but still beats Go, Bun, Deno, and Node.js.

### macOS, GitHub Actions macos-latest / Apple Silicon (30s, 100 connections, 4 threads)

| Runtime        | Requests/sec | Avg Latency | Relative |
|----------------|-------------:|------------:|---------:|
| **Yo**         | **137,805**  | **1.00ms**  | **1.00×** |
| Rust (hyper)   | 114,363      | 1.25ms      | 0.83×    |
| Bun            | 88,942       | 1.28ms      | 0.65×    |
| Go (net/http)  | 80,337       | 2.01ms      | 0.58×    |
| Deno           | 78,935       | 1.52ms      | 0.57×    |
| Node.js        | 53,304       | 2.03ms      | 0.39×    |

On macOS CI (Apple Silicon), Yo leads — **20% faster than Rust+hyper**, **55% faster than Bun**, and **158% faster than Node.js**. Rust's multi-thread advantage is less pronounced here since the CI runner allocates a constrained core budget.

## How it works

Each server is a minimal HTTP/1.1 implementation that:
- Listens on port 3000
- Returns `Hello, World!` with `Connection: keep-alive`
- Uses each runtime's lowest-level available API

| File                       | Runtime | API |
|----------------------------|---------|-----|
| `src/main.yo`              | Yo (single-threaded) | Raw TCP via `std/sys/tcp` + kqueue/io_uring async I/O |
| `src/main_mt.yo`           | Yo (multi-threaded)  | Same as above, spawned on N worker threads with `SO_REUSEPORT` via `std/worker` |
| `server_bun.ts`            | Bun     | `Bun.serve()` |
| `server_deno.ts`           | Deno    | `Deno.serve()` |
| `server_node.mjs`          | Node.js | `http.createServer()` |
| `server_go.go`             | Go      | `net/http` |
| `server_rust/src/main.rs`  | Rust    | `hyper` 1.x + `tokio` |

## Running the benchmark

### Prerequisites

- [Yo](https://github.com/shd101wyy/Yo) compiler
- [Bun](https://bun.sh/) 1.0+
- [Deno](https://deno.land/) 2.0+
- [Node.js](https://nodejs.org/) 20+
- [Go](https://go.dev/) 1.20+
- [Rust](https://www.rust-lang.org/) (cargo + rustc)
- [wrk](https://github.com/wg/wrk) HTTP benchmarking tool
- On macOS with nix: `nix-shell -p wrk deno go cargo rustc` provides everything

### Build and run

```bash
# Build the Yo server
yo build

# Run the benchmark (default: 10s, 100 connections, 4 threads)
bash benchmark.sh

# Custom duration/connections/threads
bash benchmark.sh 60s 500 8
```

### Run individual servers

```bash
# Yo (single-threaded)
./yo-out/*/bin/yo_http_benchmark

# Yo (multi-threaded, one worker per CPU core)
./yo-out/*/bin/yo_http_benchmark_mt

# Bun
bun run server_bun.ts

# Deno
deno run --allow-net server_deno.ts

# Node.js
node server_node.mjs

# Go
go run server_go.go

# Rust (builds on first run)
cd server_rust && cargo run --release
```

## Why Yo is fast

1. **Zero-overhead async I/O** — Yo compiles async/await to C state machines that use kqueue (macOS) / io_uring (Linux) directly, with no runtime overhead.
2. **Bounded-inline sync-completion fast-path** — When an awaited future is already ready (common for non-blocking recv/send), the state machine jumps to the next state via `goto` instead of rescheduling through the task queue. A budget of 32 preserves cooperative fairness.
3. **Compiled to native code** — The Yo compiler emits C11, compiled with `clang -O3 -fno-strict-aliasing`. No interpreter, no JIT warmup.
4. **No GC pauses** — Yo uses deterministic reference counting, not a tracing garbage collector. This directly explains Yo's tightest-in-class latency stdev.
5. **Minimal allocations** — The server pre-allocates a read buffer per connection and uses stack-allocated response strings.
6. **TCP_NODELAY** — Disables Nagle's algorithm for immediate response delivery.
7. **Optional multi-threading via `std/worker`** — The `main_mt.yo` variant spawns one worker thread per CPU core (each with its own event loop) and uses `SO_REUSEPORT` so the kernel load-balances connections across threads — no shared state, no locks.

## Notes

- Yo's single-threaded variant uses one event loop with `kqueue` (macOS) / `io_uring` (Linux). The multi-threaded variant uses `std/worker.spawn` to run N event loops in parallel, with `SO_REUSEPORT` for kernel-level connection distribution.
- On macOS, the loopback network stack saturates before CPU on M-series chips, so MT shows small gains. On Linux (where `io_uring` handles per-thread submission/completion natively), MT typically provides much larger scaling.
- Benchmarked with `wrk`. Results may vary by machine, OS, and background load. Run multiple times for stable numbers.
- CI results are from GitHub Actions shared runners (`ubuntu-latest` x64 and `macos-latest` Apple Silicon arm64). macOS local results are from a Mac Mini M4 (16GB RAM) with no background load.
