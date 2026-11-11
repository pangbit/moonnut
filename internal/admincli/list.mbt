///|
async fn list_commands(session : @moonnut.Session, ups : String) -> Unit {
  let names = session.list_commands(ups)
  println("Instant commands supported on UPS [" + ups + "]:\n")
  for name in names {
    let desc = Some(session.get_command_description(ups, name)) catch {
      _ => None
    }
    println(
      name +
      (match desc {
        Some(text) => " - " + text
        None => ""
      }),
    )
  }
}

///|
async fn enumeration(
  session : @moonnut.Session,
  ups : String,
  name : String,
  kind : String,
  length : Int64,
) -> Unit {
  let value = session.get_var(ups, name)
  let values = session.list_enum(ups, name)
  println("Type: ENUM" + (if kind.is_empty() { "" } else { " " + kind }))
  if kind == "STRING" {
    println("Maximum length: " + length.to_string())
  }
  for option in values {
    println(
      "Option: \"" +
      option +
      "\"" +
      (if option == value { " SELECTED" } else { "" }),
    )
  }
}

///|
async fn variable_type(
  session : @moonnut.Session,
  ups : String,
  name : String,
) -> Unit {
  let types = session.get_var_type(ups, name) catch {
    _ => {
      println("Unknown type")
      return
    }
  }
  let mut is_enum = false
  for kind in types {
    if kind.equal_ignore_ascii_case("ENUM") {
      is_enum = true
      continue
    }
    if kind.equal_ignore_ascii_case("RANGE") {
      let value = integer_prefix(session.get_var(ups, name))
      let ranges = session.list_range(ups, name)
      println("Type: RANGE NUMBER")
      for range in ranges {
        let low = integer_prefix(range.min)
        let high = integer_prefix(range.max)
        println(
          "Option: \"" +
          low.to_string() +
          "-" +
          high.to_string() +
          "\"" +
          (if value >= low && value <= high { " SELECTED" } else { "" }),
        )
      }
      return
    }
    if kind.length() >= 7 && kind[:7].equal_ignore_ascii_case("STRING:") {
      let length = integer_prefix(kind[7:].to_owned())
      if is_enum {
        enumeration(session, ups, name, "STRING", length)
      } else {
        let value = session.get_var(ups, name)
        println("Type: STRING")
        println("Maximum length: " + length.to_string())
        println("Value: " + value)
      }
      return
    }
    if kind.equal_ignore_ascii_case("NUMBER") {
      if is_enum {
        enumeration(session, ups, name, "NUMBER", 0L)
      } else {
        let value = session.get_var(ups, name)
        println("Type: NUMBER")
        println("Value: " + value)
      }
      return
    }
    if !kind.equal_ignore_ascii_case("RW") {
      println("Type: " + kind + " (unrecognized)")
    }
  }
  if is_enum {
    enumeration(session, ups, name, "", 0L)
  }
}

///|
async fn list_writable(session : @moonnut.Session, ups : String) -> Unit {
  let variables = session.list_rw(ups)
  for variable in variables {
    println("[" + variable.name + "]")
    let description = session.get_var_description(ups, variable.name) catch {
      _ => "Description unavailable"
    }
    println(description)
    variable_type(session, ups, variable.name)
    println("")
  }
}
