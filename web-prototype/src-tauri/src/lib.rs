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

/// The icon picked in Settings › General: the Dock icon on macOS (Finder keeps the bundle's), the window and taskbar
/// icon on Windows. Applied at launch and on change; the Mac remembers it across Dock show/hide below.
static DARK_ICON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

const LIGHT_ICON: &[u8] = include_bytes!("../icons/app-light.png");
const DARK_ICON_PNG: &[u8] = include_bytes!("../icons/app-dark.png");

#[tauri::command]
fn set_app_icon(app: tauri::AppHandle, dark: bool) -> Result<(), String> {
    DARK_ICON.store(dark, std::sync::atomic::Ordering::Relaxed);
    apply_app_icon(&app)
}

fn apply_app_icon(app: &tauri::AppHandle) -> Result<(), String> {
    let bytes = if DARK_ICON.load(std::sync::atomic::Ordering::Relaxed) { DARK_ICON_PNG } else { LIGHT_ICON };
    #[cfg(target_os = "macos")]
    {
        use objc2::AnyThread;
        use objc2_app_kit::{NSApplication, NSImage};
        use objc2_foundation::{MainThreadMarker, NSData};
        let _ = app;
        let mtm = MainThreadMarker::new().ok_or("not on the main thread")?;
        let image = NSImage::initWithData(NSImage::alloc(), &NSData::with_bytes(bytes)).ok_or("bad icon image")?;
        unsafe { NSApplication::sharedApplication(mtm).setApplicationIconImage(Some(&image)) };
    }
    #[cfg(not(target_os = "macos"))]
    {
        use tauri::Manager;
        if let Some(window) = app.get_webview_window("main") {
            window.set_icon(tauri::image::Image::from_bytes(bytes).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// "Close to Menu" on macOS: with the window closed the app drops its Dock icon and lives in the menu bar, still
/// polling and alerting; opening the window brings the icon back (MenuBarMode in the Swift app). Windows keeps its
/// tray icon either way, so there it does nothing.
#[tauri::command]
fn set_dock_visible(app: tauri::AppHandle, visible: bool) {
    #[cfg(target_os = "macos")]
    {
        let _ = app.set_activation_policy(if visible {
            tauri::ActivationPolicy::Regular
        } else {
            tauri::ActivationPolicy::Accessory
        });
        // The Dock icon comes back as the bundle's, so put the picked one back on.
        if visible {
            let _ = apply_app_icon(&app);
        }
    }
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
        .invoke_handler(tauri::generate_handler![secret_get, secret_set, secret_delete, set_dock_visible, set_app_icon])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
