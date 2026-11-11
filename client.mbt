///|
/// TryTls follows the NUT 2.8.4 CLI default: try unverified TLS and continue
/// in plaintext if STARTTLS is refused. Tls/TlsCaFile require verified TLS.
pub(all) enum Security {
  TryTls
  TlsUnverified
  Tls
  TlsCaFile(String)
  Plaintext
}

///|
/// Each operation owns a fresh connection, so failures and concurrent calls
/// cannot desynchronize a shared protocol stream.
pub struct Client {
  priv host : String
  priv port : Int32
  priv security : Security
  priv username : String?
  priv password : String?
  priv timeout_ms : Int32?
  priv connect_timeout_ms : Int32
  priv read_timeout_ms : Int32
  priv max_line_bytes : Int32
  priv max_rows : Int32
  priv max_response_bytes : Int32
}

///|
/// Optional timeout_ms caps the whole operation. By default, connection has a
/// 10-second timeout and each transport read has a 5-second timeout (NUT CLI values).
/// NUT may accept USERNAME/PASSWORD without validating them until a privileged
/// command. A successful read does not prove that credentials are correct.
pub fn Client::new(
  host : String,
  port~ : Int32 = 3493,
  security~ : Security = TryTls,
  username? : String,
  password? : String,
  timeout_ms? : Int32,
  connect_timeout_ms~ : Int32 = 10000,
  read_timeout_ms~ : Int32 = 5000,
  max_line_bytes~ : Int32 = 65536,
  max_rows~ : Int32 = 4096,
  max_response_bytes~ : Int32 = 4194304,
) -> Client raise NutError {
  if host.is_empty() || port < 1 || port > 65535 {
    raise InvalidArgument("invalid host or port")
  }
  if timeout_ms is Some(value) && value <= 0 {
    raise InvalidArgument("invalid operation timeout")
  }
  if connect_timeout_ms <= 0 ||
    read_timeout_ms <= 0 ||
    max_line_bytes < 16 ||
    max_line_bytes > 1048576 ||
    max_rows < 1 ||
    max_rows > 65536 ||
    max_response_bytes < max_line_bytes ||
    max_response_bytes > 67108864 {
    raise InvalidArgument("invalid resource limits")
  }
  ignore(quote_argument(host))
  match (username, password) {
    (Some(u), Some(p)) => {
      ignore(quote_argument(u))
      ignore(quote_argument(p))
      if u.is_empty() {
        raise InvalidArgument("username must not be empty")
      }
    }
    (None, None) => ()
    _ =>
      raise InvalidArgument("username and password must be supplied together")
  }
  {
    host,
    port,
    security,
    username,
    password,
    timeout_ms,
    connect_timeout_ms,
    read_timeout_ms,
    max_line_bytes,
    max_rows,
    max_response_bytes,
  }
}

///|
priv enum Transport {
  Clear(@socket.Tcp)
  Secure(@tls.Tls)
}

///|
priv struct Session {
  mut transport : Transport
  mut pending : Bytes
  mut offset : Int32
  mut received : Int32
  max_response_bytes : Int32
  max_line_bytes : Int32
  read_timeout_ms : Int32
}

///|
async fn Session::write(self : Session, line : String) -> Unit {
  match self.transport {
    Clear(tcp) => tcp.write(line + "\n")
    Secure(tls) => tls.write(line + "\n")
  }
}

