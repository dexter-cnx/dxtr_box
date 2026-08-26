use std::env;
use std::io::{self, Read, Write};
use std::process::ExitCode;

#[cfg(feature = "full")]
use rust_lib_dxtr_box::inspector_decode::{decode_record, InspectorDecodeError};
use rust_lib_dxtr_box::{
    inspector::{Inspector, MAX_KEY_PAGE_SIZE},
    DxtrBoxError,
};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const DEFAULT_LIMIT: usize = 100;
const HELP: &str = "Dxtr_Box read-only inspector\n\nUsage:\n  dxtr-box-inspect --help\n  dxtr-box-inspect --version\n  dxtr-box-inspect <path> boxes [--format text|json]\n  dxtr-box-inspect <path> keys <box> [--offset N] [--limit N] [--format text|json]\n  dxtr-box-inspect <path> get <box> <key> [--raw] [--key-stdin] [--format text|json]\n  dxtr-box-inspect <path> indexes <box> [--format text|json]\n\nCommands:\n  boxes      List discovered .dxtr boxes in deterministic order\n  keys       List a bounded deterministic page of record keys\n  get        Decode one record; use --raw for persisted MessagePack bytes\n  indexes    List persisted index definitions\n\nSecrets:\n  --key-stdin reads the exact UTF-8 key material from stdin and never accepts the raw secret in argv\n  Use printf rather than echo when the key must not include a trailing newline\n";

#[derive(Clone, Copy, PartialEq, Eq)]
enum OutputFormat {
    Text,
    Json,
}

enum Command {
    Boxes {
        format: OutputFormat,
    },
    Keys {
        box_name: String,
        options: KeyOptions,
    },
    Get {
        box_name: String,
        key: String,
        options: GetOptions,
    },
    Indexes {
        box_name: String,
        format: OutputFormat,
    },
}

fn main() -> ExitCode {
    match run(env::args().skip(1).collect()) {
        Ok(()) => ExitCode::SUCCESS,
        Err((code, message)) => {
            eprintln!("{message}");
            ExitCode::from(code)
        }
    }
}

fn run(args: Vec<String>) -> Result<(), (u8, String)> {
    let Some(first) = args.first() else {
        return Err((2, HELP.to_owned()));
    };
    match first.as_str() {
        "-h" | "--help" => return write_stdout(HELP.as_bytes()),
        "-V" | "--version" => {
            return write_stdout(format!("dxtr-box-inspect {VERSION}\n").as_bytes());
        }
        _ => {}
    }

    if args.len() < 2 {
        return Err((2, HELP.to_owned()));
    }

    let path = &args[0];
    let command = parse_command(&args[1..])?;
    let inspector = Inspector::open(path).map_err(map_inspector_error)?;
    execute(command, &inspector)
}

fn parse_command(args: &[String]) -> Result<Command, (u8, String)> {
    let Some(command) = args.first() else {
        return Err((2, HELP.to_owned()));
    };
    match command.as_str() {
        "boxes" => Ok(Command::Boxes {
            format: parse_format(&args[1..])?,
        }),
        "keys" => {
            let box_name = args
                .get(1)
                .ok_or_else(|| (2, "keys requires <box>".to_owned()))?;
            Ok(Command::Keys {
                box_name: box_name.clone(),
                options: parse_key_options(&args[2..])?,
            })
        }
        "get" => {
            let box_name = args
                .get(1)
                .ok_or_else(|| (2, "get requires <box> <key>".to_owned()))?;
            let key = args
                .get(2)
                .ok_or_else(|| (2, "get requires <box> <key>".to_owned()))?;
            Ok(Command::Get {
                box_name: box_name.clone(),
                key: key.clone(),
                options: parse_get_options(&args[3..])?,
            })
        }
        "indexes" => {
            let box_name = args
                .get(1)
                .ok_or_else(|| (2, "indexes requires <box>".to_owned()))?;
            Ok(Command::Indexes {
                box_name: box_name.clone(),
                format: parse_format(&args[2..])?,
            })
        }
        _ => Err((2, format!("unknown command '{command}'\n\n{HELP}"))),
    }
}

