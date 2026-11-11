///|
async test "list rows arrive before END and scoped readers cannot escape" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let consumed = @async.Semaphore(1, initial_value=0)
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
        assert_eq(tcp.read_until("\n"), Some("LIST UPS"))
        tcp.write("begin list ups extra\nUPS demo name extra\n")
        consumed.acquire()
        tcp.write("END LIST unrelated extra\n")
        assert_eq(tcp.read_until("\n"), Some("GET TRACKING"))
        tcp.write("OFF\n")
        assert_eq(tcp.read_some(), None)
      })
      client.with_session(session => {
        let reader = session.with_list(["UPS"], reader => {
          assert_eq(reader.next(), Some(["UPS", "demo", "name", "extra"]))
          consumed.release()
          assert_eq(reader.next(), None)
          assert_eq(reader.next(), None)
          reader
        })
        let expired = try {
          ignore(reader.next())
          false
        } catch {
          ConnectionClosed => true
          error => raise error
        }
        assert_true(expired)
        assert_false(session.is_closed())
        assert_false(session.get_tracking())
      })
    })
  })
}

///|
async test "streaming preserves partial rows and closes on read or callback failure" {
  for tail in ["ERR DATA-STALE", "WRONG prefix"] {
    session_fixture([("LIST UPS", "BEGIN LIST UPS\nUPS demo name\n" + tail)], session => {
      let seen : Array[String] = []
      let failed = try {
        session.with_list(["UPS"], reader => {
          while reader.next() is Some(row) {
            seen.push(row[1])
          }
        })
        false
      } catch {
        Server(_) | Protocol(_) => true
        error => raise error
      }
      assert_true(failed)
      assert_eq(seen, ["demo"])
      assert_true(session.is_closed())
    })
  }
  for abort in [false, true] {
    session_fixture([("LIST UPS", "BEGIN LIST UPS\nUPS demo name")], session => {
      session.with_list(["UPS"], reader => {
        ignore(reader.next())
        if abort {
          raise Protocol("callback failure")
        }
      }) catch {
        Protocol(_) => ()
        error => raise error
      }
      assert_true(session.is_closed())
    })
  }
}

///|
async test "list start errors recover and limits still bound streaming" {
  session_fixture(
    [("LIST UPS", "ERR ACCESS-DENIED"), ("GET TRACKING", "OFF")],
    session => {
      let invalid = try {
        session.with_list([], _ => ())
        false
      } catch {
        NutError::InvalidArgument(_) => true
        error => raise error
      }
      assert_true(invalid)
      expect_session_error(
        () => session.with_list(["UPS"], _ => fail("unexpected callback")),
        "ACCESS-DENIED",
      )
      assert_false(session.get_tracking())
    },
  )
  session_fixture(
    [
      (
        "LIST UPS", "BEGIN LIST UPS\nUPS first name\nUPS second name\nEND LIST UPS",
      ),
    ],
    max_rows=1,
    session => {
      let seen : Array[String] = []
      let limited = try {
        session.with_list(["UPS"], reader => {
          while reader.next() is Some(row) {
            seen.push(row[1])
          }
        })
        false
      } catch {
        LimitExceeded("rows") => true
        error => raise error
      }
      assert_true(limited)
      assert_eq(seen, ["first"])
      assert_true(session.is_closed())
    },
  )
}

///|
async test "cancelling a streaming read closes the session without replay" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let started = @async.Semaphore(1, initial_value=0)
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
        assert_eq(tcp.read_until("\n"), Some("LIST UPS"))
        tcp.write("BEGIN LIST UPS\n")
        assert_eq(tcp.read_some(), None)
      })
      let session = client.connect()
      defer session.close()
      let task = group.spawn(() => {
        ignore(
          @async.handle_cancellation(() => {
            session.with_list(["UPS"], reader => {
              started.release()
              ignore(reader.next())
            })
          }),
        )
      })
      started.acquire()
      task.cancel()
      task.wait()
      assert_true(session.is_closed())
    })
  })
}
