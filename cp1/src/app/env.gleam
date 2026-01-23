import envoy
import gleam/io
import gleam/result

pub fn get(key: String) -> String {
  let assert Ok(value) = envoy.get("JWT_SECRET")
    as { "✗ Failed to get " <> key <> " from environment!" }

  value
}

pub fn get_default(
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
