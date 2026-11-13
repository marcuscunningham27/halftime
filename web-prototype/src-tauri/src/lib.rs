// Secrets live in the system's own store (macOS Keychain, Windows Credential Manager), never in the web page's storage.
const SERVICE: &str = "com.halftime.prototype";

#[tauri::command]
fn secret_get(name: &str) -> Result<Option<String>, String> {
    match keyring::Entry::new(SERVICE, name).and_then(|e| e.get_password()) {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
fn secret_set(name: &str, value: &str) -> Result<(), String> {
    keyring::Entry::new(SERVICE, name).and_then(|e| e.set_password(value)).map_err(|e| e.to_string())
}

#[tauri::command]
fn secret_delete(name: &str) -> Result<(), String> {
    match keyring::Entry::new(SERVICE, name).and_then(|e| e.delete_credential()) {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

/// "Close to Menu" on macOS: with the window closed the app drops its Dock icon and lives in the menu bar, still
/// polling and alerting; opening the window brings the icon back (MenuBarMode in the Swift app). Windows keeps its
/// tray icon either way, so there it does nothing.
#[tauri::command]
fn set_dock_visible(app: tauri::AppHandle, visible: bool) {
    #[cfg(target_os = "macos")]
    let _ = app.set_activation_policy(if visible {
        tauri::ActivationPolicy::Regular
    } else {
        tauri::ActivationPolicy::Accessory
    });
    #[cfg(not(target_os = "macos"))]
    let _ = (app, visible);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![secret_get, secret_set, secret_delete, set_dock_visible])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