fn execute(command: Command, inspector: &Inspector) -> Result<(), (u8, String)> {
    match command {
        Command::Boxes { format } => {
            let boxes = inspector.boxes().map_err(map_inspector_error)?;
            if format == OutputFormat::Json {
                write_stdout(format!("{{\"boxes\":{}}}\n", json_string_array(&boxes)).as_bytes())
            } else {
                write_lines(boxes.iter().map(String::as_str))
            }
        }
        Command::Keys { box_name, options } => {
            require_box(inspector, &box_name)?;
            let keys = inspector
                .keys(&box_name, options.offset, options.limit)
                .map_err(map_inspector_error)?;
            if options.format == OutputFormat::Json {
                let output = format!(
                    "{{\"box\":{},\"offset\":{},\"limit\":{},\"keys\":{}}}\n",
                    json_string(&box_name),
                    options.offset,
                    options.limit,
                    json_string_array(&keys)
                );
                write_stdout(output.as_bytes())
            } else {
                write_lines(keys.iter().map(String::as_str))
            }
        }
        Command::Get {
            box_name,
            key,
            options,
        } => execute_get(inspector, &box_name, &key, options),
        Command::Indexes { box_name, format } => {
            require_box(inspector, &box_name)?;
            let indexes = inspector.indexes(&box_name).map_err(map_inspector_error)?;
            if format == OutputFormat::Json {
                let mut body = String::from("[");
                for (position, index) in indexes.iter().enumerate() {
                    if position > 0 {
                        body.push(',');
                    }
                    body.push_str(&format!(
                        "{{\"name\":{},\"field\":{}}}",
                        json_string(&index.name),
                        json_string(&index.field)
                    ));
                }
                body.push(']');
                write_stdout(
                    format!(
                        "{{\"box\":{},\"indexes\":{body}}}\n",
                        json_string(&box_name)
                    )
                    .as_bytes(),
                )
            } else {
                let lines = indexes
                    .iter()
                    .map(|index| format!("{}\t{}", index.name, index.field))
                    .collect::<Vec<_>>();
                write_lines(lines.iter().map(String::as_str))
            }
        }
    }
}

fn execute_get(
    inspector: &Inspector,
    box_name: &str,
    key: &str,
    options: GetOptions,
) -> Result<(), (u8, String)> {
    require_box(inspector, box_name)?;

    if options.raw {
        let Some(record) = inspector.get(box_name, key).map_err(map_inspector_error)? else {
            return Err((4, format!("key '{key}' was not found in box '{box_name}'")));
        };
        let hex = hex_encode(&record.value);
        if options.format == OutputFormat::Json {
            let output = format!(
                "{{\"box\":{},\"key\":{},\"encoding\":\"messagepack-raw-hex\",\"value\":{}}}\n",
                json_string(box_name),
                json_string(&record.key),
                json_string(&hex)
            );
            return write_stdout(output.as_bytes());
        }
        return write_stdout(format!("{}\t{hex}\n", record.key).as_bytes());
    }

    #[cfg(feature = "full")]
    {
        let password = if options.key_stdin {
            Some(read_key_stdin()?)
        } else {
            None
        };
        let Some(record) = decode_record(inspector, box_name, key, password.as_deref())
            .map_err(map_decode_error)?
        else {
            return Err((4, format!("key '{key}' was not found in box '{box_name}'")));
        };
        if options.format == OutputFormat::Json {
            let output = format!(
                "{{\"box\":{},\"key\":{},\"encoding\":\"messagepack-json\",\"value\":{}}}\n",
                json_string(box_name),
                json_string(&record.key),
                record.value_json
            );
            return write_stdout(output.as_bytes());
        }
        return write_stdout(format!("{}\t{}\n", record.key, record.value_json).as_bytes());
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (inspector, box_name, key, options);
        Err((
            6,
            "semantic record decoding requires the full native profile; use --raw for persisted bytes"
                .to_owned(),
        ))
    }
}

fn require_box(inspector: &Inspector, box_name: &str) -> Result<(), (u8, String)> {
    if inspector
        .box_exists(box_name)
        .map_err(map_inspector_error)?
    {
        Ok(())
    } else {
        Err((4, format!("box '{box_name}' was not found")))
    }
}

struct KeyOptions {
    offset: usize,
    limit: usize,
    format: OutputFormat,
}

struct GetOptions {
    format: OutputFormat,
    raw: bool,
    key_stdin: bool,
}

fn parse_key_options(args: &[String]) -> Result<KeyOptions, (u8, String)> {
    let mut offset = 0;
    let mut limit = DEFAULT_LIMIT;
    let mut format = OutputFormat::Text;
    let mut position = 0;
    while position < args.len() {
        match args[position].as_str() {
            "--offset" => {
                offset = parse_usize_option(args, position, "--offset")?;
                position += 2;
            }
            "--limit" => {
                limit = parse_usize_option(args, position, "--limit")?;
                if limit == 0 || limit > MAX_KEY_PAGE_SIZE {
                    return Err((
                        2,
                        format!("--limit must be between 1 and {MAX_KEY_PAGE_SIZE}"),
                    ));
                }
                position += 2;
            }
            "--format" => {
                format = parse_format_value(args.get(position + 1))?;
                position += 2;
            }
            option => return Err((2, format!("unexpected option '{option}'"))),
        }
    }
    Ok(KeyOptions {
        offset,
        limit,
        format,
    })
}

