import app/env
import app/web/auth
import app/web/user
import gleam/int
import gleam/json
import wisp

// Context
// -----------------------------------------------------------------------------

pub type Context {
  Context(
    // Collections
    users: user.UserCollection,
    // Cache
    session_cache: auth.SessionCache,
    rate_limit_cache: auth.RateLimitCache,
    recovery_token_cache: auth.RecoveryTokenCache,
    // Jwt
    jwt_secret: String,
    jwt_expiry_minutes: Int,
    // Ratelimit
    rate_limit_attempts: Int,
    rate_limit_window_seconds: Int,
  )
}

pub fn init_context(storage_path: String) {
  Context(
    users: user.init_collection(storage_path),
    session_cache: auth.init_session_cache(),
    rate_limit_cache: auth.init_rate_limit_cache(),
    recovery_token_cache: auth.init_recovery_token_cache(),
    jwt_secret: env.get("JWT_SECRET"),
    jwt_expiry_minutes: env.get_default("JWT_EXPIRY_MINUTES", int.parse, 15),
    rate_limit_attempts: env.get_default("RATE_LIMIT_ATTEMPTS", int.parse, 3),
    rate_limit_window_seconds: env.get_default(
      "RATE_LIMIT_WINDOW_SECONDS",
      int.parse,
      60,
    ),
  )
}

// Middleware
// -----------------------------------------------------------------------------

pub fn middleware(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)

  handle_request(req)
}

// Response
// -----------------------------------------------------------------------------

pub fn json_response(status: Int, data: json.Json) -> wisp.Response {
  wisp.response(status)
  |> wisp.json_body(json.to_string(data))
}

pub fn error_response(status: Int, message: String) -> wisp.Response {
  json_response(status, json.object([#("error", json.string(message))]))
}

pub fn success_response(status: Int, message: String) -> wisp.Response {
  json_response(status, json.object([#("message", json.string(message))]))
}

pub fn handle_result(
  result: Result(String, String),
  success_status: Int,
  error_status: Int,
) -> wisp.Response {
  case result {
    Ok(json) -> wisp.response(success_status) |> wisp.json_body(json)
    Error(msg) -> error_response(error_status, msg)
  }
}
