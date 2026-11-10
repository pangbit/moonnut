///|
async fn fixture(
  response : String,
  run : async (Client) -> Unit,
  security~ : Security = Plaintext,
  expected~ : String = "LIST UPS\n",
  max_line_bytes~ : Int32 = 65536,
  max_rows~ : Int32 = 4096,
  max_response_bytes~ : Int32 = 4194304,
  fragmented~ : Bool = false,
) -> Unit {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        assert_eq(tcp.read_until("\n").map(line => line + "\n"), Some(expected))
        if fragmented {
          for ch in response.iter() {
            tcp.write(ch.to_string())
          }
        } else {
          tcp.write(response)
        }
      })
      run(
        Client::new(
          "127.0.0.1",
          port=server.addr.port(),
          security~,
          max_line_bytes~,
          max_rows~,
          max_response_bytes~,
        ),
      )
    })
  })
}

///|
async test "fragmented lists and CRLF" {
  fixture(
    "BEGIN LIST UPS\r\nUPS lab \"Desk UPS\"\r\nEND LIST UPS\r\n",
    fragmented=true,
    client => {
      let devices = client.list_ups()
      assert_eq(devices.length(), 1)
      assert_eq(devices[0].name, "lab")
      assert_eq(devices[0].description, "Desk UPS")
    },
  )
}

///|
async test "GET VAR validates echoed identifiers" {
  fixture(
    "VAR lab ups.status \"OL CHRG\"\n",
    expected="GET VAR \"lab\" \"ups.status\"\n",
    client => assert_eq(client.get_var("lab", "ups.status"), "OL CHRG"),
  )
  fixture(
    "VAR other ups.status \"OL\"\n",
    expected="GET VAR \"lab\" \"ups.status\"\n",
    client => {
      let rejected = try {
        ignore(client.get_var("lab", "ups.status"))
        false
      } catch {
        Protocol(_) => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
}

///|
async test "LIST VAR validates framing and rows" {
  fixture(
    "BEGIN LIST VAR lab\nVAR lab battery.charge \"100\"\nEND LIST VAR lab\n",
    expected="LIST VAR \"lab\"\n",
    client => {
      let vars = client.list_vars("lab")
      assert_eq(vars.length(), 1)
      assert_eq(vars[0].value, "100")
    },
  )
}

///|
async test "server errors are distinct" {
  fixture("ERR ACCESS-DENIED\n", client => {
    let denied = try {
      ignore(client.list_ups())
      false
    } catch {
      Server("ACCESS-DENIED") => true
      err => raise err
    }
    assert_true(denied)
  })
}

///|
async test "TLS refusal never falls back to plaintext" {
  fixture("ERR FEATURE-NOT-SUPPORTED\n", expected="STARTTLS\n", security=Tls, client => {
    let denied = try {
      ignore(client.list_ups())
      false
    } catch {
      Server("FEATURE-NOT-SUPPORTED") => true
      err => raise err
    }
    assert_true(denied)
  })
}

///|
async test "reject wrong list boundaries and malformed rows" {
  for
    response in [
      "BEGIN LIST VAR lab\n", "BEGIN LIST UPS\nEND LIST VAR lab\n", "BEGIN LIST UPS\nUPS lab\n",
    ] {
    fixture(response, client => {
      let rejected = try {
        ignore(client.list_ups())
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
async test "truncated response and bounded lines" {
  fixture("BEGIN LIST UPS\nUPS lab \"partial", client => {
    let rejected = try {
      ignore(client.list_ups())
      false
    } catch {
      UnexpectedEof => true
      err => raise err
    }
    assert_true(rejected)
  })
  fixture("01234567890123456\n", max_line_bytes=16, client => {
    let rejected = try {
      ignore(client.list_ups())
      false
    } catch {
      LimitExceeded("line") => true
      err => raise err
    }
    assert_true(rejected)
  })
}

///|
async test "bounded row count and response bytes" {
  fixture(
    "BEGIN LIST UPS\nUPS a \"a\"\nUPS b \"b\"\nEND LIST UPS\n",
    max_rows=1,
    client => {
      let rejected = try {
        ignore(client.list_ups())
        false
      } catch {
        LimitExceeded("rows") => true
        err => raise err
      }
      assert_true(rejected)
    },
  )
  fixture(
    "BEGIN LIST UPS\nUPS a \"a\"\nEND LIST UPS\n",
    max_line_bytes=16,
    max_response_bytes=20,
    client => {
      let rejected = try {
        ignore(client.list_ups())
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
async test "whole operation timeout" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      defer tcp.close()
      ignore(tcp.read_until("\n"))
      @async.sleep(100)
    })
    let client = Client::new(
      "127.0.0.1",
      port=server.addr.port(),
      security=Plaintext,
      timeout_ms=20,
    )
    let timed_out = try {
      ignore(client.list_ups())
      false
    } catch {
      @async.TimeoutError => true
      err => raise err
    }
    assert_true(timed_out)
  })
}
