import { createServer } from "node:http";

const server = createServer((req, res) => {
  res.writeHead(200, {
    "Content-Type": "text/plain",
    "Content-Length": "13",
  });
  res.end("Hello, World!");
});

server.listen(3000, () => {
  console.log("Node HTTP server listening on port 3000");
});
