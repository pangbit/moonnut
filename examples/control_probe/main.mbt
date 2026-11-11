///|
/// Fixed control trace for the isolated in-memory fixture; accepts only a port.
async fn report(
  label : String,
  run : async () -> Unit,
  success~ : String = "OK",
) -> Unit {
  try {
    run()
    println(label + " " + success)
  } catch {
    @moonnut.NutError::Server(code) => println(label + " ERR " + code)
    error => raise error
  }
}

///|
async fn receipt(
  label : String,
  run : async () -> @moonnut.CommandReceipt,
) -> String {
  try {
    match run() {
      Accepted => {
        println(label + " OK")
        ""
      }
      Tracked(id) => {
        println(label + " OK TRACKING " + id)
        id
      }
    }
  } catch {
    @moonnut.NutError::Server(code) => {
      println(label + " ERR " + code)
      ""
    }
    error => raise error
  }
}

///|
async fn status(
  label : String,
  session : @moonnut.Session,
  id : String,
  wait~ : Bool = true,
) -> Unit {
  let mut result = session.get_tracking_status(id)
  if wait {
    for _ in 0..<100 {
      if result != @moonnut.Pending {
        break
      }
      @async.sleep(20)
      result = session.get_tracking_status(id)
    }
    if result == @moonnut.Pending {
      fail("tracking did not complete")
    }
  }
  println(
    label +
    " " +
    (match result {
      Pending => "PENDING"
      Success => "SUCCESS"
      Unknown => "ERR UNKNOWN"
      InvalidArgument => "ERR INVALID-ARGUMENT"
      Failed => "ERR FAILED"
    }),
  )
}

///|
async fn value(
  label : String,
  session : @moonnut.Session,
  name : String,
  wanted? : String,
) -> Unit {
  let mut result = session.get_var("control", name)
  if wanted is Some(expected) {
    for _ in 0..<100 {
      if result == expected {
        break
      }
      @async.sleep(20)
      result = session.get_var("control", name)
    }
    if result != expected {
      fail("driver value did not arrive")
    }
  }
  println(label + " " + result)
}

///|
async fn main {
  try {
    let args = @env.args()
    if args.length() != 2 {
      fail("expected loopback fixture port")
    }
    let client = @moonnut.Client::new(
      "127.0.0.1",
      port=@string.parse_int(args[1]),
    )
    let password = @env.get_env_var("MOONNUT_PASSWORD").unwrap()
    let denied = client.connect()
    defer denied.close()
    ignore(receipt("no-user", () => denied.set_var("control", "ups.id", "x")))
    denied.set_username("reader")
    ignore(
      receipt("no-password", () => denied.set_var("control", "ups.id", "x")),
    )
    denied.set_password(password)
    ignore(
      receipt("denied-set", () => denied.set_var("control", "missing", "x")),
    )
    ignore(
      receipt("denied-unknown-cmd", () => {
        denied.execute_command("control", "missing")
      }),
    )
    ignore(
      receipt("denied-cmd", () => {
        denied.execute_command("control", "fixture.success")
      }),
    )
    report("denied-primary", () => denied.primary("control"))
    report("denied-master", () => denied.master("control"))
    report("denied-fsd", () => denied.fsd("control"))
    denied.close()
    let session = client.connect()
    defer session.close()
    session.set_username("operator")
    session.set_password(password)
    report(
      "primary",
      () => session.primary("control"),
      success="OK PRIMARY-GRANTED",
    )
    report(
      "master",
      () => session.master("control"),
      success="OK MASTER-GRANTED",
    )
    println("logins " + session.get_num_logins("control").to_string())
    report("missing-primary", () => session.primary("missing"))
    report("missing-master", () => session.master("missing"))
    report("missing-fsd", () => session.fsd("missing"))
    ignore(
      receipt("missing-ups", () => session.set_var("missing", "ups.id", "x")),
    )
    ignore(
      receipt("missing-var", () => session.set_var("control", "missing", "x")),
    )
    ignore(
      receipt("readonly", () => session.set_var("control", "ups.status", "x")),
    )
    ignore(
      receipt("too-long", () => {
        session.set_var("control", "ups.id", "01234567890123456")
      }),
    )
    ignore(
      receipt("invalid-enum", () => {
        session.set_var("control", "ups.beeper.status", "other")
      }),
    )
    ignore(
      receipt("range-gap", () => {
        session.set_var("control", "input.transfer.low", "101")
      }),
    )
    ignore(
      receipt("delayed-set", () => {
        session.set_var("control", "ups.id", "a\"b\\c#d")
      }),
    )
    value("before-apply", session, "ups.id")
    ignore(
      receipt("release-set", () => {
        session.execute_command("control", "fixture.release")
      }),
    )
    value("after-apply", session, "ups.id", wanted="a\"b\\c#d")
    session.set_tracking(true)
    let range_id = receipt("range-text", () => {
      session.set_var("control", "input.transfer.low", "102tail")
    })
    status("range-result", session, range_id)
    value("range-value", session, "input.transfer.low", wanted="102tail")
    let held = receipt("hold", () => {
      session.execute_command("control", "fixture.hold")
    })
    status("held-result", session, held, wait=false)
    session.set_tracking(false)
    ignore(
      receipt("release-held", () => {
        session.execute_command("control", "fixture.release")
      }),
    )
    session.set_tracking(true)
    status("released-result", session, held)
    for name in ["success", "invalid", "failed", "unknown", "conversion"] {
      let id = receipt(name, () => {
        session.execute_command("control", "fixture." + name)
      })
      status(name + "-result", session, id)
    }
    session.set_tracking(false)
    ignore(
      receipt("absent", () => {
        session.execute_command("control", "fixture.success")
      }),
    )
    ignore(
      receipt("empty", () => {
        session.execute_command("control", "fixture.success", parameter="")
      }),
    )
    ignore(
      receipt("escaped", () => {
        session.execute_command(
          "control",
          "fixture.success",
          parameter="a\"b\\c#d",
        )
      }),
    )
    ignore(
      receipt("multiword", () => {
        session.execute_command(
          "control",
          "fixture.success",
          parameter="two words",
        )
      }),
    )
    session.set_tracking(true)
    let barrier = receipt("barrier", () => {
      session.execute_command("control", "fixture.success")
    })
    status("barrier-result", session, barrier)
    value("before-fsd", session, "ups.status")
    report("fsd", () => session.fsd("control"), success="OK FSD-SET")
    report("fsd-again", () => session.fsd("control"), success="OK FSD-SET")
    value("after-fsd", session, "ups.status")
    session.close()
    client.with_session(fresh => value("fresh-fsd", fresh, "ups.status"))
  } catch {
    _ => {
      println("Control fixture failed")
      @env.exit(1)
    }
  }
}
