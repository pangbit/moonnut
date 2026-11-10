///|
async test "empty device list" {
  fixture("BEGIN LIST UPS\nEND LIST UPS\n", client => {
    assert_eq(client.list_ups().length(), 0)
  })
}

///|
async test "untrusted server text is not an error message" {
  fixture("ERR \"arbitrary server text\"\n", client => {
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

///|
async test "cross-device list row rejected" {
  fixture(
    "BEGIN LIST VAR lab\nVAR other ups.status \"OL\"\n",
    expected="LIST VAR \"lab\"\n",
    client => {
      let rejected = try {
        ignore(client.list_vars("lab"))
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
async test "invalid UTF-8 is redacted as a protocol error" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (tcp, _) = server.accept()
        defer tcp.close()
        ignore(tcp.read_until("\n"))
        tcp.write(b"\xff\n")
      })
      let client = Client::new(
        "127.0.0.1",
        port=server.addr.port(),
        security=Plaintext,
      )
      let rejected = try {
        ignore(client.list_ups())
        false
      } catch {
        Protocol("invalid UTF-8 response") => true
        err => raise err
      }
      assert_true(rejected)
    })
  })
}
