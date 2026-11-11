///|
async fn session_fixture(
  script : Array[(String, String)],
  run : async (Session) -> Unit,
  max_response_bytes~ : Int32 = 4194304,
  max_rows~ : Int32 = 4096,
  connect_timeout_ms~ : Int32 = 10000,
) -> Unit {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
    max_line_bytes=64,
    max_response_bytes~,
    max_rows~,
    connect_timeout_ms~,
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        for (command, reply) in script {
          assert_eq(tcp.read_until("\n"), Some(command))
          tcp.write(reply + "\n")
        }
        assert_eq(tcp.read_some(), None)
      })
      client.with_session(run)
    })
  })
}

///|
async fn expect_session_error(run : async () -> Unit, code : String) -> Unit {
  let seen = try {
    run()
    "no error"
  } catch {
    Server(value) => value
    error => raise error
  }
  assert_eq(seen, code)
}

///|
async test "persistent credentials, tracking and LOGIN survive complete server errors" {
  session_fixture(
    [
      ("GET TRACKING", "OFF"),
      ("SET TRACKING ON", "ERR USERNAME-REQUIRED"),
      ("USERNAME \"fixture\"", "OK"),
      ("SET TRACKING ON", "ERR PASSWORD-REQUIRED"),
      ("PASSWORD \"fixture\"", "OK"),
      ("SET TRACKING ON", "OK"),
      ("GET TRACKING", "ON"),
      ("LOGIN \"demo\"", "OK"),
      ("LOGIN \"demo\"", "ERR ALREADY-LOGGED-IN"),
      ("GET NUMLOGINS \"demo\"", "NUMLOGINS demo 1"),
      (
        "LIST CLIENT \"demo\"", "BEGIN LIST CLIENT demo\nCLIENT demo 127.0.0.1\nEND LIST CLIENT demo",
      ),
      ("LOGOUT", "OK Goodbye"),
    ],
    session => {
      assert_false(session.is_closed())
      assert_false(session.is_tls())
      assert_false(session.get_tracking())
      expect_session_error(
        () => session.set_tracking(true),
        "USERNAME-REQUIRED",
      )
      session.set_username("fixture")
      expect_session_error(
        () => session.set_tracking(true),
        "PASSWORD-REQUIRED",
      )
      session.set_password("fixture")
      session.set_tracking(true)
      assert_true(session.get_tracking())
      session.login("demo")
      expect_session_error(() => session.login("demo"), "ALREADY-LOGGED-IN")
      assert_eq(session.get_num_logins("demo"), 1)
      assert_eq(session.list_clients("demo"), ["127.0.0.1"])
      session.logout()
      assert_true(session.is_closed())
      session.close()
      let closed = try {
        ignore(session.get_tracking())
        false
      } catch {
        ConnectionClosed => true
        error => raise error
      }
      assert_true(closed)
    },
  )
}

///|
async test "tracking outcomes remain distinct from protocol errors" {
  for
    (reply, status) in [
      ("PENDING", TrackingStatus::Pending),
      ("SUCCESS", TrackingStatus::Success),
      ("ERR UNKNOWN", TrackingStatus::Unknown),
      ("ERR INVALID-ARGUMENT", TrackingStatus::InvalidArgument),
      ("ERR FAILED", TrackingStatus::Failed),
    ] {
    session_fixture([("GET TRACKING \"fixture-id\"", reply)], session => {
      assert_eq(session.get_tracking_status("fixture-id"), status)
    })
  }
  session_fixture(
    [
      ("GET TRACKING \"fixture-id\"", "ERR FEATURE-NOT-CONFIGURED"),
      ("GET TRACKING", "OFF"),
    ],
    session => {
      expect_session_error(
        () => ignore(session.get_tracking_status("fixture-id")),
        "FEATURE-NOT-CONFIGURED",
      )
      assert_false(session.get_tracking())
    },
  )
}

