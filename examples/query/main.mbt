///|
/// Connect only to an explicitly supplied server. No default device is polled.
async fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("Usage: query HOST PORT [--plaintext | --ca FILE]")
    println("TLS with certificate and hostname verification is the default.")
    return
  }
  try {
    let security = match args {
      [_, _, _] => @moonnut.Tls
      [_, _, _, "--plaintext"] => @moonnut.Plaintext
      [_, _, _, "--ca", file] => @moonnut.TlsCaFile(file)
      _ => {
        println("Invalid command line")
        @env.exit(2)
      }
    }
    let client = @moonnut.Client::new(
      args[1],
      port=@string.parse_int(args[2]),
      security~,
      username?=@env.get_env_var("MOONNUT_USERNAME"),
      password?=@env.get_env_var("MOONNUT_PASSWORD"),
    )
    for ups in client.list_ups() {
      println(ups.name + "\t" + ups.description)
    }
  } catch {
    // Do not echo credentials, arguments or untrusted responses in a CLI error.
    _ => {
      println("Query failed. Check TLS trust, access and server availability.")
      @env.exit(1)
    }
  }
}
