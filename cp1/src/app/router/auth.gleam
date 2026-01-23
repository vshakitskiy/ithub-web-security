import app/web
import app/web/auth
import app/web/user
import gleam/dynamic
import gleam/dynamic/decode
import gleam/http.{Post}
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import wisp.{type Request, type Response}

// Register
// -----------------------------------------------------------------------------

pub fn register(req: Request, ctx: web.Context) -> Response {
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  do_register(json, ctx)
  |> web.handle_result(201, 400)
}

fn register_decoder() -> decode.Decoder(#(String, String, String)) {
  use username <- decode.field("username", decode.string)
  use email <- decode.field("email", decode.string)
  use password <- decode.field("password", decode.string)
  decode.success(#(username, email, password))
}

fn do_register(
  json: dynamic.Dynamic,
  ctx: web.Context,
) -> Result(String, String) {
  use #(username, email, password) <- result.try(
    decode.run(json, register_decoder())
    |> result.replace_error("Invalid request body"),
  )

  use _ <- result.try(user.validate_username(username))
  use _ <- result.try(user.validate_email(email))
  use _ <- result.try(user.validate_password_strength(password))

  use _ <- result.try(case user.get_by_username(ctx.users, username) {
    Ok(_) -> Error("Username already exists")
    Error(_) -> Ok(Nil)
  })
  use _ <- result.try(case user.get_by_email(ctx.users, email) {
    Ok(_) -> Error("Email already exists")
    Error(_) -> Ok(Nil)
  })

  let new_user =
    user.User(
      id: wisp.random_string(16),
      username: username,
      email: email,
      password_hash: auth.hash_password(password),
      role: user.UserRole,
      created_at: timestamp.system_time(),
    )

  use _ <- result.try(
    user.save(ctx.users, new_user)
    |> result.replace_error("Failed to save user"),
  )

  json.object([
    #("message", json.string("User registered successfully")),
    #("user_id", json.string(new_user.id)),
  ])
  |> json.to_string
  |> Ok
}

// Login
// -----------------------------------------------------------------------------

pub fn login(req: Request, ctx: web.Context) -> Response {
  use <- wisp.require_method(req, Post)

  let ip = get_client_ip(req)
  wisp.log_info("Login attempt from IP: " <> ip)

  let rate_limit =
    auth.check_rate_limit(
      ctx.rate_limit_cache,
      ip,
      ctx.rate_limit_attempts,
      ctx.rate_limit_window_seconds,
    )
  case rate_limit {
    True -> {
      wisp.log_warning("Rate limit exceeded for IP: " <> ip)
      web.error_response(429, "Too many login attempts. Try again later.")
    }
    False -> {
      use json <- wisp.require_json(req)
      do_login(json, ctx, ip)
      |> web.handle_result(200, 401)
    }
  }
}

fn login_decoder() -> decode.Decoder(#(String, String)) {
  use username <- decode.field("username", decode.string)
  use password <- decode.field("password", decode.string)
  decode.success(#(username, password))
}

fn do_login(
  json: dynamic.Dynamic,
  ctx: web.Context,
  ip: String,
) -> Result(String, String) {
  use #(username, password) <- result.try(
    decode.run(json, login_decoder())
    |> result.replace_error("Invalid request body"),
  )

  use found_user <- result.try(
    user.get_by_username(ctx.users, username)
    |> result.map_error(fn(_) {
      wisp.log_info("Login attempt for non-existent user: " <> username)
      auth.log_failed_login(username, ip)
      auth.record_attempt(ctx.rate_limit_cache, ip)
      "Invalid credentials"
    }),
  )

  use _ <- result.try(
    case auth.verify_password(password, found_user.password_hash) {
      True -> Ok(Nil)
      False -> {
        wisp.log_info(
          "Failed password for user: " <> username <> " from IP: " <> ip,
        )
        auth.log_failed_login(username, ip)
        auth.record_attempt(ctx.rate_limit_cache, ip)
        Error("Invalid credentials")
      }
    },
  )

  auth.clear_attempts(ctx.rate_limit_cache, ip)

  let jti = wisp.random_string(16)
  let token =
    auth.generate_jwt(
      found_user.id,
      found_user.role,
      jti,
      ctx.jwt_secret,
      ctx.jwt_expiry_minutes,
    )

  let expiry =
    timestamp.add(
      timestamp.system_time(),
      duration.minutes(ctx.jwt_expiry_minutes),
    )
  let session =
    auth.Session(user_id: found_user.id, jti: jti, expires_at: expiry)
  auth.store_session(ctx.session_cache, found_user.id, session)

  json.object([
    #("token", json.string(token)),
    #("user", user.user_to_public_json(found_user)),
  ])
  |> json.to_string
  |> Ok
}