///|
/// One-byte STARTTLS reads prevent reading encrypted data into a cleartext
/// buffer. Normal replies use a bounded buffer and retain fragmented lines.
async fn Session::raw_line(self : Session, handshake~ : Bool = false) -> String {
  let buffer = @buffer.Buffer()
  while true {
    if self.offset == self.pending.length() {
      let chunk = @async.with_timeout(self.read_timeout_ms, () => {
        match self.transport {
          Clear(tcp) => tcp.read_some(max_len=if handshake { 1 } else { 4096 })
          Secure(tls) => tls.read_some(max_len=4096)
        }
      })
      match chunk {
        None => raise UnexpectedEof
        Some(bytes) => {
          self.pending = bytes
          self.offset = 0
        }
      }
    }
    let byte = self.pending[self.offset]
    self.offset += 1
    self.received += 1
    if self.received > self.max_response_bytes {
      raise LimitExceeded("response")
    }
    if byte == b'\n' {
      let bytes = buffer.to_bytes()
      let len = bytes.length()
      let text = try {
        if len > 0 && bytes[len - 1] == b'\r' {
          @utf8.decode(bytes[:len - 1])
        } else {
          @utf8.decode(bytes)
        }
      } catch {
        _ => raise Protocol("invalid UTF-8 response")
      }
      return text
    }
    if buffer.length() >= self.max_line_bytes {
      raise LimitExceeded("line")
    }
    buffer.write_byte(byte)
  } nobreak {
    raise UnexpectedEof
  }
}

///|
async fn Session::line(self : Session) -> Array[String] {
  let tokens = parse_line(self.raw_line())
  if tokens.is_empty() {
    raise Protocol("empty response")
  }
  check_server(tokens)
  tokens
}

///|
async fn[T] with_optional_timeout(timeout : Int32?, run : async () -> T) -> T {
  match timeout {
    Some(ms) => @async.with_timeout(ms, run)
    None => run()
  }
}

