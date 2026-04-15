Bun.serve({
  port: 3000,
  fetch() {
    return new Response("Hello, World!");
  },
});
console.log("Bun HTTP server listening on port 3000");
