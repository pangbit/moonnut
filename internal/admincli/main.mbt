///|
extern "C" fn default_user() -> Bytes = "moonnut_cli_default_user"

///|
extern "C" fn prompt_line() -> Bytes = "moonnut_cli_read_line"

///|
extern "C" fn prompt_password() -> Bytes = "moonnut_cli_password"

///|
async fn credentials(opt : Options) -> (String, String) {
  let username = match opt.username {
    Some(user) => user
    None => {
      let default = @utf8.decode(default_user())
      @stdio.stdout.write(
        if default.is_empty() {
          "Username: "
        } else {
          "Username (" + default + "): "
        },
      )
      let input = @utf8.decode(prompt_line())
      if input.is_empty() {
        raise CliFailure("Error reading from stdin!")
      }
      if input.length() > 1 {
        input[:input.length() - 1].to_owned()
      } else {
        if default.is_empty() {
          raise CliFailure("No username available - even tried getpwuid")
        }
        default
      }
    }
  }
  let password = match opt.password {
    Some(value) => value
    None => {
      let bytes = prompt_password()
      if bytes[0] == 0 {
        raise CliFailure("getpass failed")
      }
      @utf8.decode(bytes[1:])
    }
  }
  (username, password)
}

///|
async fn command_result(
  session : @moonnut.Session,
  command : String,
  opt : Options,
) -> Unit {
  let reply = session.request_line(command)
  if !reply.has_prefix("OK") {
    raise CliFailure("Unexpected response from upsd: " + reply)
  }
  // Match the official CLI's acknowledgement length check; no completion is implied.
  if !opt.wait || @utf8.encode(reply).length() != 48 {
    @stdio.stderr.write(reply + "\n")
    return
  }
  let id = reply[12:].to_owned()
  let start = (@env.now() / 1000UL).reinterpret_as_int64()
  while true {
    if (@env.now() / 1000UL).reinterpret_as_int64() - start >=
      opt.timeout.to_int64() {
      raise CliFailure("Can't receive status tracking information: timeout")
    }
    let timeout = (opt.timeout.to_int64() * 1000L).min(2147483647L).to_int()
    let result = session.request_line(
      "GET TRACKING " + id,
      read_timeout_ms=timeout,
    )
    if !result.has_prefix("PENDING") {
      @stdio.stderr.write(result + "\n")
      return
    }
    @async.sleep(1000)
  }
}

///|
async fn authenticate(
  session : @moonnut.Session,
  user : String,
  password : String,
  wait : Bool,
  writable : Bool,
) -> Unit {
  // Official CLI submits already formatted credential text and only checks IO.
  ignore(session.request_line("USERNAME " + user))
  ignore(session.request_line("PASSWORD " + password))
  if wait {
    let reply = session.request_line("SET TRACKING ON")
    if !reply.has_prefix("OK") {
      raise CliFailure(
        "Enabling " +
        (if writable { "set variable" } else { "command" }) +
        " status tracking failed. upsd answered: " +
        reply,
      )
    }
  }
}

///|
async fn execute(opt : Options, writable : Bool) -> Unit {
  let (ups, host, port) = endpoint(opt.positionals[0])
  let client = @moonnut.Client::new(
    host,
    port~,
    connect_timeout_ms=connect_timeout(opt),
  )
  let session = client.connect()
  defer session.close()
  errdefer @async.protect_from_cancel(() => {
    if !session.is_closed() {
      ignore(session.request_line("LOGOUT")) catch {
        _ => ()
      }
    }
  })
  if writable && opt.setvar is None {
    list_writable(session, ups)
  } else if !writable && opt.list {
    list_commands(session, ups)
  } else if !writable && opt.positionals.length() < 2 {
    usage(writable)
  } else {
    if !writable && !opt.positionals[1].contains(".") {
      raise CliFailure("Error: old command names are not supported")
    }
    let (username, password) = credentials(opt)
    if writable {
      let text = opt.setvar.unwrap()
      let (name, value) = match text.split_once("=") {
        Some((name, value)) => (name.to_owned(), value.to_owned())
        None => {
          @stdio.stdout.write("Enter new value for " + text + ": ")
          let input = @utf8.decode(prompt_line())
          if input.is_empty() {
            raise CliFailure("Error reading from stdin!")
          }
          (text, input[:input.length() - 1].to_owned())
        }
      }
      // NUT checks old variable names after submitting both credentials.
      authenticate(session, username, password, false, writable)
      if !name.contains(".") {
        raise CliFailure("Error: old variable names are not supported")
      }
      if opt.wait {
        let reply = session.request_line("SET TRACKING ON")
        if !reply.has_prefix("OK") {
          raise CliFailure(
            "Enabling set variable status tracking failed. upsd answered: " +
            reply,
          )
        }
      }
      command_result(
        session,
        "SET VAR " + ups + " " + name + " " + @moonnut.quote_argument(value),
        opt,
      )
    } else {
      authenticate(session, username, password, opt.wait, writable)
      let suffix = if opt.positionals.length() > 2 {
        " " + opt.positionals[2]
      } else {
        ""
      }
      command_result(
        session,
        "INSTCMD " + ups + " " + opt.positionals[1] + suffix,
        opt,
      )
    }
  }
  if !session.is_closed() {
    ignore(session.request_line("LOGOUT")) catch {
      _ => ()
    }
  }
}

///|
/// POSIX management CLI entry point. Product identity remains moonnut.
pub async fn run(writable~ : Bool) -> Unit {
  let mut exit_code = 0
  try {
    if parse_options(@env.args(), writable) is Some(opt) {
      if opt.positionals.is_empty() {
        usage(writable)
      } else {
        execute(opt, writable)
      }
    }
  } catch {
    CliFailure(message) => {
      @stdio.stderr.write(message + "\n")
      exit_code = 1
    }
    @moonnut.NutError::Server(code) => {
      let message = match code {
        "UNKNOWN-UPS" => "Unknown UPS"
        "ACCESS-DENIED" => "Access denied"
        "VAR-NOT-SUPPORTED" => "Variable not supported by UPS"
        "DATA-STALE" => "Data stale"
        "DRIVER-NOT-CONNECTED" => "Driver not connected"
        "UNKNOWN-COMMAND" => "upsd is too old to support this query"
        _ => code
      }
      @stdio.stderr.write("Error: " + message + "\n")
      exit_code = 1
    }
    _ => {
      @stdio.stderr.write("Error: connection or protocol failure\n")
      exit_code = 1
    }
  }
  if exit_code != 0 {
    @env.exit(exit_code)
  }
}
