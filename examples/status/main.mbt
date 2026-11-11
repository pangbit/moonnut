///|
/// Status is a space-separated set of exact, case-sensitive flags, not one enum.
/// Keep unknown flags and the original value; do not infer a safe shutdown policy.
fn status_flags(value : String) -> Array[String] {
  value
  .split(" ")
  .filter(part => !part.is_empty())
  .map(part => part.to_owned())
  .to_array()
}

///|
/// Offline interpretation only: pass a value already obtained from get_var.
fn main {
  let args = @env.args()
  let raw = if args.length() > 1 { args[1] } else { "OL CHRG" }
  let flags = status_flags(raw)
  println("raw=" + raw)
  println("flags=" + flags.join(","))
  println("online=" + flags.contains("OL").to_string())
  println("on_battery=" + flags.contains("OB").to_string())
  println("low_battery=" + flags.contains("LB").to_string())
  println("charging=" + flags.contains("CHRG").to_string())
  println(
    "Illustration only: empty, unknown or stale status is not proof of healthy power.",
  )
}
