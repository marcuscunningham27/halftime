# Halftime

A sports scores app for Mac, Windows and the web: Tauri (Rust) around a SvelteKit page. See `../HANDOFF.md` for
what it does, how it's laid out and what's open.

- Run the desktop app: `CARGO_TARGET_DIR="$HOME/Library/Caches/halftime-prototype-target" npm run tauri dev`
  (the cache path keeps Rust's build output out of iCloud).
- Run in a browser only: `npm run dev`, then open http://localhost:1420.
- Checks: `npm run check` (types) and `npm test` (logic, with Node's test runner).

Data comes from ESPN's and Sleeper's public APIs; ESPN Fantasy private leagues and the Claude key use the
system Keychain / Credential Manager through the Rust commands in `src-tauri/src/lib.rs`.
