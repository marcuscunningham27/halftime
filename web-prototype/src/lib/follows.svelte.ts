// Followed leagues and teams, as SportsKit's FollowedLeague / FollowedTeam, shared live by every page.
// shortcut: kept in localStorage (the app's own WebKit / WebView2 storage in Tauri); move to a file or SQLite via Tauri if it needs syncing or backup.
import type { Team } from './espn';

export type FollowedTeam = { leagueID: string; team: Team };
type Saved = { leagues: string[]; teams: FollowedTeam[] };

function load(): Saved {
	try {
		const saved = JSON.parse(localStorage.getItem('follows') ?? '');
		return { leagues: saved.leagues ?? [], teams: saved.teams ?? [] };
	} catch {
		return { leagues: [], teams: [] };
	}
}

/** Oldest first, as the Swift sidebar sorts by when each was followed. */
export const follows = $state<Saved>(typeof localStorage === 'undefined' ? { leagues: [], teams: [] } : load());

function save() {
	try {
		localStorage.setItem('follows', JSON.stringify(follows));
	} catch {
		// Storage can be unavailable (private windows); follows then last until the app closes.
	}
}

/** League-qualified, since team IDs repeat across leagues (NFL 49ers and NHL Ducks are both 25). */
export const teamKey = (leagueID: string, teamID: string) => `${leagueID}:${teamID}`;
export const followedKeys = () => new Set(follows.teams.map((t) => teamKey(t.leagueID, t.team.id)));

export const isFollowingLeague = (leagueID: string) => follows.leagues.includes(leagueID);
export const isFollowingTeam = (leagueID: string, teamID: string) => follows.teams.some((t) => t.leagueID === leagueID && t.team.id === teamID);

export function toggleLeague(leagueID: string) {
	follows.leagues = isFollowingLeague(leagueID) ? follows.leagues.filter((id) => id !== leagueID) : [...follows.leagues, leagueID];
	save();
}

export function toggleTeam(leagueID: string, team: Team) {
	follows.teams = isFollowingTeam(leagueID, team.id)
		? follows.teams.filter((t) => !(t.leagueID === leagueID && t.team.id === team.id))
		: [...follows.teams, { leagueID, team: { id: team.id, abbreviation: team.abbreviation, displayName: team.displayName, shortName: team.shortName, color: team.color, alternateColor: team.alternateColor, logo: team.logo } }];
	save();
}
