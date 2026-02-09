const express = require("express");
const app = express();
app.use(express.json());

let users = [
  {
    id: 1,
    username: "admin",
    password: "secret123",
    email: "admin@test.com",
    role: "admin",
  },
  {
    id: 2,
    username: "user1",
    password: "qwerty",
    email: "user1@test.com",
    role: "user",
  },
];

app.get("/users", (req, res) => {
  const safeUsers = users.map((user) => ({
    username: user.username,
    email: user.email,
    role: user.role,
  }));
  res.json(safeUsers);
});

const checkAdmin = (req, res, next) => {
  if (req.query.token !== "admin_token") {
    return res.status(403).send("Forbidden");
  }
};

app.put("/users/:id", checkAdmin, (req, res) => {
  const allowedUpdates = ["email", "password"];
  const updates = Object.keys(req.body);

  const isValid = updates.every(allowedUpdates.includes);
  if (!isValid) return res.status(400).send("Invalid updates");

  const userId = parseInt(req.params.id);
  const user = users.find((u) => u.id === userId);

  if (!user) return res.status(404).send("User not found");

  Object.assign(user, req.body);
  res.json(user);
});

app.listen(3000, () => console.log("Server running on http://localhost:3000"));
