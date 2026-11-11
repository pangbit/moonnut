///|
async fn discover(client : Client, kind : String) -> Unit {
  match kind {
    "RW" => ignore(client.list_rw("lab"))
    "ENUM" => ignore(client.list_enum("lab", "v"))
    "RANGE" => ignore(client.list_range("lab", "v"))
    "CMD" => ignore(client.list_commands("lab"))
    _ => abort("unknown discovery fixture")
  }
}

///|
async test "discovery validates command specific rows and preserves strings" {
  fixture(
    "BEGIN LIST RW lab\nRW lab ups.id \"020\"\nRW lab note \"\"\nEND LIST RW lab\n",
    expected="LIST RW \"lab\"\n",
    client => {
      assert_eq(client.list_rw("lab"), [
        { name: "ups.id", value: "020", },
        { name: "note", value: "", },
      ])
    },
  )
  fixture(
    "BEGIN LIST ENUM lab v\r\nENUM lab v \"Eco mode\"\r\nENUM lab v \"\"\r\nENUM lab v \"电源 \\\"A\\\"\"\r\nEND LIST ENUM lab v\r\n",
    expected="LIST ENUM \"lab\" \"v\"\n",
    fragmented=true,
    client => {
      assert_eq(client.list_enum("lab", "v"), ["Eco mode", "", "电源 \"A\""])
    },
  )
  fixture(
    "BEGIN LIST RANGE lab v\nRANGE lab v \"-1.50\" \"0\"\nRANGE lab v \"002\" \"10.25\"\nEND LIST RANGE lab v\n",
    expected="LIST RANGE \"lab\" \"v\"\n",
    client => {
      assert_eq(client.list_range("lab", "v"), [
        { min: "-1.50", max: "0", },
        { min: "002", max: "10.25", },
      ])
    },
  )
  fixture(
    "BEGIN LIST CMD lab\nCMD lab test.battery.start.quick\nCMD lab load.off\nEND LIST CMD lab\n",
    expected="LIST CMD \"lab\"\n",
    client => {
      assert_eq(client.list_commands("lab"), [
        "test.battery.start.quick", "load.off",
      ])
    },
  )
}

///|
async test "discovery accepts empty lists" {
  for
    (kind, suffix, args) in [
      ("RW", " lab", " \"lab\""),
      ("CMD", " lab", " \"lab\""),
      ("ENUM", " lab v", " \"lab\" \"v\""),
      ("RANGE", " lab v", " \"lab\" \"v\""),
    ] {
    fixture(
      "BEGIN LIST " + kind + suffix + "\nEND LIST " + kind + suffix + "\n",
      expected="LIST " + kind + args + "\n",
      client => discover(client, kind),
    )
  }
}

///|
async test "discovery rejects wrong arity identifiers commands and boundaries" {
  for
    (kind, suffix, args, rows) in [
      (
        "RW",
        " lab",
        " \"lab\"",
        ["RW lab v", "RW lab v x extra", "RW other v x", "VAR lab v x"],
      ),
      (
        "CMD",
        " lab",
        " \"lab\"",
        [
          "CMD lab", "CMD lab load.off description", "CMD other load.off", "RW lab load.off",
        ],
      ),
      (
        "ENUM",
        " lab v",
        " \"lab\" \"v\"",
        [
          "ENUM lab v", "ENUM lab v x extra", "ENUM other v x", "ENUM lab other x",
          "RANGE lab v x",
        ],
      ),
      (
        "RANGE",
        " lab v",
        " \"lab\" \"v\"",
        [
          "RANGE lab v 1", "RANGE lab v 1 2 extra", "RANGE other v 1 2", "RANGE lab other 1 2",
          "ENUM lab v 1 2",
        ],
      ),
    ] {
    let begin = "BEGIN LIST " + kind + suffix + "\n"
    let end = "END LIST " + kind + suffix + "\n"
    let invalid = rows.map(row => begin + row + "\n" + end)
    invalid.push("BEGIN LIST UPS\n")
    invalid.push(begin + "END LIST " + kind + " wrong\n")
    for response in invalid {
      fixture(response, expected="LIST " + kind + args + "\n", client => {
        let rejected = try {
          discover(client, kind)
          false
        } catch {
          Protocol(_) => true
          err => raise err
        }
        assert_true(rejected)
      })
    }
  }
}