fn parse_get_options(args: &[String]) -> Result<GetOptions, (u8, String)> {
    let mut format = OutputFormat::Text;
    let mut raw = false;
    let mut key_stdin = false;
    let mut position = 0;
    while position < args.len() {
        match args[position].as_str() {
            "--raw" => {
                raw = true;
                position += 1;
            }
            "--key-stdin" => {
                key_stdin = true;
                position += 1;
            }
            "--format" => {
                format = parse_format_value(args.get(position + 1))?;
                position += 2;
            }
            option => return Err((2, format!("unexpected option '{option}'"))),
        }
    }
    if raw && key_stdin {
        return Err((
            2,
            "--key-stdin cannot be combined with --raw because raw inspection does not decrypt"
                .to_owned(),
        ));
    }
    Ok(GetOptions {
        format,
        raw,
        key_stdin,
    })
}

fn parse_format(args: &[String]) -> Result<OutputFormat, (u8, String)> {
    if args.is_empty() {
        return Ok(OutputFormat::Text);
    }
    if args.len() == 2 && args[0] == "--format" {
        return parse_format_value(args.get(1));
    }
    Err((2, "expected only '--format text|json'".to_owned()))
}

fn parse_format_value(value: Option<&String>) -> Result<OutputFormat, (u8, String)> {
    match value.map(String::as_str) {
        Some("text") => Ok(OutputFormat::Text),
        Some("json") => Ok(OutputFormat::Json),
        _ => Err((2, "--format must be 'text' or 'json'".to_owned())),
    }
}

fn parse_usize_option(args: &[String], position: usize, name: &str) -> Result<usize, (u8, String)> {
    let value = args
        .get(position + 1)
        .ok_or_else(|| (2, format!("{name} requires a value")))?;
    value
        .parse::<usize>()
        .map_err(|_| (2, format!("{name} must be a non-negative integer")))
}

fn read_key_stdin() -> Result<String, (u8, String)> {
    let mut value = String::new();
    io::stdin()
        .read_to_string(&mut value)
        .map_err(|error| (5, format!("read encryption key from stdin: {error}")))?;
    if value.is_empty() {
        return Err((5, "encryption key from stdin cannot be empty".to_owned()));
    }
    Ok(value)
}

fn map_inspector_error(error: DxtrBoxError) -> (u8, String) {
    let code = match error {
        DxtrBoxError::InvalidInput { .. } => 3,
        DxtrBoxError::UnsupportedFeature { .. } => 6,
        DxtrBoxError::Engine { .. } => 1,
    };
    (code, error.to_string())
}

#[cfg(feature = "full")]
fn map_decode_error(error: InspectorDecodeError) -> (u8, String) {
    match error {
        InspectorDecodeError::Storage(error) => map_inspector_error(error),
        InspectorDecodeError::Authentication(message) | InspectorDecodeError::Decode(message) => {
            (5, message)
        }
        InspectorDecodeError::Unsupported(message) => (6, message),
    }
}

fn write_lines<'a>(lines: impl Iterator<Item = &'a str>) -> Result<(), (u8, String)> {
    let mut output = String::new();
    for line in lines {
        output.push_str(line);
        output.push('\n');
    }
    write_stdout(output.as_bytes())
}

fn write_stdout(bytes: &[u8]) -> Result<(), (u8, String)> {
    let mut stdout = io::stdout().lock();
    match stdout.write_all(bytes) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Err(error) => Err((1, format!("write stdout: {error}"))),
    }
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn json_string_array(values: &[String]) -> String {
    let mut output = String::from("[");
    for (position, value) in values.iter().enumerate() {
        if position > 0 {
            output.push(',');
        }
        output.push_str(&json_string(value));
    }
    output.push(']');
    output
}

fn json_string(value: &str) -> String {
    let mut output = String::with_capacity(value.len() + 2);
    output.push('"');
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            character if character.is_control() => {
                output.push_str(&format!("\\u{:04x}", character as u32));
            }
            character => output.push(character),
        }
    }
    output.push('"');
    output
}
