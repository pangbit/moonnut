///|
async test "control acknowledgements preserve dispatch and tracking distinctions" {
  session_fixture(
    [
      ("SET VAR \"demo\" \"ups.id\" \"a\\\"b\\\\c\\#d\"", "OK"),
      ("INSTCMD \"demo\" \"fixture.success\"", "OK TRACKING fixture-id"),
      ("INSTCMD \"demo\" \"fixture.success\" \"\"", "OK"),
      ("INSTCMD \"demo\" \"fixture.success\" \"two words\"", "OK"),
      ("PRIMARY \"demo\"", "OK PRIMARY-GRANTED"),
      ("MASTER \"demo\"", "OK MASTER-GRANTED"),
      ("FSD \"demo\"", "ERR ACCESS-DENIED"),
      ("FSD \"demo\"", "OK FSD-SET"),
    ],
    session => {
      assert_eq(session.set_var("demo", "ups.id", "a\"b\\c#d"), Accepted)
      assert_eq(
        session.execute_command("demo", "fixture.success"),
        Tracked("fixture-id"),
      )
      assert_eq(
        session.execute_command("demo", "fixture.success", parameter=""),
        Accepted,
      )
      assert_eq(
        session.execute_command(
          "demo",
          "fixture.success",
          parameter="two words",
        ),
        Accepted,
      )
      session.primary("demo")
      session.master("demo")
      expect_session_error(() => session.fsd("demo"), "ACCESS-DENIED")
      session.fsd("demo")
    },
  )
}

///|
async test "malformed command receipts and control arguments are rejected" {
  for
    reply in [
      "OK TRACKING", "OK TRACKING \"\"", "OK extra", "OK TRACKING id extra",
    ] {
    session_fixture([("SET VAR \"demo\" \"ups.id\" \"value\"", reply)], session => {
      let rejected = try {
        ignore(session.set_var("demo", "ups.id", "value"))
        false
      } catch {
        Protocol(_) => true
        error => raise error
      }
      assert_true(rejected)
    })
  }
  session_fixture([("GET TRACKING", "OFF")], session => {
    for
      run in [
        () => ignore(session.set_var("demo", "ups.id", "bad\nFSD demo")),
        () => {
          ignore(
            session.execute_command(
              "demo",
              "fixture.success",
              parameter="bad\r",
            ),
          )
        },
        () => session.primary("bad\n"),
        () => session.master("bad\n"),
        () => session.fsd("bad\n"),
      ] {
      let rejected = try {
        run()
        false
      } catch {
        InvalidArgument(_) => true
        error => raise error
      }
      assert_true(rejected)
    }
    assert_false(session.get_tracking())
  })
}

///|
async test "lost control acknowledgement closes the stream and never replays" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        assert_eq(
          tcp.read_until("\n"),
          Some("INSTCMD \"demo\" \"fixture.success\""),
        )
        tcp.close()
      })
      client.with_session(session => {
        let lost = try {
          ignore(session.execute_command("demo", "fixture.success"))
          false
        } catch {
          UnexpectedEof => true
          error => raise error
        }
        assert_true(lost)
        assert_true(session.is_closed())
        let closed = try {
          ignore(session.execute_command("demo", "fixture.success"))
          false
        } catch {
          ConnectionClosed => true
          error => raise error
        }
        assert_true(closed)
      })
    })
  })
}