///|
async fn Client::query(
  self : Client,
  command : String,
  header : Array[String],
  list : Bool,
  row_values~ : Int32 = 2,
  raw~ : Bool = false,
) -> Array[Array[String]] {
  with_optional_timeout(self.timeout_ms, () => {
    let tcp = @async.with_timeout(self.connect_timeout_ms, () => {
      @socket.Tcp::connect_to_host(self.host, port=self.port)
    })
    defer tcp.close()
    let session : Session = {
      transport: Clear(tcp),
      pending: b"",
      offset: 0,
      received: 0,
      max_response_bytes: self.max_response_bytes,
      max_line_bytes: self.max_line_bytes,
      read_timeout_ms: self.read_timeout_ms,
    }
    match self.security {
      Plaintext => ()
      _ => {
        session.write("STARTTLS")
        let reply = session.raw_line(handshake=true)
        if reply.has_prefix("OK STARTTLS") {
          let trust = match self.security {
            TryTls | TlsUnverified => @tls.NoVerification
            TlsCaFile(path) => @tls.CustomPemFile(path)
            _ => @tls.SystemRoot
          }
          let tls = @async.with_timeout(self.read_timeout_ms, () => {
            @tls.Tls::client(tcp, host=self.host, trust~)
          })
          session.transport = Secure(tls)
        } else if !(self.security is TryTls) {
          expect(parse_line(reply), ["OK", "STARTTLS"])
        }
      }
    }
    defer (match session.transport {
      Secure(tls) => tls.close()
      _ => ()
    })
    match (self.username, self.password) {
      (Some(user), Some(pass)) => {
        session.write("USERNAME " + quote_argument(user))
        expect(session.line(), ["OK"])
        session.write("PASSWORD " + quote_argument(pass))
        expect(session.line(), ["OK"])
      }
      _ => ()
    }
    session.write(command)
    if raw {
      let reply = session.raw_line()
      if reply.is_empty() {
        raise Protocol("empty response")
      }
      if reply.has_prefix("ERR ") {
        check_server(parse_line(reply))
      }
      return [[reply]]
    }
    if !list {
      return [session.line()]
    }
    let begin = ["BEGIN", "LIST"] + header
    let end = ["END", "LIST"] + header
    expect_echo(session.line(), begin)
    let rows : Array[Array[String]] = []
    while true {
      let row = session.line()
      if row.length() == end.length() && row[0] == "END" && row[1] == "LIST" {
        expect_echo(row, end)
        return rows
      }
      if rows.length() >= self.max_rows {
        raise LimitExceeded("rows")
      }
      if row.length() != header.length() + row_values {
        raise Protocol("invalid list row shape")
      }
      for i in 0..<header.length() {
        if !row[i].equal_ignore_ascii_case(header[i]) {
          raise Protocol("invalid list row header")
        }
      }
      rows.push(row)
    } nobreak {
      raise UnexpectedEof
    }
  })
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Ups {
  name : String
  description : String
}

///|
/// Values remain strings as provided by the server.
#derive(Eq, @debug.Debug)
pub(all) struct Variable {
  name : String
  value : String
}

///|
/// No management or shutdown command is exposed.
pub async fn Client::list_ups(self : Client) -> Array[Ups] {
  let rows = self.query("LIST UPS", ["UPS"], true)
  rows.map(row => { name: row[1], description: row[2], })
}

///|
pub async fn Client::list_vars(self : Client, ups : String) -> Array[Variable] {
  let rows = self.query("LIST VAR " + quote_argument(ups), ["VAR", ups], true)
  rows.map(row => { name: row[2], value: row[3], })
}

///|
pub async fn Client::get_var(
  self : Client,
  ups : String,
  name : String,
) -> String {
  let rows = self.query(
    "GET VAR " + quote_argument(ups) + " " + quote_argument(name),
    [],
    false,
  )
  match rows[0] {
    [kind, device, key, value] if kind.equal_ignore_ascii_case("VAR") &&
      device.equal_ignore_ascii_case(ups) &&
      key.equal_ignore_ascii_case(name) => value
    _ => raise Protocol("invalid variable response")
  }
}

///|
/// Read the configured UPS description (or the server's "Unavailable" text).
pub async fn Client::get_ups_description(self : Client, ups : String) -> String {
  let rows = self.query("GET UPSDESC " + quote_argument(ups), [], false)
  match rows[0] {
    [kind, device, description] if kind.equal_ignore_ascii_case("UPSDESC") &&
      device.equal_ignore_ascii_case(ups) => description
    _ => raise Protocol("invalid UPS description response")
  }
}

///|
/// Read the server's variable description, which may be localized or unavailable.
pub async fn Client::get_var_description(
  self : Client,
  ups : String,
  name : String,
) -> String {
  let rows = self.query(
    "GET DESC " + quote_argument(ups) + " " + quote_argument(name),
    [],
    false,
  )
  match rows[0] {
    [kind, device, key, description] if kind.equal_ignore_ascii_case("DESC") &&
      device.equal_ignore_ascii_case(ups) &&
      key.equal_ignore_ascii_case(name) => description
    _ => raise Protocol("invalid variable description response")
  }
}

///|
/// Return all GET TYPE tokens in server order, without coercing variable values.
/// Examples: ["RW", "STRING:32"], ["ENUM", "NUMBER"]. Unknown tokens are retained.
/// An empty array is valid: NUT defines an omitted type as numeric.
/// RW describes server metadata; it never grants this client write capability.
pub async fn Client::get_var_type(
  self : Client,
  ups : String,
  name : String,
) -> Array[String] {
  let rows = self.query(
    "GET TYPE " + quote_argument(ups) + " " + quote_argument(name),
    [],
    false,
  )
  let row = rows[0]
  if row.length() < 3 ||
    !row[0].equal_ignore_ascii_case("TYPE") ||
    !row[1].equal_ignore_ascii_case(ups) ||
    !row[2].equal_ignore_ascii_case(name) {
    raise Protocol("invalid variable type response")
  }
  row[3:].to_owned()
}

///|
pub extend Ups with Eq::{equal, not_equal}

///|
pub extend Ups with @debug.Debug::{to_repr}

///|
pub extend Variable with Eq::{equal, not_equal}

///|
pub extend Variable with @debug.Debug::{to_repr}

///|
/// Discover writable variables and their current values without modifying them.
pub async fn Client::list_rw(self : Client, ups : String) -> Array[Variable] {
  let rows = self.query("LIST RW " + quote_argument(ups), ["RW", ups], true)
  rows.map(row => { name: row[2], value: row[3], })
}

///|
/// Allowed values in server order. Read the current value separately with get_var.
pub async fn Client::list_enum(
  self : Client,
  ups : String,
  name : String,
) -> Array[String] {
  let rows = self.query(
    "LIST ENUM " + quote_argument(ups) + " " + quote_argument(name),
    ["ENUM", ups, name],
    true,
    row_values=1,
  )
  rows.map(row => row[3])
}

///|
/// One advertised interval. Endpoints remain server strings without numeric coercion.
#derive(Eq, @debug.Debug)
pub(all) struct VariableRange {
  min : String
  max : String
}

///|
/// Preserve every interval in server order, including gaps between ranges.
pub async fn Client::list_range(
  self : Client,
  ups : String,
  name : String,
) -> Array[VariableRange] {
  let rows = self.query(
    "LIST RANGE " + quote_argument(ups) + " " + quote_argument(name),
    ["RANGE", ups, name],
    true,
  )
  rows.map(row => { min: row[3], max: row[4], })
}

///|
/// Discover command names only. This client cannot execute instant commands.
pub async fn Client::list_commands(
  self : Client,
  ups : String,
) -> Array[String] {
  let rows = self.query(
    "LIST CMD " + quote_argument(ups),
    ["CMD", ups],
    true,
    row_values=1,
  )
  rows.map(row => row[2])
}

///|
/// Read an instant command description without invoking the command.
pub async fn Client::get_command_description(
  self : Client,
  ups : String,
  command : String,
) -> String {
  let rows = self.query(
    "GET CMDDESC " + quote_argument(ups) + " " + quote_argument(command),
    [],
    false,
  )
  match rows[0] {
    [kind, device, name, description] if kind.equal_ignore_ascii_case("CMDDESC") &&
      device.equal_ignore_ascii_case(ups) &&
      name.equal_ignore_ascii_case(command) => description
    _ => raise Protocol("invalid command description response")
  }
}

///|
pub extend VariableRange with Eq::{equal, not_equal}

///|
pub extend VariableRange with @debug.Debug::{to_repr}

///|
/// Count clients which have issued LOGIN for this UPS, not all TCP connections.
pub async fn Client::get_num_logins(self : Client, ups : String) -> Int32 {
  let rows = self.query("GET NUMLOGINS " + quote_argument(ups), [], false)
  match rows[0] {
    [kind, device, value] if kind.equal_ignore_ascii_case("NUMLOGINS") &&
      device.equal_ignore_ascii_case(ups) => {
      if value.is_empty() || !value.iter().all(ch => ch.is_ascii_digit()) {
        raise Protocol("invalid login count")
      }
      @string.parse_int(value) catch {
        _ => raise Protocol("invalid login count")
      }
    }
    _ => raise Protocol("invalid login count response")
  }
}

///|
/// Preserve the server's LOGIN client addresses, including repeated addresses.
pub async fn Client::list_clients(self : Client, ups : String) -> Array[String] {
  let rows = self.query(
    "LIST CLIENT " + quote_argument(ups),
    ["CLIENT", ups],
    true,
    row_values=1,
  )
  rows.map(row => row[2])
}

///|
/// The server's unmodified VER banner, excluding the line delimiter.
pub async fn Client::get_server_version(self : Client) -> String {
  self.query("VER", [], false, raw=true)[0][0]
}

///|
pub async fn Client::get_net_version(self : Client) -> String {
  self.query("NETVER", [], false, raw=true)[0][0]
}

///|
/// Request PROTVER explicitly; NUT 2.8.4 treats it as a NETVER alias.
pub async fn Client::get_protocol_version(self : Client) -> String {
  self.query("PROTVER", [], false, raw=true)[0][0]
}

///|
/// HELP is informational: NUT omits some supported commands from this response.
pub async fn Client::get_help(self : Client) -> String {
  self.query("HELP", [], false, raw=true)[0][0]
}
