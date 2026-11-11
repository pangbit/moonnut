///|
/// A scoped LIST iterator. Only use inside Session::with_list; next calls are
/// serialized. Rows include the echoed query tokens and all returned fields.
pub struct ListReader {
  priv session : Session
  priv query : Array[String]
  priv mutex : @async.Mutex
  priv mut active : Bool
  priv mut done : Bool
  priv mut rows : Int32
}

///|
fn expect_prefix(
  tokens : Array[String],
  wanted : Array[String],
) -> Unit raise NutError {
  if tokens.length() < wanted.length() {
    raise Protocol("response does not match request")
  }
  for i in 0..<wanted.length() {
    if !tokens[i].equal_ignore_ascii_case(wanted[i]) {
      raise Protocol("response does not match request")
    }
  }
}

///|
/// Read one row or None at END LIST. Matches libupsclient prefix checks:
/// start/row echoes ignore ASCII case; uppercase END LIST ends the iteration
/// without checking trailing tokens. Any failed read closes this session.
pub async fn ListReader::next(self : ListReader) -> Array[String]? {
  self.mutex.acquire()
  defer self.mutex.release()
  if !self.active {
    raise ConnectionClosed
  }
  if self.done {
    return None
  }
  if self.session.is_closed() {
    raise ConnectionClosed
  }
  let mut complete = false
  defer (if !complete { self.session.close() })
  let row = self.session.line()
  if row.length() >= 2 && row[0] == "END" && row[1] == "LIST" {
    self.done = true
    complete = true
    return None
  }
  expect_prefix(row, self.query)
  if self.rows >= self.session.max_rows {
    raise LimitExceeded("rows")
  }
  self.rows += 1
  complete = true
  Some(row)
}

///|
/// Stream a generic LIST query (for example ["VAR", "demo"]) while holding the
/// session lock. Arguments are encoded; no control command can be submitted.
/// The callback must not issue another request on this same Session. Returning
/// early, callback failure, cancellation or a read error closes an unfinished
/// stream. A complete server error before BEGIN LIST leaves the session usable.
/// Existing typed list methods retain their stricter framing and buffered API.
pub async fn[T] Session::with_list(
  self : Session,
  query : Array[String],
  run : async (ListReader) -> T,
) -> T {
  if query.is_empty() {
    raise NutError::InvalidArgument("empty list query")
  }
  // Copy caller-owned arguments before suspension and validate before writing.
  let query = query.copy()
  let command = "LIST " +
    query
    .map(argument => {
      let encoded = quote_argument(argument)
      if argument.is_empty() || argument.contains(" ") {
        encoded
      } else {
        encoded[1:encoded.length() - 1].to_owned()
      }
    })
    .join(" ")
  with_optional_timeout(self.timeout_ms, () => {
    self.mutex.acquire()
    defer self.mutex.release()
    if self.is_closed() {
      raise ConnectionClosed
    }
    let reader : ListReader = {
      session: self,
      query,
      mutex: @async.Mutex(),
      active: true,
      done: false,
      rows: 0,
    }
    let mut reusable = false
    defer {
      reader.active = false
      if !reader.done && !reusable {
        self.close()
      }
    }
    self.received = 0
    self.write(command)
    let start = self.line() catch {
      Server(_) as error => {
        reusable = true
        raise error
      }
      error => raise error
    }
    expect_prefix(start, ["BEGIN", "LIST"] + query)
    run(reader)
  })
}
