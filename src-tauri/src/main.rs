#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, ChildStdin, Command, Stdio},
    sync::{Arc, Mutex},
};
use tauri::Manager;

struct AudioService {
    child: Mutex<Child>,
    input: Mutex<ChildStdin>,
    latest: Arc<Mutex<Value>>,
}

#[tauri::command]
fn snapshot(service: tauri::State<AudioService>) -> Result<Value, String> {
    service
        .latest
        .lock()
        .map(|v| v.clone())
        .map_err(|e| e.to_string())
}

#[tauri::command]
fn audio_command(
    service: tauri::State<AudioService>,
    action: String,
    uid: Option<String>,
    channel: Option<u32>,
    mode: Option<String>,
) -> Result<(), String> {
    if !["tap", "select", "mode"].contains(&action.as_str()) {
        return Err("Unknown audio action".into());
    }
    if action == "mode" && !matches!(mode.as_deref(), Some("music" | "click")) {
        return Err("Choose Music or Click track".into());
    }
    let data = json!({"action": action, "uid": uid, "channel": channel, "mode": mode});
    let mut input = service.input.lock().map_err(|e| e.to_string())?;
    writeln!(input, "{}", data)
        .map_err(|_| "Audio service stopped. Reopen Tempo Time LIVE.".to_string())
}

fn main() {
    let app = tauri::Builder::default()
        .on_window_event(|window, event| {
            if matches!(event, tauri::WindowEvent::CloseRequested { .. }) {
                window.app_handle().exit(0);
            }
        })
        .setup(|app| {
            let helper = std::env::current_exe()?.parent().ok_or("Missing application directory")?.join("tempo-service");
            let mut command = Command::new(helper);
            let runtime = app.path().resource_dir()?.join("runtime/tempo-live/tempo-live");
            if cfg!(debug_assertions) {
                let worker = std::env::var_os("TEMPO_BEATNET_WORKER")
                    .ok_or("Start development with npm run dev")?;
                command.env("TEMPO_BEATNET_WORKER", worker);
            } else {
                command.env("TEMPO_BEATNET_WORKER", runtime);
            }
            let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit()).spawn()?;
            let input = child.stdin.take().ok_or("Missing audio input pipe")?;
            let output = child.stdout.take().ok_or("Missing audio output pipe")?;
            let latest = Arc::new(Mutex::new(json!({"devices": [], "channel": 1, "uid": "", "status": "Connecting", "listening": false, "starting": false, "manual": false, "mode": "music", "bpm": null, "pulse": null, "peakDB": -120, "error": null})));
            let reader_state = latest.clone();
            std::thread::spawn(move || {
                for line in BufReader::new(output).lines() {
                    let Ok(line) = line else { break };
                    if let Ok(value) = serde_json::from_str::<Value>(&line) {
                        if let Ok(mut state) = reader_state.lock() { *state = value; }
                    }
                }
                if let Ok(mut state) = reader_state.lock() {
                    state["error"] = json!("Audio service stopped. Reopen Tempo Time LIVE.");
                    state["listening"] = json!(false);
                    state["starting"] = json!(false);
                    state["bpm"] = Value::Null;
                    state["pulse"] = Value::Null;
                    state["peakDB"] = json!(-120);
                }
            });
            app.manage(AudioService { child: Mutex::new(child), input: Mutex::new(input), latest });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![snapshot, audio_command])
        .build(tauri::generate_context!())
        .expect("could not start Tempo Time LIVE");
    app.run(|app, event| {
        if matches!(event, tauri::RunEvent::Exit) {
            let service = app.state::<AudioService>();
            if let Ok(mut child) = service.child.lock() {
                let _ = child.kill();
                let _ = child.wait();
            };
        }
    });
}
