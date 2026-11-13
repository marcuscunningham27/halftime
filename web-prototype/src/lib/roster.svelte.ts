// Your fantasy players across every saved league, for marking them on NFL game pages (FantasyStore.loadRoster and
// FantasyRoster): starred, with a yellow tint, in the Gamecast, Play-By-Play and Box Score.
import * as F from './fantasy';

export const roster = $state<{ players: F.Player[] }>({ players: [] });
let loaded = 0;

/** Loads every league's team, at most every 10 minutes; a league that fails is just left out. */
export async function loadRoster() {
	if (Date.now() - loaded < 600_000) return;
	loaded = Date.now();
	const leagues = F.store.leagues();
	if (!leagues.length) return;
	const { season } = await F.nflState();
	const teams = await Promise.all(leagues.map((l) => F.team(l, season).catch(() => undefined)));
	const players: F.Player[] = [];
	for (const t of teams) {
		for (const p of t ? [...t.lineup.flatMap((s) => (s.player ? [s.player] : [])), ...t.bench] : []) {
			if (!players.some((q) => q.id === p.id)) players.push(p);
		}
	}
	roster.players = players;
}

/** Your players a play names, and whether a box score row is yours (FantasyRoster). */
export const playersIn = (text: string) => F.playersIn(text, roster.players);
export const isRostered = (athleteID: string, name: string) => F.isRostered(athleteID, name, roster.players);
