import app/web.{type Context}
import app/web/auth
import app/web/user
import gleam/http.{Get}
import gleam/json
import wisp.{type Request, type Response}

pub fn list_users(req: Request, ctx: Context) -> Response {
  use req <- auth.require_admin(
    req,
    ctx.users,
    ctx.session_cache,
    ctx.jwt_secret,
    ctx.jwt_expiry_minutes,
  )
  use <- wisp.require_method(req, Get)

  do_list_users(ctx)
}

fn do_list_users(ctx: Context) -> Response {
  case user.list_all(ctx.users) {
    Ok(users) -> {
      web.json_response(
        200,
        json.object([
          #("users", json.array(users, user.user_to_public_json)),
        ]),
      )
    }
    Error(_) -> web.error_response(500, "Failed to retrieve users")
  }
}

pub fn get_profile(req: Request, ctx: Context) -> Response {
  use req, user <- auth.require_auth(
    req,
    ctx.users,
    ctx.session_cache,
    ctx.jwt_secret,
    ctx.jwt_expiry_minutes,
  )
  use <- wisp.require_method(req, Get)

  web.json_response(200, user.user_to_public_json(user))
}
