use std::env;
use std::process::ExitCode;

use rust_lib_dxtr_box::inspector::Inspector;

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
            print!("{HELP}");
            return Ok(());
        }
        "-V" | "--version" => {
            println!("dxtr-box-inspect {VERSION}");
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
            let inspector = Inspector::open(&path).map_err(|error| (3, error.to_string()))?;
            for box_name in inspector.boxes().map_err(|error| (1, error.to_string()))? {
                println!("{box_name}");
            }
            Ok(())
        }
        _ => Err((2, format!("unknown command '{command}'\n\n{HELP}"))),
    }
}
