// What the app needs to know about where it runs, and the fetch every data source shares.

/** True in the desktop app (Tauri), false in a plain browser. */
export const inTauri = () => typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/** A JSON GET that throws on any non-2xx status, saying which. */
export async function getJSON(url: string): Promise<any> {
	const response = await fetch(url);
	if (!response.ok) throw new Error(`${new URL(url).hostname} returned ${response.status}`);
	return response.json();
}

/** For a link's click: in the desktop app a link would replace the app's own page, so it opens in the default
 *  browser instead. In a browser the link opens as usual. */
export async function openInBrowser(e: MouseEvent, url: string | undefined) {
	if (!url || !inTauri()) return;
	e.preventDefault();
	(await import('@tauri-apps/plugin-opener')).openUrl(url);
}
