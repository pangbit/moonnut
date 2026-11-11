///|
priv enum Operation {
  Ups
  NumLogins(String)
  Clients(String)
  ServerVersion
  NetVersion
  ProtocolVersion
  ServerHelp
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
    "Usage: query HOST PORT [--plaintext | --tls | --tls-unverified | --ca FILE] [--vars UPS | --get UPS VARIABLE | --ups-desc UPS | --desc UPS VARIABLE | --type UPS VARIABLE | --rw UPS | --enum UPS VARIABLE | --range UPS VARIABLE | --commands UPS | --cmd-desc UPS COMMAND | --num-logins UPS | --clients UPS | --server-version | --net-version | --protocol-version | --server-help] [--json]",
  )
  println(
    "Default: try unverified TLS, then plaintext if STARTTLS is refused (NUT CLI policy). Use --tls or --ca FILE to require verified TLS.",
  )
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
    let mut security = @moonnut.TryTls
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
        "--tls" if !security_set => {
          security = @moonnut.Tls
          security_set = true
          index += 1
        }
        "--tls-unverified" if !security_set => {
          security = @moonnut.TlsUnverified
          security_set = true
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
        "--num-logins" if !operation_set && index + 1 < args.length() => {
          operation = NumLogins(args[index + 1])
          operation_set = true
          index += 2
        }
        "--clients" if !operation_set && index + 1 < args.length() => {
          operation = Clients(args[index + 1])
          operation_set = true
          index += 2
        }
        "--server-version" if !operation_set => {
          operation = ServerVersion
          operation_set = true
          index += 1
        }
        "--net-version" if !operation_set => {
          operation = NetVersion
          operation_set = true
          index += 1
        }
        "--protocol-version" if !operation_set => {
          operation = ProtocolVersion
          operation_set = true
          index += 1
        }
        "--server-help" if !operation_set => {
          operation = ServerHelp
          operation_set = true
          index += 1
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
      NumLogins(ups) => {
        let count = client.get_num_logins(ups)
        if json_output {
          println(
            @json.Json::object({
              "ups": @json.Json::string(ups),
              "num_logins": @json.Json::number(count.to_double()),
            }).stringify(),
          )
        } else {
          println(count)
        }
      }
      Clients(ups) => {
        let addresses = client.list_clients(ups)
        if json_output {
          println(
            @json.Json::array(
              addresses.map(address => @json.Json::string(address)),
            ).stringify(),
          )
        } else {
          for address in addresses {
            println(address)
          }
        }
      }
      ServerVersion | NetVersion | ProtocolVersion | ServerHelp => {
        let value = match operation {
          ServerVersion => client.get_server_version()
          NetVersion => client.get_net_version()
          ProtocolVersion => client.get_protocol_version()
          _ => client.get_help()
        }
        if json_output {
          println(@json.Json::string(value).stringify())
        } else {
          println(value)
        }
      }
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
