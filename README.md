# HTTP Throughput Benchmark: Yo vs Bun vs Deno vs Node.js vs Go vs Rust

Minimal "Hello, World!" HTTP server benchmark comparing throughput across six runtimes.

## Results (macOS, Apple Silicon, 60s, 500 connections, 8 threads)

| Runtime        | Requests/sec | Avg Latency | Stdev | Relative |
|----------------|-------------:|------------:|------:|---------:|
| **Yo**         | **270,800**  | **1.81ms**  | **240μs** | **1.00×** |
| Bun            | 243,431      | 2.03ms      | 322μs | 0.90×    |
| Deno           | 235,133      | 2.10ms      | 331μs | 0.87×    |
| Go (net/http)  | 219,337      | 2.35ms      | 2.87ms| 0.81×    |
| Rust (hyper)   | 217,469      | 1.83ms      | 1.77ms| 0.80×    |
| Node.js        | 127,546      | 4.17ms      | 7.26ms| 0.47×    |

Yo achieves the highest throughput — **11% faster than Bun**, **24% faster than Rust+hyper**, and **112% faster than Node.js** — while also having the tightest latency distribution (lowest stdev of any runtime in the test).

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

- Benchmark uses a single-process, single-threaded event loop for each runtime. Rust/hyper uses tokio multi-thread runtime which spreads across CPU cores; despite this, Yo's single-threaded implementation wins on both throughput and tail latency.
- Benchmarked with `wrk`. Results may vary by machine, OS, and background load. Run multiple times for stable numbers.
