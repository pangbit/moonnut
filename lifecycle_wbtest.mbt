///|
/// Cancellation must close the in-flight socket, not merely stop awaiting it.
async test "cancelled query closes its connection and permits another query" {
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
        let (first, _) = server.accept()
        defer first.close()
        assert_eq(first.read_until("\n"), Some("LIST UPS"))
        received.release()
        assert_eq(first.read_some(), None)
        let (second, _) = server.accept()
        defer second.close()
        assert_eq(second.read_until("\n"), Some("LIST UPS"))
        second.write(
          "BEGIN LIST UPS\nUPS demo \"Fresh connection\"\nEND LIST UPS\n",
        )
        assert_eq(second.read_some(), None)
      })
      let pending = group.spawn(() => {
        ignore(@async.handle_cancellation(() => client.list_ups()))
      })
      received.acquire()
      pending.cancel()
      let result = client.list_ups()
      assert_eq(result.length(), 1)
      assert_eq(result[0].description, "Fresh connection")
    })
  })
}

///|
async test "timed out query closes its connection and permits another query" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
    timeout_ms=200,
  )
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (first, _) = server.accept()
        defer first.close()
        assert_eq(first.read_until("\n"), Some("LIST UPS"))
        assert_eq(first.read_some(), None)
        let (second, _) = server.accept()
        defer second.close()
        assert_eq(second.read_until("\n"), Some("LIST UPS"))
        second.write("BEGIN LIST UPS\nEND LIST UPS\n")
        assert_eq(second.read_some(), None)
      })
      let timed_out = try {
        ignore(client.list_ups())
        false
      } catch {
        @async.TimeoutError => true
        err => raise err
      }
      assert_true(timed_out)
      assert_eq(client.list_ups().length(), 0)
    })
  })
}

///|
/// The server deliberately waits for both sockets, then replies in reverse order.
async test "concurrent operations on one client keep separate response streams" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = Client::new(
    "127.0.0.1",
    port=server.addr.port(),
    security=Plaintext,
  )
  fn reply(command : String?) -> String raise {
    match command {
      Some("GET VAR \"demo\" \"alpha\"") => "VAR demo alpha \"A\"\n"
      Some("GET VAR \"demo\" \"beta\"") => "VAR demo beta \"B\"\n"
      _ => raise Protocol("unexpected concurrent test request")
    }
  }
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (first, _) = server.accept()
        defer first.close()
        let first_reply = reply(first.read_until("\n"))
        let (second, _) = server.accept()
        defer second.close()
        let second_reply = reply(second.read_until("\n"))
        second.write(second_reply)
        first.write(first_reply)
        assert_eq(first.read_some(), None)
        assert_eq(second.read_some(), None)
      })
      let alpha = group.spawn(() => client.get_var("demo", "alpha"))
      let beta = group.spawn(() => client.get_var("demo", "beta"))
      assert_eq(alpha.wait(), "A")
      assert_eq(beta.wait(), "B")
    })
  })
}