///|
async test "discovery propagates server errors EOF and shared limits" {
  for
    (kind, args, code) in [
      ("RW", " \"lab\"", "UNKNOWN-UPS"),
      ("ENUM", " \"lab\" \"v\"", "NOT-ENUM"),
      ("RANGE", " \"lab\" \"v\"", "NOT-RANGE"),
      ("CMD", " \"lab\"", "ACCESS-DENIED"),
    ] {
    fixture("ERR " + code + "\n", expected="LIST " + kind + args + "\n", client => {
      let rejected = try {
        discover(client, kind)
        false
      } catch {
        Server(actual) => actual == code
        err => raise err
      }
      assert_true(rejected)
    })
  }
  fixture(
    "BEGIN LIST CMD lab\nCMD lab load.off\n",
    expected="LIST CMD \"lab\"\n",
    client => {
      let rejected = try {
        ignore(client.list_commands("lab"))
        false
      } catch {
        UnexpectedEof => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
  fixture(
    "BEGIN LIST RANGE lab v\nRANGE lab v 1 2\nRANGE lab v 4 5\nEND LIST RANGE lab v\n",
    expected="LIST RANGE \"lab\" \"v\"\n",
    max_rows=1,
    client => {
      let rejected = try {
        ignore(client.list_range("lab", "v"))
        false
      } catch {
        LimitExceeded("rows") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
  fixture(
    "BEGIN LIST CMD lab\nCMD lab load.off\nEND LIST CMD lab\n",
    expected="LIST CMD \"lab\"\n",
    max_line_bytes=32,
    max_response_bytes=32,
    client => {
      let rejected = try {
        ignore(client.list_commands("lab"))
        false
      } catch {
        LimitExceeded("response") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
}

///|
async test "command description preserves text and validates identity" {
  fixture(
    "CMDDESC lab load.off \"Unavailable\"\n",
    expected="GET CMDDESC \"lab\" \"load.off\"\n",
    client => {
      assert_eq(
        client.get_command_description("lab", "load.off"),
        "Unavailable",
      )
    },
  )
  for
    response in [
      "CMDDESC other load.off x\n", "CMDDESC lab other x\n", "CMDDESC lab load.off\n",
      "CMDDESC lab load.off x extra\n", "DESC lab load.off x\n",
    ] {
    fixture(response, expected="GET CMDDESC \"lab\" \"load.off\"\n", client => {
      let rejected = try {
        ignore(client.get_command_description("lab", "load.off"))
        false
      } catch {
        Protocol(_) => true
        err => raise err
      }
      assert_true(rejected)
    })
  }
  fixture(
    "ERR CMD-NOT-SUPPORTED\n",
    expected="GET CMDDESC \"lab\" \"missing\"\n",
    client => {
      let rejected = try {
        ignore(client.get_command_description("lab", "missing"))
        false
      } catch {
        Server("CMD-NOT-SUPPORTED") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
}

///|
async test "discovery rejects command injection before connecting" {
  let client = Client::new("unused.example.invalid", security=Plaintext)
  for kind in ["RW", "ENUM", "RANGE", "CMD", "CMDDESC"] {
    let rejected = try {
      match kind {
        "RW" => ignore(client.list_rw("lab\nSET VAR lab x 1"))
        "ENUM" => ignore(client.list_enum("lab", "v\r\nINSTCMD lab load.off"))
        "RANGE" => ignore(client.list_range("lab\n", "v"))
        "CMD" => ignore(client.list_commands("lab\n"))
        _ => ignore(client.get_command_description("lab", "load.off\n"))
      }
      false
    } catch {
      InvalidArgument(_) => true
      err => raise err
    }
    assert_true(rejected)
  }
}
