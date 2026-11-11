///|
/// Errors never include credentials or the raw response line.
#derive(@debug.Debug)
pub suberror NutError {
  InvalidArgument(String)
  Protocol(String)
  Server(String)
  LimitExceeded(String)
  UnexpectedEof
  ConnectionClosed
}

///|
/// Decode a NUT parseconf-style line without its line ending.
/// Supports quoted words, escapes, comments and equals tokens.
/// Physical newline continuation is rejected for network framing.
pub fn parse_line(line : String) -> Array[String] raise NutError {
  let out : Array[String] = []
  let mut word = StringBuilder()
  let mut active = false
  let mut quoted = false
  let mut escaped = false
  for ch in line.iter() {
    if (ch.to_int() < 32 && ch != '\t') || ch.to_int() == 127 {
      raise Protocol("control character in line")
    }
    if escaped {
      word.write_char(ch)
      active = true
      escaped = false
    } else if ch == '\\' {
      escaped = true
      active = true
    } else if quoted {
      if ch == '"' {
        out.push(word.to_string())
        word = StringBuilder()
        active = false
        quoted = false
      } else {
        word.write_char(ch)
      }
    } else if ch == '#' {
      break
    } else if ch == ' ' || ch == '\t' || ch == '=' {
      if active {
        out.push(word.to_string())
        word = StringBuilder()
        active = false
      }
      if ch == '=' {
        out.push("=")
      }
    } else if ch == '"' && !active {
      quoted = true
      active = true
    } else {
      active = true
      word.write_char(ch)
    }
  }
  if quoted || escaped {
    raise Protocol("incomplete quoted or escaped token")
  }
  if active {
    out.push(word.to_string())
  }
  out
}

///|
/// Quote an argument. Reject controls to prevent command injection.
pub fn quote_argument(value : String) -> String raise NutError {
  let out = StringBuilder()
  out.write_char('"')
  for ch in value.iter() {
    if ch.to_int() < 32 || ch.to_int() == 127 {
      raise InvalidArgument("argument contains a control character")
    }
    if ch == '"' || ch == '\\' || ch == '#' {
      out.write_char('\\')
    }
    out.write_char(ch)
  }
  out.write_char('"')
  out.to_string()
}

///|
fn check_server(tokens : Array[String]) -> Unit raise NutError {
  if tokens.length() > 0 && tokens[0] == "ERR" {
    if tokens.length() == 2 {
      let code = tokens[1]
      if code.is_empty() || code.length() > 128 {
        raise Protocol("invalid server error code")
      }
      for ch in code.iter() {
        if !(ch >= 'A' && ch <= 'Z') &&
          !(ch >= '0' && ch <= '9') &&
          ch != '-' &&
          ch != '_' {
          raise Protocol("invalid server error code")
        }
      }
      raise Server(code)
    }
    raise Protocol("malformed error response")
  }
}

///|
fn expect(
  tokens : Array[String],
  wanted : Array[String],
) -> Unit raise NutError {
  check_server(tokens)
  if tokens != wanted {
    raise Protocol("response does not match request")
  }
}

///|
pub extend NutError with @debug.Debug::{to_repr}

///|
/// libupsclient compares echoed query tokens with strcasecmp.
fn expect_echo(
  tokens : Array[String],
  wanted : Array[String],
) -> Unit raise NutError {
  if tokens.length() != wanted.length() {
    raise Protocol("response does not match request")
  }
  for i in 0..<wanted.length() {
    if !tokens[i].equal_ignore_ascii_case(wanted[i]) {
      raise Protocol("response does not match request")
    }
  }
}