// Forgot password
// -----------------------------------------------------------------------------

pub fn forgot_password(req: Request, ctx: web.Context) -> Response {
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  do_forgot_password(json, ctx)
}

fn email_decoder() -> decode.Decoder(String) {
  use email <- decode.field("email", decode.string)
  decode.success(email)
}

fn do_forgot_password(json: dynamic.Dynamic, ctx: web.Context) -> Response {
  case decode.run(json, email_decoder()) {
    Error(_) -> web.error_response(400, "Invalid email")

    Ok(email) ->
      case user.get_by_email(ctx.users, email) {
        Error(_) -> {
          web.success_response(
            200,
            "If email exists, recovery token has been generated",
          )
        }

        Ok(found_user) -> {
          let token =
            auth.generate_recovery_token(found_user.id, ctx.jwt_expiry_minutes)
          auth.store_recovery_token(ctx.recovery_token_cache, token)

          web.json_response(
            200,
            json.object([
              #("message", json.string("Recovery token generated")),
              #("token", json.string(token.token)),
              #("expires_in_minutes", json.int(ctx.jwt_expiry_minutes)),
            ]),
          )
        }
      }
  }
}

// Reset Password
// -----------------------------------------------------------------------------

pub fn reset_password(req: Request, ctx: web.Context) -> Response {
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  do_reset_password(json, ctx)
  |> web.handle_result(200, 400)
}

fn reset_password_decoder() -> decode.Decoder(#(String, String)) {
  use token_string <- decode.field("token", decode.string)
  use new_password <- decode.field("new_password", decode.string)
  decode.success(#(token_string, new_password))
}

fn do_reset_password(
  json: dynamic.Dynamic,
  ctx: web.Context,
) -> Result(String, String) {
  use #(token_string, new_password) <- result.try(
    decode.run(json, reset_password_decoder())
    |> result.replace_error("Invalid request body"),
  )

  use _ <- result.try(user.validate_password_strength(new_password))

  use token <- result.try(
    auth.get_recovery_token(ctx.recovery_token_cache, token_string)
    |> result.replace_error("Invalid or expired token"),
  )

  use _ <- result.try(case token.used {
    True -> Error("Token already used")
    False -> Ok(Nil)
  })

  let now = timestamp.system_time()
  use _ <- result.try(case timestamp.compare(now, token.expires_at) {
    order.Lt -> Ok(Nil)
    _ -> Error("Token expired")
  })

  use found_user <- result.try(
    user.get_by_id(ctx.users, token.user_id)
    |> result.replace_error("User not found"),
  )

  let updated_user =
    user.User(..found_user, password_hash: auth.hash_password(new_password))
  use _ <- result.try(
    user.save(ctx.users, updated_user)
    |> result.replace_error("Failed to update password"),
  )

  auth.mark_recovery_token_used(ctx.recovery_token_cache, token_string)
  auth.invalidate_session(ctx.session_cache, token.user_id)

  Ok("{\"message\":\"Password reset successfully\"}")
}

// Logout
// -----------------------------------------------------------------------------

pub fn logout(req: Request, ctx: web.Context) -> Response {
  use req, user <- auth.require_auth(
    req,
    ctx.users,
    ctx.session_cache,
    ctx.jwt_secret,
    ctx.jwt_expiry_minutes,
  )
  use <- wisp.require_method(req, Post)

  do_logout(user.id, ctx)
}

fn do_logout(user_id: String, ctx: web.Context) -> Response {
  auth.invalidate_session(ctx.session_cache, user_id)
  web.success_response(200, "Logged out successfully")
}

fn get_client_ip(req: Request) -> String {
  req.headers
  |> list.key_find("x-forwarded-for")
  |> result.or(list.key_find(req.headers, "x-real-ip"))
  |> result.unwrap("unknown")
}
