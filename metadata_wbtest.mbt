///|
async test "UPS and variable descriptions preserve quoted and unavailable text" {
  fixture(
    "UPSDESC lab \"Desk \\\"A\\\" 电源\"\r\n",
    expected="GET UPSDESC \"lab\"\n",
    fragmented=true,
    client => assert_eq(client.get_ups_description("lab"), "Desk \"A\" 电源"),
  )
  fixture(
    "DESC lab ups.status \"UPS status\"\n",
    expected="GET DESC \"lab\" \"ups.status\"\n",
    client => {
      assert_eq(client.get_var_description("lab", "ups.status"), "UPS status")
    },
  )
  fixture(
    "DESC lab ups.status \"Unavailable\"\n",
    expected="GET DESC \"lab\" \"ups.status\"\n",
    client => {
      assert_eq(client.get_var_description("lab", "ups.status"), "Unavailable")
    },
  )
}

///|
async test "type metadata preserves multiple unknown and omitted tokens" {
  for
    (suffix, expected_types) in [
      (" RW STRING:32", ["RW", "STRING:32"]),
      (" ENUM NUMBER", ["ENUM", "NUMBER"]),
      (" RW RANGE NUMBER", ["RW", "RANGE", "NUMBER"]),
      (" FUTURE", ["FUTURE"]),
      ("", []),
    ] {
    fixture(
      "TYPE lab ups.status" + suffix + "\n",
      expected="GET TYPE \"lab\" \"ups.status\"\n",
      client => {
        assert_eq(client.get_var_type("lab", "ups.status"), expected_types)
      },
    )
  }
}

///|
async test "metadata rejects mismatched identifiers and malformed response shapes" {
  for
    response in [
      "UPSDESC other \"Desk UPS\"\n", "UPSDESC lab\n", "UPSDESC lab x extra\n",
    ] {
    fixture(response, expected="GET UPSDESC \"lab\"\n", client => {
      let rejected = try {
        ignore(client.get_ups_description("lab"))
        false
      } catch {
        Protocol(_) => true
        err => raise err
      }
      assert_true(rejected)
    })
  }
  for
    response in [
      "DESC other ups.status x\n", "DESC lab other x\n", "DESC lab ups.status\n",
      "DESC lab ups.status x extra\n",
    ] {
    fixture(response, expected="GET DESC \"lab\" \"ups.status\"\n", client => {
      let rejected = try {
        ignore(client.get_var_description("lab", "ups.status"))
        false
      } catch {
        Protocol(_) => true
        err => raise err
      }
      assert_true(rejected)
    })
  }
  for
    response in [
      "TYPE other ups.status NUMBER\n", "TYPE lab other NUMBER\n", "TYPE lab\n",
      "VAR lab ups.status NUMBER\n",
    ] {
    fixture(response, expected="GET TYPE \"lab\" \"ups.status\"\n", client => {
      let rejected = try {
        ignore(client.get_var_type("lab", "ups.status"))
        false
      } catch {
        Protocol(_) => true
        err => raise err
      }
      assert_true(rejected)
    })
  }
}

///|
async test "metadata preserves canonical errors and shared response limits" {
  fixture("ERR UNKNOWN-UPS\n", expected="GET UPSDESC \"missing\"\n", client => {
    let rejected = try {
      ignore(client.get_ups_description("missing"))
      false
    } catch {
      Server("UNKNOWN-UPS") => true
      err => raise err
    }
    assert_true(rejected)
  })
  fixture(
    "ERR VAR-NOT-SUPPORTED\n",
    expected="GET DESC \"lab\" \"missing\"\n",
    client => {
      let rejected = try {
        ignore(client.get_var_description("lab", "missing"))
        false
      } catch {
        Server("VAR-NOT-SUPPORTED") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
  fixture(
    "TYPE lab ups.status RW STRING:32\n",
    expected="GET TYPE \"lab\" \"ups.status\"\n",
    max_line_bytes=16,
    client => {
      let rejected = try {
        ignore(client.get_var_type("lab", "ups.status"))
        false
      } catch {
        LimitExceeded("line") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
}
