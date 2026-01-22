import envoy
import gleam/int
import gleam/io
import gleam/result

pub type Config {
  Config(
    app_secret: String,
    jwt_secret: String,
    jwt_expiry_minutes: Int,
    rate_limit_attempts: Int,
    rate_limit_window_seconds: Int,
    port: Int,
  )
}

pub fn load() -> Config {
  Config(
    app_secret: extract("APP_SECRET"),
    jwt_secret: extract("JWT_SECRET"),
    jwt_expiry_minutes: extract_default("JWT_EXPIRY_MINUTES", int.parse, 15),
    rate_limit_attempts: extract_default("RATE_LIMIT_ATTEMPTS", int.parse, 3),
    rate_limit_window_seconds: extract_default(
      "RATE_LIMIT_WINDOW_SECONDS",
      int.parse,
      60,
    ),
    port: extract_default("PORT", int.parse, 8080),
  )
}

fn extract(key: String) -> String {
  let assert Ok(value) = envoy.get("JWT_SECRET")
    as { "✗ Failed to get " <> key <> " from environment!" }

  value
}

fn extract_default(
  key: String,
  transform: fn(String) -> Result(a, Nil),
  default: a,
) -> a {
  envoy.get(key)
  |> result.try(transform)
  |> result.lazy_unwrap(fn() {
    io.println_error(
      "✗ Failed to get valid "
      <> key
      <> " from environment, using default value.",
    )

    default
  })
}
