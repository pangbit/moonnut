///|
priv struct QueryOptions {
  mut list : Bool
  mut verbose : Bool
  mut clients : Bool
  mut connect_timeout : String?
  positionals : Array[String]
}

///|
fn query_usage() -> Unit {
  println("moonnut upsc (NUT 2.8.4 client profile, unreleased)")
  println("usage: upsc [-W SECONDS] -l | -L [host[:port]]")
  println("       upsc [-W SECONDS] ups[@host[:port]] [variable]")
  println("       upsc [-W SECONDS] -c ups[@host[:port]]")
  println(
    "-h shows help; -V shows the client version. Default host: localhost; port: 3493.",
  )
  println(
    "Default: unverified TLS; STARTTLS refusal permits plaintext. Use the library's explicit TLS modes when verification is required.",
  )
}

///|
fn parse_query_options(args : Array[String]) -> QueryOptions? {
  let opt : QueryOptions = {
    list: false,
    verbose: false,
    clients: false,
    connect_timeout: None,
    positionals: [],
  }
  let mut index = 1
  while index < args.length() {
    let arg = args[index]
    if arg == "--" {
      index += 1
      break
    }
    if !arg.has_prefix("-") || arg == "-" {
      break
    }
    let chars = arg.to_array()
    let mut offset = 1
    while offset < chars.length() {
      match chars[offset] {
        'l' => opt.list = true
        'L' => {
          opt.list = true
          opt.verbose = true
        }
        'c' => opt.clients = true
        'V' => {
          println("moonnut upsc (NUT 2.8.4 client profile, unreleased)")
          return None
        }
        'W' => {
          opt.connect_timeout = Some(
            if offset + 1 < chars.length() {
              arg[offset + 1:].to_owned()
            } else {
              index += 1
              if index >= args.length() {
                query_usage()
                return None
              }
              args[index]
            },
          )
          break
        }
        _ => {
          query_usage()
          return None
        }
      }
      offset += 1
    }
    index += 1
  }
  while index < args.length() {
    opt.positionals.push(args[index])
    index += 1
  }
  Some(opt)
}

///|
/// Match common splitname/splitaddr diagnostics; unusual C buffer/tokenizer
/// boundary behavior remains an explicit compatibility gap.
fn query_endpoint(opt : QueryOptions) -> (String, String, Int32) raise {
  let value = if opt.positionals.is_empty() {
    if opt.list {
      Some("localhost")
    } else {
      None
    }
  } else {
    Some(opt.positionals[0])
  }
  let invalid = if opt.list {
    "Error: invalid hostname.\nRequired format: [hostname[:port]]"
  } else {
    "Error: invalid UPS definition.\nRequired format: upsname[@hostname[:port]]"
  }
  guard value is Some(text) else { raise CliFailure(invalid) }
  let target = if opt.list { "query@" + text } else { text }
  endpoint(target) catch {
    _ => {
      let reason = if !opt.list && text.is_empty() {
        "upscli_splitname: can't parse empty string"
      } else if !opt.list && text.has_prefix("@") {
        "upscli_splitname: got empty upsname string"
      } else if !opt.list && !text.contains("@") {
        "upscli_splitname: port specified, but not a hostname"
      } else {
        let address = if opt.list {
          text
        } else {
          text.split_once("@").unwrap().1.to_owned()
        }
        if address.is_empty() {
          if opt.list {
            "upscli_splitaddr: can't parse empty string"
          } else {
            "upscli_splitname: got the @ separator and then an empty hostname[:port] string"
          }
        } else if address.has_prefix("[") && !address.contains("]") {
          "upscli_splitaddr: missing closing bracket in [domain literal]"
        } else {
          "upscli_splitaddr: no port specified after ':' separator"
        }
      }
      raise CliFailure(reason + "\n" + invalid)
    }
  }
}

///|
async fn query_execute(opt : QueryOptions) -> Unit {
  // Upstream resolves timeout configuration before validating the address.
  let timeout = connect_timeout(opt.connect_timeout)
  let (ups, host, port) = query_endpoint(opt)
  let session = @moonnut.Client::new(host, port~, connect_timeout_ms=timeout).connect()
  defer session.close()
  defer @async.protect_from_cancel(() => {
    if !session.is_closed() {
      ignore(session.request_line("LOGOUT")) catch {
        _ => ()
      }
    }
  })
  if opt.list || opt.clients || opt.positionals.length() == 1 {
    query_list(session, opt, ups)
  } else {
    let name = opt.positionals[1]
    if !name.contains(".") {
      raise CliFailure("Error: old-style variable names are not supported")
    }
    println(session.get_var(ups, name))
  }
}

///|
/// Read-only upsc entry point. Never authenticates or registers a consumer.
pub async fn run_query() -> Unit {
  let mut scalar = false
  let mut exit_code = 0
  try {
    if parse_query_options(@env.args()) is Some(opt) {
      scalar = !opt.list && !opt.clients && opt.positionals.length() > 1
      query_execute(opt)
    }
  } catch {
    CliFailure(message) => {
      @stdio.stderr.write(message + "\n")
      exit_code = 1
    }
    @moonnut.NutError::Server(code) => {
      @stdio.stderr.write("Error: " + server_message(code, scalar) + "\n")
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

///|
async fn query_list(
  session : @moonnut.Session,
  opt : QueryOptions,
  ups : String,
) -> Unit {
  let query = if opt.list {
    ["UPS"]
  } else if opt.clients {
    ["CLIENT", ups]
  } else {
    ["VAR", ups]
  }
  let required = if !opt.list && !opt.clients { 4 } else { 3 }
  session.with_list(query, reader => {
    while true {
      // upsc ignores list_next failures, but treats short delivered rows as fatal.
      // Resource caps are a moonnut extension and remain explicit failures.
      let row = reader.next() catch {
        @moonnut.NutError::LimitExceeded(_) as error => raise error
        _ => None
      }
      guard row is Some(row) else { break }
      if row.length() < required {
        raise CliFailure(
          "Error: insufficient data (got " +
          row.length().to_string() +
          " args, need at least " +
          required.to_string() +
          ")",
        )
      }
      if opt.list {
        println(if opt.verbose { row[1] + ": " + row[2] } else { row[1] })
      } else if opt.clients {
        println(row[2])
      } else {
        println(row[2] + ": " + row[3])
      }
    }
  }) catch {
    @moonnut.NutError::Protocol(_) => raise CliFailure("Error: Protocol error")
    @moonnut.NutError::UnexpectedEof =>
      raise CliFailure("Error: Server disconnected")
    error => raise error
  }
}
