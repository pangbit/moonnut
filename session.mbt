///|
priv enum Transport {
  Clear(@socket.Tcp)
  Secure(@tls.Tls)
}

///|
/// A persistent NUT connection. Call close() or use Client::with_session.
/// Queries are serialized; cancellation during a request closes the stream.
pub struct Session {
  priv tcp : @socket.Tcp
  priv mutex : @async.Mutex
  priv mut closed : Bool
  priv timeout_ms : Int32?
  priv max_rows : Int32
  priv mut transport : Transport
  priv mut pending : Bytes
  priv mut offset : Int32
  priv mut received : Int32
  priv max_response_bytes : Int32
  priv max_line_bytes : Int32
  priv read_timeout_ms : Int32
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
/// Consume one complete reply while holding the connection lock. A server
/// error before the list begins is a complete response; an incomplete list,
/// transport failure, timeout or cancellation makes the stream unusable.
async fn Session::query(
  self : Session,
  command : String,
  header : Array[String],
  list : Bool,
  row_values~ : Int32 = 2,
  raw~ : Bool = false,
  check_errors~ : Bool = true,
  close_after~ : Bool = false,
) -> Array[Array[String]] {
  with_optional_timeout(self.timeout_ms, () => {
    self.mutex.acquire()
    defer self.mutex.release()
    if self.closed {
      raise ConnectionClosed
    }
    let mut complete = false
    let mut in_list = false
    defer (if close_after || !complete { self.close() })
    self.received = 0
    let result = try {
      self.write(command)
      if raw {
        let reply = self.raw_line()
        if reply.is_empty() {
          raise Protocol("empty response")
        }
        if check_errors && reply.has_prefix("ERR ") {
          check_server(parse_line(reply))
        }
        [[reply]]
      } else if !list {
        [self.line()]
      } else {
        expect_echo(self.line(), ["BEGIN", "LIST"] + header)
        in_list = true
        let end = ["END", "LIST"] + header
        let rows : Array[Array[String]] = []
        while true {
          let row = self.line()
          if row.length() == end.length() && row[0] == "END" && row[1] == "LIST" {
            expect_echo(row, end)
            break
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
        }
        rows
      }
    } catch {
      Server(_) as error => {
        complete = !in_list
        raise error
      }
      error => raise error
    }
    complete = true
    result
  })
}

///|
/// Close immediately without protocol IO. Safe to call more than once.
pub fn Session::close(self : Session) -> Unit {
  if !self.closed {
    self.closed = true
    match self.transport {
      Secure(tls) => tls.close()
      _ => ()
    }
    self.tcp.close()
  }
}

///|
pub fn Session::is_closed(self : Session) -> Bool {
  self.closed
}

///|
/// Encryption status only; unverified TLS does not authenticate the server.
pub fn Session::is_tls(self : Session) -> Bool {
  !self.closed && self.transport is Secure(_)
}

///|
pub async fn Session::set_username(self : Session, username : String) -> Unit {
  expect(self.query("USERNAME " + quote_argument(username), [], false)[0], [
    "OK",
  ])
}

///|
pub async fn Session::set_password(self : Session, password : String) -> Unit {
  expect(self.query("PASSWORD " + quote_argument(password), [], false)[0], [
    "OK",
  ])
}

///|
/// Register this connection as a power consumer. This changes NUMLOGINS and
/// LIST CLIENT; it is not a read-only credential probe.
pub async fn Session::login(self : Session, ups : String) -> Unit {
  expect(self.query("LOGIN " + quote_argument(ups), [], false)[0], ["OK"])
}

///|
/// Read the server's Goodbye response and close even if LOGOUT fails.
pub async fn Session::logout(self : Session) -> Unit {
  expect(self.query("LOGOUT", [], false, close_after=true)[0], ["OK", "Goodbye"])
}

///|
pub async fn Session::set_tracking(self : Session, enabled : Bool) -> Unit {
  expect(
    self.query(
      "SET TRACKING " + (if enabled { "ON" } else { "OFF" }),
      [],
      false,
    )[0],
    ["OK"],
  )
}

///|
pub async fn Session::get_tracking(self : Session) -> Bool {
  match self.query("GET TRACKING", [], false)[0] {
    ["ON"] => true
    ["OFF"] => false
    _ => raise Protocol("invalid tracking state")
  }
}

///|
#derive(Eq, @debug.Debug)
pub(all) enum TrackingStatus {
  Pending
  Success
  Unknown
  InvalidArgument
  Failed
}

///|
/// Query an ID without issuing or retrying any operation. ERR UNKNOWN, FAILED
/// and INVALID-ARGUMENT are tracking outcomes; other server errors still raise.
pub async fn Session::get_tracking_status(
  self : Session,
  id : String,
) -> TrackingStatus {
  let reply = self.query(
      "GET TRACKING " + quote_argument(id),
      [],
      false,
      raw=true,
      check_errors=false,
    )[0][0]
  match reply {
    "PENDING" => Pending
    "SUCCESS" => Success
    "ERR UNKNOWN" => Unknown
    "ERR INVALID-ARGUMENT" => TrackingStatus::InvalidArgument
    "ERR FAILED" => Failed
    _ => {
      check_server(parse_line(reply))
      raise Protocol("invalid tracking result")
    }
  }
}

///|
pub extend TrackingStatus with Eq::{equal, not_equal}

///|
pub extend TrackingStatus with @debug.Debug::{to_repr}
