///|
priv suberror CliFailure {
  CliFailure(String)
}

///|
priv struct Options {
  mut username : String?
  mut password : String?
  mut setvar : String?
  mut list : Bool
  mut wait : Bool
  mut timeout : UInt32
  mut connect_timeout : String?
  positionals : Array[String]
}

///|
fn usage(writable : Bool) -> Unit {
  let name = if writable { "upsrw" } else { "upscmd" }
  println("moonnut " + name + " (NUT 2.8.4 client profile, unreleased)")
  println(
    if writable {
      "usage: upsrw [-l] [-s VAR[=VALUE]] [-u USER] [-p PASSWORD] [-w] [-t SECONDS] [-W SECONDS] ups[@host[:port]]"
    } else {
      "usage: upscmd [-l] [-u USER] [-p PASSWORD] [-w] [-t SECONDS] [-W SECONDS] ups[@host[:port]] [command [value]]"
    },
  )
  println(
    "-w waits for a driver result (default 10 seconds); a terminal ERR result still exits 0, as in NUT.",
  )
  println(
    "Default: unverified TLS; STARTTLS refusal permits plaintext credentials. Use the library's explicit TLS modes when verification is required.",
  )
}

///|
async fn parse_options(args : Array[String], writable : Bool) -> Options? {
  let opt : Options = {
    username: None,
    password: None,
    setvar: None,
    list: false,
    wait: false,
    timeout: 10U,
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
      let ch = chars[offset]
      match ch {
        'h' => {
          usage(writable)
          return None
        }
        'V' => {
          println(
            "moonnut " +
            (if writable { "upsrw" } else { "upscmd" }) +
            " (NUT 2.8.4 client profile, unreleased)",
          )
          return None
        }
        'w' => opt.wait = true
        'l' => {
          opt.list = true
          if writable && opt.setvar is Some(_) {
            @stdio.stderr.write(
              "Listing mode requested, overriding setvar specified earlier!\n",
            )
            opt.setvar = None
          }
        }
        'u' | 'p' | 't' | 'W' | 's' => {
          if ch == 's' && !writable {
            usage(writable)
            return None
          }
          let value = if offset + 1 < chars.length() {
            arg[offset + 1:].to_owned()
          } else {
            index += 1
            if index >= args.length() {
              usage(writable)
              return None
            }
            args[index]
          }
          match ch {
            'u' => opt.username = Some(value)
            'p' => opt.password = Some(value)
            's' => opt.setvar = Some(value)
            'W' => opt.connect_timeout = Some(value)
            _ =>
              opt.timeout = @string.parse_uint(value.trim()) catch {
                _ =>
                  raise CliFailure(
                    "Could not convert the provided value for timeout ('-t' option) to unsigned int",
                  )
              }
          }
          break
        }
        _ => {
          usage(writable)
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
/// C-style integer-prefix behavior used for RANGE display and address ports.
fn integer_prefix(value : String) -> Int64 {
  let chars = value.trim().to_array()
  let mut index = 0
  let mut sign = 1L
  if chars.length() > 0 && (chars[0] == '-' || chars[0] == '+') {
    if chars[0] == '-' {
      sign = -1L
    }
    index = 1
  }
  let mut result = 0L
  while index < chars.length() && chars[index] >= '0' && chars[index] <= '9' {
    if result > 922337203685477580L ||
      (result == 922337203685477580L && chars[index] > '7') {
      return if sign < 0 { -9223372036854775807L } else { 9223372036854775807L }
    }
    result = result * 10L + (chars[index].to_int() - 48).to_int64()
    index += 1
  }
  result * sign
}

///|
fn endpoint(value : String) -> (String, String, Int32) raise {
  let invalid = "Error: invalid UPS definition.  Required format: upsname[@hostname[:port]]"
  if value.is_empty() || value.has_prefix("@") {
    raise CliFailure(invalid)
  }
  match value.split_once("@") {
    None => {
      if value.contains(":") {
        raise CliFailure(invalid)
      }
      (value, "localhost", 3493)
    }
    Some((ups, address)) => {
      if address.is_empty() {
        raise CliFailure(invalid)
      }
      let (host, port_text) = if address.has_prefix("[") {
        match address.find("]") {
          None => raise CliFailure(invalid)
          Some(end) => {
            let suffix = address[end + 1:]
            (
              address[1:end].to_owned(),
              if suffix.has_prefix(":") {
                Some(suffix[1:].to_owned())
              } else {
                None
              },
            )
          }
        }
      } else {
        match address.split_once(":") {
          Some((host, port)) => (host.to_owned(), Some(port.to_owned()))
          None => (address.to_owned(), None)
        }
      }
      let port = match port_text {
        None => 3493L
        Some(text) => integer_prefix(text)
      }
      if host.is_empty() || port < 1L || port > 65535L {
        raise CliFailure(invalid)
      }
      (ups.to_owned(), host, port.to_int())
    }
  }
}

///|
async fn connect_timeout(cli_value : String?) -> Int32 {
  let mut timeout = 10000
  for
    (source, value) in [
      (
        "NUT_DEFAULT_CONNECT_TIMEOUT",
        @env.get_env_var("NUT_DEFAULT_CONNECT_TIMEOUT"),
      ),
      ("cli_secs", cli_value),
    ] {
    if value is Some(text) {
      let parsed = Some(@string.parse_double(text.trim())) catch { _ => None }
      match parsed {
        Some(seconds) if seconds >= 0 && seconds <= 2147483.647 =>
          timeout = if seconds == 0 {
            0
          } else {
            (seconds * 1000).to_int().max(1)
          }
        _ =>
          @stdio.stderr.write(
            "upscli_init_default_connect_timeout: " +
            source +
            "='" +
            text +
            "' value was not recognized, ignored\n",
          )
      }
    }
  }
  timeout
}
