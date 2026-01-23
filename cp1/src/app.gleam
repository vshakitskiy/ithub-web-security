import app/env
import app/router
import app/web
import gleam/erlang/process
import gleam/int
import mist
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let ctx = web.init_context("./data")

  let assert Ok(_started) =
    router.handle_request(_, ctx)
    |> wisp_mist.handler(env.get("APP_SECRET"))
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(env.get_default("PORT", int.parse, 8080))
    |> mist.start
    as "✗ Failed to start mist server!"

  process.sleep_forever()
}
