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
pub async fn Session::list_ups(self : Session) -> Array[Ups] {
  let rows = self.query("LIST UPS", ["UPS"], true)
  rows.map(row => { name: row[1], description: row[2], })
}

///|
pub async fn Session::list_vars(
  self : Session,
  ups : String,
) -> Array[Variable] {
  let rows = self.query("LIST VAR " + quote_argument(ups), ["VAR", ups], true)
  rows.map(row => { name: row[2], value: row[3], })
}

///|
pub async fn Session::get_var(
  self : Session,
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
pub async fn Session::get_ups_description(
  self : Session,
  ups : String,
) -> String {
  let rows = self.query("GET UPSDESC " + quote_argument(ups), [], false)
  match rows[0] {
    [kind, device, description] if kind.equal_ignore_ascii_case("UPSDESC") &&
      device.equal_ignore_ascii_case(ups) => description
    _ => raise Protocol("invalid UPS description response")
  }
}

///|
/// Read the server's variable description, which may be localized or unavailable.
pub async fn Session::get_var_description(
  self : Session,
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
pub async fn Session::get_var_type(
  self : Session,
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
pub async fn Session::list_rw(self : Session, ups : String) -> Array[Variable] {
  let rows = self.query("LIST RW " + quote_argument(ups), ["RW", ups], true)
  rows.map(row => { name: row[2], value: row[3], })
}

///|
/// Allowed values in server order. Read the current value separately with get_var.
pub async fn Session::list_enum(
  self : Session,
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
pub async fn Session::list_range(
  self : Session,
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
pub async fn Session::list_commands(
  self : Session,
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
pub async fn Session::get_command_description(
  self : Session,
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
pub async fn Session::get_num_logins(self : Session, ups : String) -> Int32 {
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
pub async fn Session::list_clients(
  self : Session,
  ups : String,
) -> Array[String] {
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
pub async fn Session::get_server_version(self : Session) -> String {
  self.query("VER", [], false, raw=true)[0][0]
}

///|
pub async fn Session::get_net_version(self : Session) -> String {
  self.query("NETVER", [], false, raw=true)[0][0]
}

///|
/// Request PROTVER explicitly; NUT 2.8.4 treats it as a NETVER alias.
pub async fn Session::get_protocol_version(self : Session) -> String {
  self.query("PROTVER", [], false, raw=true)[0][0]
}

///|
/// HELP is informational: NUT omits some supported commands from this response.
pub async fn Session::get_help(self : Session) -> String {
  self.query("HELP", [], false, raw=true)[0][0]
}
