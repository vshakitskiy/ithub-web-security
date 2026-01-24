const express = require("express");
const DOMPurify = require("isomorphic-dompurify");
const helmet = require("helmet");
const app = express();

app.use(express.urlencoded({ extended: true }));
app.set("view engine", "ejs");
app.use(
  helmet.contentSecurityPolicy({
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      formAction: ["'self'"],
      upgradeInsecureRequests: null,
    },
  }),
);

const comments = [];

app.get("/", (req, res) => {
  res.render("index", { comments });
});

app.post("/comment", (req, res) => {
  const cleanText = DOMPurify.sanitize(req.body.text);
  comments.push(cleanText);
  res.redirect("/");
});

app.listen(3000, () => console.log("Listening on http://localhost:3000"));
