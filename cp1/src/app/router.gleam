import app/router/auth
import app/router/user
import app/web.{type Context}
import wisp.{type Request, type Response}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- web.middleware(req)

  case wisp.path_segments(req) {
    ["auth", "register"] -> auth.register(req, ctx)
    ["auth", "login"] -> auth.login(req, ctx)
    ["auth", "forgot_password"] -> auth.forgot_password(req, ctx)
    ["auth", "reset_password"] -> auth.reset_password(req, ctx)
    ["auth", "logout"] -> auth.logout(req, ctx)

    ["api", "profile"] -> user.get_profile(req, ctx)
    ["admin", "users"] -> user.list_users(req, ctx)

    _ -> wisp.not_found()
  }
}
