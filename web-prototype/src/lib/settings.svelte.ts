// App settings (Settings › General and Notifications), shared live and saved on every change.
import { events, scopePrefix, type EventType } from './alerts';

type Saved = {
	/** Each alert type on or off for everything followed. */
	alerts: Record<EventType, boolean>;
	quietHours: { enabled: boolean; start: number; end: number };
	/** Closing the window leaves Halftime in the menu bar, still polling and alerting. */
	closeToMenu: boolean;
	/** A league's or followed team's own alert settings, by scopePrefix + event; absent follows the wider setting. */
	overrides: Record<string, boolean>;
	/** "league:team" keys of followed teams whose alerts are off. */
	muted: string[];
	/** The Dock icon (macOS) or window and taskbar icon (Windows): black or white background. */
	appIcon: 'dark' | 'light';
	/** For weather at the venue; starts from the system's region. */
	units: 'metric' | 'imperial';
	/** Leagues picked on the welcome screen (or in Settings) for the sidebar and Home; null until the first choice. */
	shownLeagues: string[] | null;
	/** League IDs in the order dragged into in the sidebar, which Home's sections follow; empty = the usual order. */
	leagueOrder: string[];
};

const defaults = (): Saved => ({
	alerts: Object.fromEntries(events.map((e) => [e.type, e.onByDefault])) as Record<EventType, boolean>,
	quietHours: { enabled: false, start: 22 * 60, end: 7 * 60 },
	closeToMenu: true,
	overrides: {},
	appIcon: 'dark',
	muted: [],
	units: typeof navigator !== 'undefined' && /-(US|LR|MM)$/.test(navigator.language) ? 'imperial' : 'metric',
	shownLeagues: null,
	leagueOrder: []
});

function load(): Saved {
	const base = defaults();
	try {
		const saved = JSON.parse(localStorage.getItem('settings') ?? '{}');
		return { ...base, ...saved, alerts: { ...base.alerts, ...saved.alerts }, quietHours: { ...base.quietHours, ...saved.quietHours } };
	} catch {
		return base;
	}
}

export const settings = $state<Saved>(typeof localStorage === 'undefined' ? defaults() : load());

/** Call after changing `settings`; bindings in Settings do this through their onchange. */
export function saveSettings() {
	try {
		localStorage.setItem('settings', JSON.stringify(settings));
	} catch {
		// Storage unavailable: settings last until the app closes.
	}
}

export function setOverride(type: EventType, on: boolean, leagueID: string, teamID?: string) {
	settings.overrides = { ...settings.overrides, [scopePrefix(leagueID, teamID) + type]: on };
	saveSettings();
}

/** Drops a league's or team's own settings, so it follows the wider ones again. */
export function clearOverrides(leagueID: string, teamID?: string) {
	const prefix = scopePrefix(leagueID, teamID);
	settings.overrides = Object.fromEntries(Object.entries(settings.overrides).filter(([k]) => !k.startsWith(prefix)));
	saveSettings();
}
