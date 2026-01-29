const express = require("express");
const app = express();
const cookieParser = require("cookie-parser");

const csrf = require("csurf");
const csrfProtection = csrf({ cookie: true });

app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
app.set("view engine", "ejs");

let user = {
  id: 1,
  email: "user@example.com",
};

app.use(csrfProtection);
app.get("/", (req, res) => {
  res.render("profile", { email: user.email, csrfToken: req.csrfToken() });
});

app.post("/update-email", (req, res) => {
  user.email = req.body.email;
  res.redirect("/");
});

app.listen(8080, () => console.log("Listening on http://localhost:8080"));
