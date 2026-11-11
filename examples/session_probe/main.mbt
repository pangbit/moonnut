///|
/// Test adapter: only the disposable loopback upsd fixture is accepted.
/// It changes connection state, never UPS variables or power state.
async fn report(run : async () -> Unit, success~ : String = "OK") -> Unit {
  try {
    run()
    println(success)
  } catch {
    @moonnut.NutError::Server(code) => println("ERR " + code)
    error => raise error
  }
}

///|
async fn tracking(session : @moonnut.Session) -> Unit {
  println(if session.get_tracking() { "ON" } else { "OFF" })
}

///|
async fn status(session : @moonnut.Session) -> Unit {
  try {
    let result = session.get_tracking_status("fixture-unknown")
    println(
      match result {
        Pending => "PENDING"
        Success => "SUCCESS"
        Unknown => "ERR UNKNOWN"
        InvalidArgument => "ERR INVALID-ARGUMENT"
        Failed => "ERR FAILED"
      },
    )
  } catch {
    @moonnut.NutError::Server(code) => println("ERR " + code)
    error => raise error
  }
}

///|
async fn count(session : @moonnut.Session, wait_for? : Int32) -> Unit {
  let mut value = session.get_num_logins("demo")
  if wait_for is Some(wanted) {
    for _ in 0..<50 {
      if value == wanted {
        break
      }
      @async.sleep(20)
      value = session.get_num_logins("demo")
    }
    if value != wanted {
      fail("LOGIN cleanup did not complete")
    }
  }
  println("NUMLOGINS demo " + value.to_string())
}

///|
async fn clients(session : @moonnut.Session) -> Unit {
  let addresses = session.list_clients("demo")
  println(
    "CLIENTS" +
    (if addresses.is_empty() { "" } else { " " + addresses.join(" ") }),
  )
}

///|
async fn main {
  try {
    let args = @env.args()
    if args.length() != 2 {
      fail("expected loopback fixture port")
    }
    let username = @env.get_env_var("MOONNUT_USERNAME").unwrap()
    let password = @env.get_env_var("MOONNUT_PASSWORD").unwrap()
    let ca = @env.get_env_var("MOONNUT_CA")
    let security = match ca {
      Some(path) => @moonnut.TlsCaFile(path)
      None =>
        if @env.get_env_var("MOONNUT_SESSION_PLAINTEXT") == Some("1") {
          @moonnut.Plaintext
        } else {
          @moonnut.TryTls
        }
    }
    let client = @moonnut.Client::new(
      if ca is Some(_) {
        "localhost"
      } else {
        "127.0.0.1"
      },
      port=@string.parse_int(args[1]),
      security~,
    )
    let first = client.connect()
    defer first.close()
    tracking(first)
    status(first)
    report(() => first.set_tracking(true))
    report(() => first.login("demo"))
    report(() => first.set_username(username))
    report(() => first.set_username(username))
    report(() => first.set_tracking(true))
    report(() => first.login("demo"))
    report(() => first.set_password(password))
    report(() => first.set_password(password))
    count(first)
    clients(first)
    report(() => first.set_tracking(true))
    report(() => first.set_tracking(true))
    tracking(first)
    status(first)
    report(() => first.set_tracking(false))
    tracking(first)
    status(first)
    report(() => first.set_tracking(true))
    report(() => first.login("missing"))
    report(() => first.login("demo"))
    report(() => first.login("demo"))
    count(first)
    clients(first)
    println("VALUE " + first.get_var("demo", "ups.status"))
    let second = client.connect()
    defer second.close()
    tracking(second)
    report(() => second.set_username(username))
    report(() => second.set_password(password))
    report(() => second.login("demo"))
    count(first)
    clients(first)
    report(() => second.logout(), success="OK Goodbye")
    count(first, wait_for=1)
    report(() => first.logout(), success="OK Goodbye")
    let fresh = client.connect()
    defer fresh.close()
    tracking(fresh)
    count(fresh, wait_for=0)
    // Password before username is accepted; neither OK validates it.
    report(() => fresh.set_password("wrong-fixture-password"))
    report(() => fresh.set_username(username))
    report(() => fresh.set_tracking(true))
    tracking(fresh)
    report(() => fresh.login("demo"))
    println("VALUE " + fresh.get_var("demo", "ups.status"))
    report(() => fresh.logout(), success="OK Goodbye")
  } catch {
    _ => {
      println("Session fixture failed")
      @env.exit(1)
    }
  }
}
