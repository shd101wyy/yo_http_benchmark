# HTTP Throughput Benchmark: Yo vs Bun vs Deno vs Node.js vs Go vs Rust

Minimal "Hello, World!" HTTP server benchmark comparing throughput across six runtimes.

> **CI**: This benchmark runs automatically on every push via [GitHub Actions](https://github.com/shd101wyy/yo_http_benchmark/actions) on `ubuntu-latest`.

## Results

### macOS, Mac Mini M4 (16GB RAM, 60s, 500 connections, 8 threads)

| Runtime        | Requests/sec | Avg Latency | Stdev     | Relative |
|----------------|-------------:|------------:|----------:|---------:|
| **Yo**         | **289,808**  | **1.58ms**  | **125μs** | **1.00×** |
| Deno           | 245,130      | 2.02ms      | 159μs     | 0.85×    |
| Bun            | 235,314      | 2.10ms      | 156μs     | 0.81×    |
| Go (net/http)  | 220,050      | 2.19ms      | 2.52ms    | 0.76×    |
| Rust (hyper)   | 216,410      | 1.72ms      | 1.20ms    | 0.75×    |
| Node.js        | 138,315      | 3.81ms      | 6.03ms    | 0.48×    |

On Apple Silicon, Yo achieves the highest throughput — **23% faster than Bun**, **34% faster than Rust+hyper**, and **109% faster than Node.js** — while also having the tightest latency distribution (lowest stdev of any runtime in the test).

### Linux, GitHub Actions ubuntu-latest (30s, 100 connections, 4 threads)

| Runtime        | Requests/sec | Avg Latency | Relative |
|----------------|-------------:|------------:|---------:|
| Rust (hyper)   | 131,900      | 0.74ms      | 1.45×    |
| **Yo**         | **91,242**   | **1.09ms**  | **1.00×** |
| Go (net/http)  | 79,411       | 1.55ms      | 0.87×    |
| Bun            | 76,288       | 1.31ms      | 0.84×    |
| Deno           | 59,078       | 1.70ms      | 0.65×    |
| Node.js        | 28,777       | 4.15ms      | 0.32×    |

On Linux CI, Rust leads because `tokio` uses a **multi-threaded runtime** (all CPU cores) with `io_uring`. Yo's event loop is currently **single-threaded**, but still beats Go, Bun, Deno, and Node.js. The absolute numbers are lower than macOS due to GitHub's shared runner environment.

## How it works

Each server is a minimal HTTP/1.1 implementation that:
- Listens on port 3000
- Returns `Hello, World!` with `Connection: keep-alive`
- Uses each runtime's lowest-level available API

| File                       | Runtime | API |
|----------------------------|---------|-----|
| `src/main.yo`              | Yo      | Raw TCP via `std/sys/tcp` + kqueue async I/O |
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
~/Workspace/Yo/yo-cli build

# Run the benchmark (default: 10s, 100 connections, 4 threads)
bash benchmark.sh

# Custom duration/connections/threads
bash benchmark.sh 60s 500 8
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

## Notes

- Yo uses a single-threaded event loop with `kqueue` (macOS) / `io_uring` (Linux). Rust/hyper uses tokio's multi-threaded runtime (all CPU cores); on Apple Silicon this is less advantageous than on Linux CI, where Rust pulls ahead.
- Benchmarked with `wrk`. Results may vary by machine, OS, and background load. Run multiple times for stable numbers.
- CI results are from GitHub Actions `ubuntu-latest` shared runners. macOS results are from a Mac Mini M4 (16GB RAM) with no background load.
