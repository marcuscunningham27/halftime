// App settings (Settings › General and Notifications), shared live and saved on every change.
import { events, type EventType } from './alerts';

type Saved = {
	/** Each alert type on or off for everything followed. */
	alerts: Record<EventType, boolean>;
	quietHours: { enabled: boolean; start: number; end: number };
	/** Closing the window leaves Halftime in the menu bar, still polling and alerting. */
	closeToMenu: boolean;
	/** "league:team" keys of followed teams whose alerts are off. */
	muted: string[];
	/** For weather at the venue; starts from the system's region. */
	units: 'metric' | 'imperial';
};

const defaults = (): Saved => ({
	alerts: Object.fromEntries(events.map((e) => [e.type, e.onByDefault])) as Record<EventType, boolean>,
	quietHours: { enabled: false, start: 22 * 60, end: 7 * 60 },
	closeToMenu: true,
	muted: [],
	units: typeof navigator !== 'undefined' && /-(US|LR|MM)$/.test(navigator.language) ? 'imperial' : 'metric'
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
