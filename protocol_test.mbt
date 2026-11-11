///|
test "NUT quoted values and escaping" {
  assert_eq(@moonnut.parse_line("VAR ups ups.status \"OL CHRG\""), [
    "VAR", "ups", "ups.status", "OL CHRG",
  ])
  assert_eq(@moonnut.parse_line("UPS a \"Outlet \\#3 \\\"A\\\" C:\\\\ups\""), [
    "UPS", "a", "Outlet #3 \"A\" C:\\ups",
  ])
}

///|
test "parseconf delimiters are not shell or JSON" {
  assert_eq(@moonnut.parse_line("\"one\"two a=b 'two words' # ignored"), [
    "one", "two", "a", "=", "b", "'two", "words'",
  ])
  assert_eq(@moonnut.parse_line("a\\ b \\n \"\" \"#text\""), [
    "a b", "n", "", "#text",
  ])
}

///|
test "quote round trip" {
  for value in ["", "ups", "line space", "x=y", "#x", "a\\b", "a\"b", "设备"] {
    assert_eq(@moonnut.parse_line(@moonnut.quote_argument(value)), [value])
  }
}

///|
test "reject incomplete and injected lines" {
  for
    value in [
      "\"unfinished", "escape\\", "line\nbreak", "line\rbreak", "x\u0000",
    ] {
    let rejected = try {
      ignore(@moonnut.parse_line(value))
      false
    } catch {
      @moonnut.NutError::Protocol(_) => true
      err => raise err
    }
    assert_true(rejected)
  }
  for value in ["ups\nFSD ups", "a\rb", "x\t", "\u007f"] {
    let rejected = try {
      ignore(@moonnut.quote_argument(value))
      false
    } catch {
      @moonnut.NutError::InvalidArgument(_) => true
      err => raise err
    }
    assert_true(rejected)
  }
}

///|
test "plaintext credentials follow NUT compatibility policy" {
  ignore(
    @moonnut.Client::new(
      "localhost",
      security=@moonnut.Plaintext,
      username="fixture",
      password="fixture",
    ),
  )
}

///|
test "validate paired credentials and bounds" {
  let missing = try {
    ignore(@moonnut.Client::new("localhost", username="fixture"))
    false
  } catch {
    @moonnut.NutError::InvalidArgument(_) => true
    err => raise err
  }
  assert_true(missing)
  for port in [-1, 0, 65536] {
    let rejected = try {
      ignore(@moonnut.Client::new("localhost", port~))
      false
    } catch {
      @moonnut.NutError::InvalidArgument(_) => true
      err => raise err
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(@moonnut.Client::new("localhost", timeout_ms=0))
    false
  } catch {
    @moonnut.NutError::InvalidArgument(_) => true
    err => raise err
  }
  assert_true(rejected)
}