///|
async test "response budget resets between requests on the same session" {
  let reply = "Network UPS Tools upsd synthetic fixture"
  session_fixture(
    [("VER", reply), ("VER", reply), ("VER", reply)],
    max_response_bytes=64,
    session => {
      for _ in 0..<3 {
        assert_eq(session.get_server_version(), reply)
      }
    },
  )
}

///|
async test "persistent session serializes concurrent requests" {
  session_fixture(
    [
      ("GET VAR \"demo\" \"alpha\"", "VAR demo alpha A"),
      ("GET VAR \"demo\" \"beta\"", "VAR demo beta B"),
    ],
    session => {
      @async.with_task_group(group => {
        let first = group.spawn(() => session.get_var("demo", "alpha"))
        let second = group.spawn(() => session.get_var("demo", "beta"))
        assert_eq(first.wait(), "A")
        assert_eq(second.wait(), "B")
      })
    },
  )
}

///|
async test "cancelled persistent request closes the stream without replay" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let received = @async.Semaphore(1, initial_value=0)
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        assert_eq(tcp.read_until("\n"), Some("GET TRACKING"))
        received.release()
        assert_eq(tcp.read_some(), None)
      })
      let session = client.connect()
      defer session.close()
      let pending = group.spawn(() => {
        ignore(@async.handle_cancellation(() => session.get_tracking()))
      })
      received.acquire()
      pending.cancel()
      pending.wait()
      assert_true(session.is_closed())
    })
  })
}

///|
async test "incomplete list closes a persistent session" {
  session_fixture(
    [("LIST UPS", "BEGIN LIST UPS\nUPS demo name\nERR DATA-STALE")],
    session => {
      expect_session_error(() => ignore(session.list_ups()), "DATA-STALE")
      assert_true(session.is_closed())
    },
  )
}

///|
async test "cancelling a queued request preserves the active session" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let received = @async.Semaphore(1, initial_value=0)
  let waiting = @async.Semaphore(1, initial_value=0)
  let allow_reply = @async.Semaphore(1, initial_value=0)
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        assert_eq(tcp.read_until("\n"), Some("GET TRACKING"))
        received.release()
        allow_reply.acquire()
        tcp.write("OFF\n")
        assert_eq(tcp.read_until("\n"), Some("GET NUMLOGINS \"demo\""))
        tcp.write("NUMLOGINS demo 0\n")
        assert_eq(tcp.read_some(), None)
      })
      let session = client.connect()
      defer session.close()
      let active = group.spawn(() => session.get_tracking())
      received.acquire()
      let queued = group.spawn(() => {
        waiting.release()
        ignore(@async.handle_cancellation(() => session.get_server_version()))
      })
      waiting.acquire()
      queued.cancel()
      queued.wait()
      assert_false(session.is_closed())
      allow_reply.release()
      assert_false(active.wait())
      assert_eq(session.get_num_logins("demo"), 0)
    })
  })
}

///|
async test "single reply exchange preserves raw results and rejects multiline framing" {
  session_fixture(
    [
      ("INSTCMD demo fixture.success two words", "ERR ACCESS-DENIED"),
      ("GET TRACKING id", "ERR FAILED"),
      ("LOGOUT", "OK Goodbye"),
    ],
    connect_timeout_ms=0,
    session => {
      for
        command in [
          "LIST UPS", "STARTTLS", "FSD demo\nFSD other", "USERNAME bad\r",
        ] {
        let rejected = try {
          ignore(session.request_line(command))
          false
        } catch {
          InvalidArgument(_) | Protocol(_) => true
          error => raise error
        }
        assert_true(rejected)
      }
      assert_eq(
        session.request_line("INSTCMD demo fixture.success two words"),
        "ERR ACCESS-DENIED",
      )
      assert_eq(
        session.request_line("GET TRACKING id", read_timeout_ms=1000),
        "ERR FAILED",
      )
      assert_eq(session.request_line("LOGOUT"), "OK Goodbye")
      assert_true(session.is_closed())
    },
  )
}
