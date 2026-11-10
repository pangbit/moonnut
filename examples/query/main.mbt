///|
priv enum Operation {
  Ups
  Vars(String)
  Var(String, String)
}

///|
fn usage() -> Unit {
  println(
    "Usage: query HOST PORT [--plaintext | --ca FILE] [--vars UPS | --get UPS VARIABLE] [--json]",
  )
  println("TLS with certificate and hostname verification is the default.")
}

///|
/// Connect only to an explicitly supplied server. No default device is polled.
async fn main {
  let args = @env.args()
  if args.length() < 3 {
    usage()
    return
  }
  try {
    let mut security = @moonnut.Tls
    let mut security_set = false
    let mut operation = Ups
    let mut operation_set = false
    let mut json_output = false
    let mut index = 3
    while index < args.length() {
      match args[index] {
        "--json" if !json_output => {
          json_output = true
          index += 1
        }
        "--plaintext" if !security_set => {
          security = @moonnut.Plaintext
          security_set = true
          index += 1
        }
        "--ca" if !security_set && index + 1 < args.length() => {
          security = @moonnut.TlsCaFile(args[index + 1])
          security_set = true
          index += 2
        }
        "--vars" if !operation_set && index + 1 < args.length() => {
          operation = Vars(args[index + 1])
          operation_set = true
          index += 2
        }
        "--get" if !operation_set && index + 2 < args.length() => {
          operation = Var(args[index + 1], args[index + 2])
          operation_set = true
          index += 3
        }
        _ => {
          usage()
          @env.exit(2)
        }
      }
    }
    let client = @moonnut.Client::new(
      args[1],
      port=@string.parse_int(args[2]),
      security~,
      username?=@env.get_env_var("MOONNUT_USERNAME"),
      password?=@env.get_env_var("MOONNUT_PASSWORD"),
    )
    match operation {
      Ups => {
        let devices = client.list_ups()
        if json_output {
          let value = @json.Json::array(
            devices.map(ups => {
              @json.Json::object({
                "name": @json.Json::string(ups.name),
                "description": @json.Json::string(ups.description),
              })
            }),
          )
          println(value.stringify())
        } else {
          for ups in devices {
            println(ups.name + "\t" + ups.description)
          }
        }
      }
      Vars(ups) => {
        let variables = client.list_vars(ups)
        if json_output {
          let value = @json.Json::array(
            variables.map(variable => {
              @json.Json::object({
                "name": @json.Json::string(variable.name),
                "value": @json.Json::string(variable.value),
              })
            }),
          )
          println(value.stringify())
        } else {
          for variable in variables {
            println(variable.name + "\t" + variable.value)
          }
        }
      }
      Var(ups, name) => {
        let value = client.get_var(ups, name)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "name": @json.Json::string(name),
              "value": @json.Json::string(value),
            }).stringify(),
          )
        } else {
          println(value)
        }
      }
    }
  } catch {
    // Do not echo credentials, arguments or untrusted responses in a CLI error.
    _ => {
      println("Query failed. Check TLS trust, access and server availability.")
      @env.exit(1)
    }
  }
}
