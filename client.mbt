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
/// Connection configuration. Direct read methods use fresh connections;
/// connect/with_session provide an explicit persistent Session.
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
/// Open a persistent connection and submit any configured credentials.
/// Receiving OK does not establish their validity or grant LOGIN permission.
pub async fn Client::connect(self : Client) -> Session {
  with_optional_timeout(self.timeout_ms, () => {
    let tcp = @async.with_timeout(self.connect_timeout_ms, () => {
      @socket.Tcp::connect_to_host(self.host, port=self.port)
    })
    let session : Session = {
      tcp,
      mutex: @async.Mutex(),
      closed: false,
      timeout_ms: self.timeout_ms,
      max_rows: self.max_rows,
      transport: Clear(tcp),
      pending: b"",
      offset: 0,
      received: 0,
      max_response_bytes: self.max_response_bytes,
      max_line_bytes: self.max_line_bytes,
      read_timeout_ms: self.read_timeout_ms,
    }
    let mut ready = false
    defer (if !ready { session.close() })
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
    match (self.username, self.password) {
      (Some(user), Some(pass)) => {
        session.set_username(user)
        session.set_password(pass)
      }
      _ => ()
    }
    ready = true
    session
  })
}

///|
/// Close the connection on return, error or cancellation. No implicit LOGIN,
/// reconnection or replay. timeout_ms, if supplied, caps the whole callback.
pub async fn[T] Client::with_session(
  self : Client,
  run : async (Session) -> T,
) -> T {
  with_optional_timeout(self.timeout_ms, () => {
    let session = self.connect()
    defer session.close()
    run(session)
  })
}

///|
pub async fn Client::list_ups(self : Client) -> Array[Ups] {
  self.with_session(session => session.list_ups())
}

///|
pub async fn Client::list_vars(self : Client, ups : String) -> Array[Variable] {
  ignore(quote_argument(ups))
  self.with_session(session => session.list_vars(ups))
}

///|
pub async fn Client::get_var(
  self : Client,
  ups : String,
  name : String,
) -> String {
  ignore(quote_argument(ups))
  ignore(quote_argument(name))
  self.with_session(session => session.get_var(ups, name))
}

///|
pub async fn Client::get_ups_description(self : Client, ups : String) -> String {
  ignore(quote_argument(ups))
  self.with_session(session => session.get_ups_description(ups))
}

///|
pub async fn Client::get_var_description(
  self : Client,
  ups : String,
  name : String,
) -> String {
  ignore(quote_argument(ups))
  ignore(quote_argument(name))
  self.with_session(session => session.get_var_description(ups, name))
}

///|
pub async fn Client::get_var_type(
  self : Client,
  ups : String,
  name : String,
) -> Array[String] {
  ignore(quote_argument(ups))
  ignore(quote_argument(name))
  self.with_session(session => session.get_var_type(ups, name))
}

///|
pub async fn Client::list_rw(self : Client, ups : String) -> Array[Variable] {
  ignore(quote_argument(ups))
  self.with_session(session => session.list_rw(ups))
}

///|
pub async fn Client::list_enum(
  self : Client,
  ups : String,
  name : String,
) -> Array[String] {
  ignore(quote_argument(ups))
  ignore(quote_argument(name))
  self.with_session(session => session.list_enum(ups, name))
}

///|
pub async fn Client::list_range(
  self : Client,
  ups : String,
  name : String,
) -> Array[VariableRange] {
  ignore(quote_argument(ups))
  ignore(quote_argument(name))
  self.with_session(session => session.list_range(ups, name))
}

///|
pub async fn Client::list_commands(
  self : Client,
  ups : String,
) -> Array[String] {
  ignore(quote_argument(ups))
  self.with_session(session => session.list_commands(ups))
}

///|
pub async fn Client::get_command_description(
  self : Client,
  ups : String,
  command : String,
) -> String {
  ignore(quote_argument(ups))
  ignore(quote_argument(command))
  self.with_session(session => session.get_command_description(ups, command))
}

///|
pub async fn Client::get_num_logins(self : Client, ups : String) -> Int32 {
  ignore(quote_argument(ups))
  self.with_session(session => session.get_num_logins(ups))
}

///|
pub async fn Client::list_clients(self : Client, ups : String) -> Array[String] {
  ignore(quote_argument(ups))
  self.with_session(session => session.list_clients(ups))
}

///|
pub async fn Client::get_server_version(self : Client) -> String {
  self.with_session(session => session.get_server_version())
}

///|
pub async fn Client::get_net_version(self : Client) -> String {
  self.with_session(session => session.get_net_version())
}

///|
pub async fn Client::get_protocol_version(self : Client) -> String {
  self.with_session(session => session.get_protocol_version())
}

///|
pub async fn Client::get_help(self : Client) -> String {
  self.with_session(session => session.get_help())
}
