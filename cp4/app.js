const express = require("express");
const sqlite3 = require("sqlite3").verbose();
const app = express();

const db = new sqlite3.Database(":memory:");

db.serialize(() => {
  db.run(
    "CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, is_admin INTEGER)",
  );
  db.run(
    "INSERT INTO users (username, password, is_admin) VALUES ('admin', 'secret123', 1)",
  );
  db.run(
    "INSERT INTO users (username, password, is_admin) VALUES ('user1', 'qwerty', 0)",
  );
});

app.get("/search", (req, res) => {
  const username = req.query.username || "";

  if (!/^[a-zA-Z0-9]+$/.test(username)) {
    return res.status(400).send("Invalid query content");
  }

  db.all(`SELECT * FROM users WHERE username = ?`, [username], (err, rows) => {
    if (err) return res.status(500).send("Internal Server Error");
    res.json(rows);
  });
});

app.listen(3000, () => console.log("Listening on http://localhost:3000"));
