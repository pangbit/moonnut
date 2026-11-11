///|
async test "server information preserves raw text and protocol errors" {
  fixture("Network UPS Tools  upsd 2.8.4 # \"build\"\r\n", expected="VER\n", client => {
    assert_eq(
      client.get_server_version(),
      "Network UPS Tools  upsd 2.8.4 # \"build\"",
    )
  })
  fixture("1.3\n", expected="NETVER\n", client => {
    assert_eq(client.get_net_version(), "1.3")
  })
  fixture("1.3\n", expected="PROTVER\n", client => {
    assert_eq(client.get_protocol_version(), "1.3")
  })
  fixture("Commands: HELP VER\n", expected="HELP\n", client => {
    assert_eq(client.get_help(), "Commands: HELP VER")
  })
  fixture("ERR FEATURE-NOT-SUPPORTED\n", expected="NETVER\n", client => {
    let rejected = try {
      ignore(client.get_net_version())
      false
    } catch {
      Server("FEATURE-NOT-SUPPORTED") => true
      err => raise err
    }
    assert_true(rejected)
  })
}

///|
async test "login counts and client addresses are read without LOGIN" {
  fixture("NUMLOGINS lab 2\n", expected="GET NUMLOGINS \"lab\"\n", client => {
    assert_eq(client.get_num_logins("lab"), 2)
  })
  fixture(
    "BEGIN LIST CLIENT lab\nCLIENT lab 127.0.0.1\nCLIENT lab ::1\nCLIENT lab 127.0.0.1\nEND LIST CLIENT lab\n",
    expected="LIST CLIENT \"lab\"\n",
    client => {
      assert_eq(client.list_clients("lab"), ["127.0.0.1", "::1", "127.0.0.1"])
    },
  )
  for value in ["-1", "2147483648", "2x", "\"\""] {
    fixture(
      "NUMLOGINS lab " + value + "\n",
      expected="GET NUMLOGINS \"lab\"\n",
      client => {
        let rejected = try {
          ignore(client.get_num_logins("lab"))
          false
        } catch {
          Protocol(_) => true
          err => raise err
        }
        assert_true(rejected)
      },
    )
  }
}

///|
async test "echoed query tokens follow libupsclient ASCII case matching" {
  fixture(
    "VAR unused server.version \"2.8.4\"\n",
    expected="GET VAR \"unused\" \"SERVER.VERSION\"\n",
    client => assert_eq(client.get_var("unused", "SERVER.VERSION"), "2.8.4"),
  )
  fixture(
    "begin list client LAB\nclient lab 127.0.0.1\nEND LIST CLIENT Lab\n",
    expected="LIST CLIENT \"lab\"\n",
    client => assert_eq(client.list_clients("lab"), ["127.0.0.1"]),
  )
}

///|
async test "read timeout restarts for each transport read without an overall deadline" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        ignore(tcp.read_until("\n"))
        for part in ["BEGIN ", "LIST ", "UPS\n", "END ", "LIST ", "UPS\n"] {
          @async.sleep(40)
          tcp.write(part)
        }
      })
      let client = Client::new(
        "127.0.0.1",
        port=server.addr.port(),
        security=Plaintext,
        read_timeout_ms=150,
      )
      assert_eq(client.list_ups(), [])
    })
  })
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
      read_timeout_ms=20,
    )
    let expired = try {
      ignore(client.list_ups())
      false
    } catch {
      @async.TimeoutError => true
      err => raise err
    }
    assert_true(expired)
  })
}
