///|
/// TLS is mandatory by default. Plaintext is only for explicitly trusted local
/// networks or an external authenticated tunnel; credentials are never allowed.
pub(all) enum Security {
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
  priv timeout_ms : Int32
  priv max_line_bytes : Int32
  priv max_rows : Int32
  priv max_response_bytes : Int32
}

///|
/// The timeout covers DNS, connection, TLS, credential exchange and the whole query.
/// NUT may accept USERNAME/PASSWORD without validating them until a privileged
/// command. A successful read does not prove that credentials are correct.
pub fn Client::new(
  host : String,
  port~ : Int32 = 3493,
  security~ : Security = Tls,
  username? : String,
  password? : String,
  timeout_ms~ : Int32 = 5000,
  max_line_bytes~ : Int32 = 65536,
  max_rows~ : Int32 = 4096,
  max_response_bytes~ : Int32 = 4194304,
) -> Client raise NutError {
  if host.is_empty() || port < 1 || port > 65535 {
    raise InvalidArgument("invalid host or port")
  }
  if timeout_ms <= 0 ||
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
      if security is Plaintext {
        raise InvalidArgument("credentials require verified TLS")
      }
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
async fn Session::line(
  self : Session,
  handshake~ : Bool = false,
) -> Array[String] {
  let buffer = @buffer.Buffer()
  while true {
    if self.offset == self.pending.length() {
      let chunk = match self.transport {
        Clear(tcp) => tcp.read_some(max_len=if handshake { 1 } else { 4096 })
        Secure(tls) => tls.read_some(max_len=4096)
      }
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
      let tokens = parse_line(text)
      if tokens.is_empty() {
        raise Protocol("empty response")
      }
      check_server(tokens)
      return tokens
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
async fn Client::query(
  self : Client,
  command : String,
  header : Array[String],
  list : Bool,
) -> Array[Array[String]] {
  @async.with_timeout(self.timeout_ms, () => {
    let tcp = @socket.Tcp::connect_to_host(self.host, port=self.port)
    defer tcp.close()
    let session : Session = {
      transport: Clear(tcp),
      pending: b"",
      offset: 0,
      received: 0,
      max_response_bytes: self.max_response_bytes,
      max_line_bytes: self.max_line_bytes,
    }
    match self.security {
      Plaintext => ()
      _ => {
        session.write("STARTTLS")
        expect(session.line(handshake=true), ["OK", "STARTTLS"])
        let trust = match self.security {
          TlsCaFile(path) => @tls.CustomPemFile(path)
          _ => @tls.SystemRoot
        }
        let tls = @tls.Tls::client(tcp, host=self.host, trust~)
        session.transport = Secure(tls)
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
    if !list {
      return [session.line()]
    }
    let begin = ["BEGIN", "LIST"] + header
    let end = ["END", "LIST"] + header
    expect(session.line(), begin)
    let rows : Array[Array[String]] = []
    while true {
      let row = session.line()
      if row == end {
        return rows
      }
      if rows.length() >= self.max_rows {
        raise LimitExceeded("rows")
      }
      if row.length() != header.length() + 2 {
        raise Protocol("invalid list row shape")
      }
      for i in 0..<header.length() {
        if row[i] != header[i] {
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
  rows.map(row => {
    match row {
      ["UPS", name, description] => { name, description, }
      _ => raise Protocol("invalid UPS list row")
    }
  })
}

///|
pub async fn Client::list_vars(self : Client, ups : String) -> Array[Variable] {
  let rows = self.query("LIST VAR " + quote_argument(ups), ["VAR", ups], true)
  rows.map(row => {
    match row {
      ["VAR", device, name, value] if device == ups => { name, value, }
      _ => raise Protocol("invalid variable list row")
    }
  })
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
    ["VAR", device, key, value] if device == ups && key == name => value
    _ => raise Protocol("invalid variable response")
  }
}

///|
/// Read the configured UPS description (or the server's "Unavailable" text).
pub async fn Client::get_ups_description(self : Client, ups : String) -> String {
  let rows = self.query("GET UPSDESC " + quote_argument(ups), [], false)
  match rows[0] {
    ["UPSDESC", device, description] if device == ups => description
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
    ["DESC", device, key, description] if device == ups && key == name =>
      description
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
  if row.length() < 3 || row[0] != "TYPE" || row[1] != ups || row[2] != name {
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
