import app/web/user
import argus
import booklet.{type Booklet}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import simplifile
import wisp.{type Request, type Response}
import ywt
import ywt/claim
import ywt/sign_key
import ywt/verify_key

// Session
// -----------------------------------------------------------------------------

pub type Session {
  Session(user_id: String, jti: String, expires_at: timestamp.Timestamp)
}

pub opaque type SessionCache {
  SessionCache(cache: Booklet(Dict(String, Session)))
}

pub fn init_session_cache() -> SessionCache {
  SessionCache(booklet.new(dict.new()))
}

pub fn store_session(cache: SessionCache, user_id: String, session: Session) {
  booklet.update(cache.cache, dict.insert(_, user_id, session))
  Nil
}

pub fn get_session(cache: SessionCache, user_id: String) -> Result(Session, Nil) {
  booklet.get(cache.cache)
  |> dict.get(user_id)
}

pub fn invalidate_session(cache: SessionCache, user_id: String) {
  booklet.update(cache.cache, dict.delete(_, user_id))
  Nil
}

// Recovery
// -----------------------------------------------------------------------------

pub opaque type RecoveryTokenCache {
  RecoveryTokenCache(cache: Booklet(Dict(String, RecoveryToken)))
}

pub type RecoveryToken {
  RecoveryToken(
    user_id: String,
    token: String,
    created_at: timestamp.Timestamp,
    expires_at: timestamp.Timestamp,
    used: Bool,
  )
}

pub fn init_recovery_token_cache() -> RecoveryTokenCache {
  RecoveryTokenCache(booklet.new(dict.new()))
}

pub fn store_recovery_token(cache: RecoveryTokenCache, token: RecoveryToken) {
  booklet.update(cache.cache, dict.insert(_, token.token, token))
  Nil
}

pub fn get_recovery_token(
  cache: RecoveryTokenCache,
  token_string: String,
) -> Result(RecoveryToken, Nil) {
  booklet.get(cache.cache)
  |> dict.get(token_string)
}

pub fn mark_recovery_token_used(cache: RecoveryTokenCache, token_string: String) {
  booklet.update(cache.cache, fn(tokens) {
    case dict.get(tokens, token_string) {
      Ok(token) ->
        dict.insert(tokens, token_string, RecoveryToken(..token, used: True))
      Error(_) -> tokens
    }
  })
  Nil
}

pub fn generate_recovery_token(
  user_id: String,
  expiry_minutes: Int,
) -> RecoveryToken {
  let now = timestamp.system_time()
  RecoveryToken(
    user_id: user_id,
    token: wisp.random_string(32),
    created_at: now,
    expires_at: timestamp.add(now, duration.minutes(expiry_minutes)),
    used: False,
  )
}

// Rate Limit
// -----------------------------------------------------------------------------

pub opaque type RateLimitCache {
  RateLimitCache(cache: Booklet(Dict(String, RateLimit)))
}

pub type RateLimit {
  RateLimitState(count: Int, window_start: timestamp.Timestamp)
}

pub fn init_rate_limit_cache() -> RateLimitCache {
  RateLimitCache(booklet.new(dict.new()))
}

pub fn check_rate_limit(
  cache: RateLimitCache,
  ip: String,
  max_attempts: Int,
  window_seconds: Int,
) -> Bool {
  let attempts = booklet.get(cache.cache)
  let now = timestamp.system_time()

  case dict.get(attempts, ip) {
    Ok(state) -> {
      let elapsed = timestamp.difference(state.window_start, now)
      let window = duration.seconds(window_seconds)

      case duration.compare(elapsed, window) {
        order.Lt -> {
          wisp.log_info(
            "Rate limit check for "
            <> ip
            <> ": "
            <> int.to_string(state.count)
            <> "/"
            <> int.to_string(max_attempts),
          )
          state.count >= max_attempts
        }
        _ -> False
      }
    }
    Error(_) -> False
  }
}

pub fn record_attempt(cache: RateLimitCache, ip: String) {
  let now = timestamp.system_time()

  booklet.update(cache.cache, fn(attempts) {
    case dict.get(attempts, ip) {
      Ok(state) -> {
        let elapsed = timestamp.difference(state.window_start, now)
        let window = duration.seconds(60)

        case duration.compare(elapsed, window) {
          order.Lt -> {
            let new_count = state.count + 1
            wisp.log_info(
              "Recording attempt for "
              <> ip
              <> ": count now "
              <> int.to_string(new_count),
            )
            dict.insert(
              attempts,
              ip,
              RateLimitState(count: new_count, window_start: state.window_start),
            )
          }
          _ -> {
            wisp.log_info(
              "Rate limit window expired for " <> ip <> ", resetting",
            )
            dict.insert(
              attempts,
              ip,
              RateLimitState(count: 1, window_start: now),
            )
          }
        }
      }
      Error(_) -> {
        wisp.log_info("First attempt for " <> ip)
        dict.insert(attempts, ip, RateLimitState(count: 1, window_start: now))
      }
    }
  })
  Nil
}

pub fn clear_attempts(cache: RateLimitCache, ip: String) {
  booklet.update(cache.cache, dict.delete(_, ip))
  wisp.log_info("Cleared rate limit for " <> ip)
  Nil
}

