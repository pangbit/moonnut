///|
/// An upsd acknowledgement, not evidence that a driver completed the operation.
#derive(Eq, @debug.Debug)
pub(all) enum CommandReceipt {
  Accepted
  Tracked(String)
}

///|
fn command_receipt(reply : Array[String]) -> CommandReceipt raise {
  match reply {
    ["OK"] => Accepted
    ["OK", "TRACKING", id] if !id.is_empty() => Tracked(id)
    _ => raise Protocol("invalid command acknowledgement")
  }
}

///|
/// Submit one SET VAR. Values are strings; validation belongs to upsd/driver.
/// Never retries. A lost reply leaves the operation's outcome uncertain.
pub async fn Session::set_var(
  self : Session,
  ups : String,
  name : String,
  value : String,
) -> CommandReceipt {
  command_receipt(
    self.query(
      "SET VAR " +
      quote_argument(ups) +
      " " +
      quote_argument(name) +
      " " +
      quote_argument(value),
      [],
      false,
    )[0],
  )
}

///|
/// Submit one INSTCMD, preserving absent versus explicitly empty parameter.
/// Accepted/Tracked acknowledge dispatch, not physical execution or completion.
pub async fn Session::execute_command(
  self : Session,
  ups : String,
  command : String,
  parameter? : String,
) -> CommandReceipt {
  let suffix = match parameter {
    None => ""
    Some(value) => " " + quote_argument(value)
  }
  command_receipt(
    self.query(
      "INSTCMD " + quote_argument(ups) + " " + quote_argument(command) + suffix,
      [],
      false,
    )[0],
  )
}

///|
/// Check PRIMARY permission. Does not implicitly LOGIN or fall back to MASTER.
pub async fn Session::primary(self : Session, ups : String) -> Unit {
  expect(self.query("PRIMARY " + quote_argument(ups), [], false)[0], [
    "OK", "PRIMARY-GRANTED",
  ])
}

///|
/// Explicit legacy MASTER permission check; no fallback or implicit LOGIN.
pub async fn Session::master(self : Session, ups : String) -> Unit {
  expect(self.query("MASTER " + quote_argument(ups), [], false)[0], [
    "OK", "MASTER-GRANTED",
  ])
}

///|
/// Set the server's forced-shutdown flag. Real monitors may act on this flag.
/// An OK is not evidence of device or host shutdown. Never retries.
pub async fn Session::fsd(self : Session, ups : String) -> Unit {
  expect(self.query("FSD " + quote_argument(ups), [], false)[0], [
    "OK", "FSD-SET",
  ])
}

///|
pub extend CommandReceipt with Eq::{equal, not_equal}

///|
pub extend CommandReceipt with @debug.Debug::{to_repr}
