use std::env;
use std::io::{self, Write};
use std::process::ExitCode;

use rust_lib_dxtr_box::{inspector::Inspector, DxtrBoxError};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const HELP: &str = "Dxtr_Box read-only inspector\n\nUsage:\n  dxtr-box-inspect --help\n  dxtr-box-inspect --version\n  dxtr-box-inspect <path> boxes\n\nCommands:\n  boxes    List discovered .dxtr boxes in deterministic order\n";

fn main() -> ExitCode {
    match run(env::args().skip(1)) {
        Ok(()) => ExitCode::SUCCESS,
        Err((code, message)) => {
            eprintln!("{message}");
            ExitCode::from(code)
        }
    }
}

fn run(mut args: impl Iterator<Item = String>) -> Result<(), (u8, String)> {
    let first = args.next().ok_or_else(|| (2, HELP.to_owned()))?;
    match first.as_str() {
        "-h" | "--help" => {
            write_stdout(HELP.as_bytes())?;
            return Ok(());
        }
        "-V" | "--version" => {
            write_stdout(format!("dxtr-box-inspect {VERSION}\n").as_bytes())?;
            return Ok(());
        }
        _ => {}
    }

    let path = first;
    let command = args.next().ok_or_else(|| (2, HELP.to_owned()))?;
    if args.next().is_some() {
        return Err((2, "unexpected extra arguments".to_owned()));
    }

    match command.as_str() {
        "boxes" => {
            let inspector = Inspector::open(&path).map_err(map_inspector_error)?;
            let boxes = inspector.boxes().map_err(map_inspector_error)?;
            let mut output = String::new();
            for box_name in boxes {
                output.push_str(&box_name);
                output.push('\n');
            }
            write_stdout(output.as_bytes())
        }
        _ => Err((2, format!("unknown command '{command}'\n\n{HELP}"))),
    }
}

fn map_inspector_error(error: DxtrBoxError) -> (u8, String) {
    let code = match error {
        DxtrBoxError::InvalidInput { .. } => 3,
        DxtrBoxError::UnsupportedFeature { .. } => 6,
        DxtrBoxError::Engine { .. } => 1,
    };
    (code, error.to_string())
}

fn write_stdout(bytes: &[u8]) -> Result<(), (u8, String)> {
    let mut stdout = io::stdout().lock();
    match stdout.write_all(bytes) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Err(error) => Err((1, format!("write stdout: {error}"))),
    }
}
