import nasty_page from "./csrf-attack.html";

// As I am working on my homelab, I will serve the nasty evil file via the web
// server :)
Bun.serve({
  port: 3000,
  routes: {
    "/": nasty_page,
  },
});
