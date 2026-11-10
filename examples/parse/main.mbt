///|
/// This offline example never opens a network connection.
fn main {
  let fields = @moonnut.parse_line("VAR demo ups.status \"OL CHRG\"") catch {
    _ => []
  }
  for field in fields {
    println(field)
  }
}