// JWT
// -----------------------------------------------------------------------------

pub fn generate_jwt(
  user_id: String,
  role: user.Role,
  jti: String,
  jwt_secret: String,
  expiry_minutes: Int,
) -> String {
  let payload = [
    #("sub", json.string(user_id)),
    #("role", json.string(user.role_to_string(role))),
  ]

  let claims = [
    claim.expires_at(
      max_age: duration.minutes(expiry_minutes),
      leeway: duration.minutes(1),
    ),
    claim.id(jti, []),
  ]

  let assert Ok(key) = sign_key.hs256(<<jwt_secret:utf8>>)

  ywt.encode(payload: payload, claims: claims, key: key)
}

pub fn verify_jwt(
  token: String,
  jwt_secret: String,
  expiry_minutes: Int,
) -> Result(#(String, String), Nil) {
  let decoder = {
    use sub <- decode.field("sub", decode.string)
    decode.success(sub)
  }

  let claims = [
    claim.expires_at(
      max_age: duration.minutes(expiry_minutes),
      leeway: duration.minutes(1),
    ),
  ]

  let assert Ok(sign_key) = sign_key.hs256(<<jwt_secret:utf8>>)
  let verify_key = verify_key.derived(sign_key)

  use sub <- result.try(
    ywt.decode(token, using: decoder, claims: claims, keys: [verify_key])
    |> result.replace_error(Nil),
  )

  use jti <- result.try(extract_jti(token))

  Ok(#(sub, jti))
}

fn extract_jti(token: String) -> Result(String, Nil) {
  let decoder = {
    use jti <- decode.field("jti", decode.string)
    decode.success(jti)
  }

  ywt.decode_unsafely_without_validation(token, decoder)
}

// Password
// -----------------------------------------------------------------------------

pub fn hash_password(password: String) -> String {
  let salt = argus.gen_salt()
  let hasher = argus.hasher()
  let assert Ok(hashes) = argus.hash(hasher, password, salt)
  hashes.encoded_hash
}

pub fn verify_password(password: String, hash: String) -> Bool {
  argus.verify(hash, password)
  |> result.unwrap(False)
}

// Logging
// -----------------------------------------------------------------------------

pub fn log_failed_login(username: String, ip: String) {
  let now = timestamp.system_time()
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(now)

  let log_entry =
    json.to_string(
      json.object([
        #("event", json.string("login_failed")),
        #("username", json.string(username)),
        #("ip", json.string(ip)),
        #("timestamp", json.int(seconds)),
      ]),
    )
    <> "\n"

  let _ = simplifile.create_directory_all("./logs")

  case simplifile.append("./logs/failed_logins.log", log_entry) {
    Ok(_) -> {
      wisp.log_info("Logged failed login for " <> username)
      Nil
    }
    Error(_) -> {
      wisp.log_error("Failed to write failed login log")
      Nil
    }
  }
}

// Middleware
// -----------------------------------------------------------------------------

pub fn require_auth(
  req: Request,
  users: user.UserCollection,
  session_cache: SessionCache,
  jwt_secret: String,
  jwt_expiry_minutes: Int,
  handler: fn(Request, user.User) -> Response,
) -> Response {
  let extracted =
    extract_and_verify(
      req,
      users,
      session_cache,
      jwt_secret,
      jwt_expiry_minutes,
    )
  case extracted {
    Ok(current_user) -> handler(req, current_user)
    Error(_) ->
      wisp.response(401)
      |> wisp.json_body("{\"error\":\"Unauthorized\"}")
  }
}

fn extract_and_verify(
  req: Request,
  users: user.UserCollection,
  session_cache: SessionCache,
  jwt_secret: String,
  jwt_expiry_minutes: Int,
) -> Result(user.User, Nil) {
  use token <- result.try({
    use header <- result.try(
      req.headers
      |> list.key_find("authorization")
      |> result.replace_error(Nil),
    )
    case string.starts_with(header, "Bearer ") {
      True -> Ok(string.drop_start(header, 7))
      False -> Error(Nil)
    }
  })

  use #(user_id, jti) <- result.try(verify_jwt(
    token,
    jwt_secret,
    jwt_expiry_minutes,
  ))

  use session <- result.try(get_session(session_cache, user_id))

  use _ <- result.try(case session.jti == jti {
    True -> Ok(Nil)
    False -> Error(Nil)
  })

  user.get_by_id(users, user_id)
  |> result.replace_error(Nil)
}

pub fn require_admin(
  req: Request,
  users: user.UserCollection,
  session_cache: SessionCache,
  jwt_secret: String,
  jwt_expiry_minutes: Int,
  handler: fn(Request) -> Response,
) -> Response {
  use req, current_user <- require_auth(
    req,
    users,
    session_cache,
    jwt_secret,
    jwt_expiry_minutes,
  )

  case user.has_role(current_user, [user.AdminRole]) {
    True -> handler(req)
    False ->
      wisp.response(403)
      |> wisp.json_body("{\"error\":\"Forbidden; Admin access required\"}")
  }
}
