import app/config
import app/router
import app/web.{Context}
import gleam/erlang/process
import mist
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  let config = config.load()

  let context = Context

  let assert Ok(_started) =
    router.handle_request(_, context)
    |> wisp_mist.handler(config.app_secret)
    |> mist.new
    |> mist.port(8080)
    |> mist.start
    as "✗ Failed to start mist server!"

  process.sleep_forever()
}
