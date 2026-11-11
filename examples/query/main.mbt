///|
priv enum Operation {
  Ups
  Vars(String)
  Var(String, String)
  UpsDescription(String)
  VarDescription(String, String)
  VarType(String, String)
  Writable(String)
  EnumValues(String, String)
  Ranges(String, String)
  Commands(String)
  CommandDescription(String, String)
}

///|
fn usage() -> Unit {
  println(
    "Usage: query HOST PORT [--plaintext | --ca FILE] [--vars UPS | --get UPS VARIABLE | --ups-desc UPS | --desc UPS VARIABLE | --type UPS VARIABLE | --rw UPS | --enum UPS VARIABLE | --range UPS VARIABLE | --commands UPS | --cmd-desc UPS COMMAND] [--json]",
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
        "--ups-desc" if !operation_set && index + 1 < args.length() => {
          operation = UpsDescription(args[index + 1])
          operation_set = true
          index += 2
        }
        "--desc" if !operation_set && index + 2 < args.length() => {
          operation = VarDescription(args[index + 1], args[index + 2])
          operation_set = true
          index += 3
        }
        "--type" if !operation_set && index + 2 < args.length() => {
          operation = VarType(args[index + 1], args[index + 2])
          operation_set = true
          index += 3
        }
        "--rw" if !operation_set && index + 1 < args.length() => {
          operation = Writable(args[index + 1])
          operation_set = true
          index += 2
        }
        "--enum" if !operation_set && index + 2 < args.length() => {
          operation = EnumValues(args[index + 1], args[index + 2])
          operation_set = true
          index += 3
        }
        "--range" if !operation_set && index + 2 < args.length() => {
          operation = Ranges(args[index + 1], args[index + 2])
          operation_set = true
          index += 3
        }
        "--commands" if !operation_set && index + 1 < args.length() => {
          operation = Commands(args[index + 1])
          operation_set = true
          index += 2
        }
        "--cmd-desc" if !operation_set && index + 2 < args.length() => {
          operation = CommandDescription(args[index + 1], args[index + 2])
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
      Vars(ups) | Writable(ups) => {
        let variables = match operation {
          Writable(_) => client.list_rw(ups)
          _ => client.list_vars(ups)
        }
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
      UpsDescription(ups) => {
        let description = client.get_ups_description(ups)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "description": @json.Json::string(description),
            }).stringify(),
          )
        } else {
          println(description)
        }
      }
      VarDescription(ups, name) => {
        let description = client.get_var_description(ups, name)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "name": @json.Json::string(name),
              "description": @json.Json::string(description),
            }).stringify(),
          )
        } else {
          println(description)
        }
      }
      VarType(ups, name) => {
        let types = client.get_var_type(ups, name)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "name": @json.Json::string(name),
              "types": @json.Json::array(
                types.map(value => @json.Json::string(value)),
              ),
            }).stringify(),
          )
        } else {
          println(types.join(" "))
        }
      }
      EnumValues(ups, name) => {
        let values = client.list_enum(ups, name)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "name": @json.Json::string(name),
              "values": @json.Json::array(
                values.map(value => @json.Json::string(value)),
              ),
            }).stringify(),
          )
        } else {
          for value in values {
            println(value)
          }
        }
      }
      Ranges(ups, name) => {
        let ranges = client.list_range(ups, name)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "name": @json.Json::string(name),
              "ranges": @json.Json::array(
                ranges.map(range => {
                  @json.Json::object({
                    "min": @json.Json::string(range.min),
                    "max": @json.Json::string(range.max),
                  })
                }),
              ),
            }).stringify(),
          )
        } else {
          for range in ranges {
            println(range.min + "\t" + range.max)
          }
        }
      }
      Commands(ups) => {
        let commands = client.list_commands(ups)
        if json_output {
          println(
            @json.Json::array(
              commands.map(command => @json.Json::string(command)),
            ).stringify(),
          )
        } else {
          for command in commands {
            println(command)
          }
        }
      }
      CommandDescription(ups, command) => {
        let description = client.get_command_description(ups, command)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "command": @json.Json::string(command),
              "description": @json.Json::string(description),
            }).stringify(),
          )
        } else {
          println(description)
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
