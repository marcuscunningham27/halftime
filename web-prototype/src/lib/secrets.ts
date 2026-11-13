// Secrets (the Claude key, ESPN cookies). In the desktop app they go to the macOS Keychain / Windows Credential
// Manager through the Rust commands in src-tauri/src/lib.rs. A website has no such store, so there they last only
// for the browser session (sessionStorage) and are typed again next visit.

const inTauri = () => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
const invoke = async <T>(cmd: string, args: Record<string, string>) => (await import('@tauri-apps/api/core')).invoke<T>(cmd, args);

export async function getSecret(name: string): Promise<string | undefined> {
	if (inTauri()) return (await invoke<string | null>('secret_get', { name })) ?? undefined;
	try {
		return sessionStorage.getItem(`secret:${name}`) ?? undefined;
	} catch {
		return undefined;
	}
}

/** Saves the secret, or removes it when `value` is empty. Throws if the system store refused. */
export async function setSecret(name: string, value: string | undefined): Promise<void> {
	if (inTauri()) {
		await (value ? invoke('secret_set', { name, value }) : invoke('secret_delete', { name }));
		return;
	}
	try {
		if (value) sessionStorage.setItem(`secret:${name}`, value);
		else sessionStorage.removeItem(`secret:${name}`);
	} catch {
		// Storage unavailable: the secret lasts until the page reloads.
	}
}
