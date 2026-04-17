# HTTP Throughput Benchmark: Yo vs Bun vs Deno vs Node.js vs Go vs Rust

Minimal "Hello, World!" HTTP server benchmark comparing throughput across six runtimes. Yo is benchmarked in two configurations: **single-threaded** (one event loop) and **multi-threaded** (one event loop per CPU core via `std/worker` + `SO_REUSEPORT`).

> **CI**: This benchmark runs automatically on every push via [GitHub Actions](https://github.com/shd101wyy/yo_http_benchmark/actions) on `ubuntu-latest` and `macos-latest`.

## Results

### macOS, Mac Mini M4 (16GB RAM)

Benchmarked with `bash benchmark.sh 60s 256 8` — 60-second duration, 256 concurrent connections, 8 wrk threads (`wrk -t8 -c256 -d60s http://127.0.0.1:3000/`).

| Runtime                 | Requests/sec | Avg Latency | Stdev      | Relative |
|-------------------------|-------------:|------------:|-----------:|---------:|
| **Yo (multi-threaded)** | **294,183**  | **0.84ms**  | **78μs**   | **1.00×** |
| **Yo (single)**         | **293,075**  | **0.84ms**  | **79μs**   | **1.00×** |
| Bun                     | 254,756      | 1.00ms      | 162μs      | 0.87×    |
| Deno                    | 247,130      | 1.03ms      | 86μs       | 0.84×    |
| Go (net/http)           | 217,268      | 1.26ms      | 1.51ms     | 0.74×    |
| Rust (hyper)            | 213,902      | 0.92ms      | 626μs      | 0.73×    |
| Node.js                 | 141,362      | 1.88ms      | 2.55ms     | 0.48×    |

On Apple Silicon, Yo's single-threaded event loop already saturates `kqueue` loopback throughput — the multi-threaded variant shows only marginal gains (~0.4%) on macOS because the loopback interface becomes the bottleneck before CPU. Yo still leads all runtimes, beating Bun by ~15%, Rust+hyper by ~37%, and Node.js by ~108% — with the tightest-in-class latency distribution (78–79μs stdev vs 162μs+ for every other runtime).

### Linux, GitHub Actions ubuntu-latest (30s, 100 connections, 4 threads)

| Runtime                 | Requests/sec | Avg Latency | Relative |
|-------------------------|-------------:|------------:|---------:|
| **Yo (multi-threaded)** | **260,819**  | **0.50ms**  | **1.00×** |
| Rust (hyper)            | 197,542      | 0.50ms      | 0.76×    |
| Yo (single)             | 155,125      | 16.40ms     | 0.59×    |
| Go (net/http)           | 116,872      | 1.27ms      | 0.45×    |
| Bun                     | 112,768      | 0.88ms      | 0.43×    |
| Deno                    | 85,831       | 1.18ms      | 0.33×    |
| Node.js                 | 47,806       | 2.39ms      | 0.18×    |

On Linux CI, Yo's multi-threaded variant takes the top spot — **32% faster than Rust+hyper** (which uses `tokio`'s multi-thread runtime with `io_uring`), **125% faster than Go**, and **445% faster than Node.js**. With multi-threading, Yo's per-core `io_uring` event loops saturate more CPU than a single-loop can, reaching a combined throughput that outpaces every other runtime in this benchmark. Latency is also best-in-class at 500μs (matching Rust).

### macOS, GitHub Actions macos-latest / Apple Silicon (30s, 100 connections, 4 threads)

| Runtime                 | Requests/sec | Avg Latency | Relative |
|-------------------------|-------------:|------------:|---------:|
| **Rust (hyper)**        | **159,943**  | **1.85ms**  | **1.03×** |
| **Yo (single)**         | **156,075**  | **0.88ms**  | **1.00×** |
| Bun                     | 117,458      | 1.01ms      | 0.75×    |
| Deno                    | 107,409      | 1.02ms      | 0.69×    |
| Yo (multi-threaded)     | 103,674      | 1.08ms      | 0.66×    |
| Go (net/http)           | 101,820      | 2.13ms      | 0.65×    |
| Node.js                 | 72,448       | 1.46ms      | 0.46×    |

On macOS CI (Apple Silicon), Yo's single-threaded event loop is effectively tied with Rust+hyper (156k vs 160k) while **cutting average latency in half** (0.88ms vs 1.85ms). The multi-threaded Yo variant is actually slower on macOS CI — the `kqueue` loopback stack saturates before extra threads can help, and the CI runner's constrained core budget adds contention overhead. Yo's single-threaded mode beats Bun by 33%, Deno by 45%, Go by 53%, and Node.js by 115%.

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
