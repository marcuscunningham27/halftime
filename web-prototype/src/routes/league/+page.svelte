<script lang="ts">
	// ScoreboardView.swift: a league (or, with ?team=, one team) for a chosen day in cards: live, upcoming, then results.
	// On today it also shows recent results grouped by day, then the standings; Upcoming lists the games ahead.
	// shortcut: no date picker field or follow button yet; Previous / Today / Next cover changing day.
	import { page } from '$app/state';
	import Backdrop from '$lib/Backdrop.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import ScoreCard from '$lib/ScoreCard.svelte';
	import { leagueByID, leagueLogo, scoreboard, recentResults, upcoming, standings as loadStandings, startOfDay, type Game, type Standings } from '$lib/espn';

	const league = $derived(leagueByID(page.url.searchParams.get('league')));
	const teamID = $derived(page.url.searchParams.get('team'));

	const days = ['Yesterday', 'Today', 'Upcoming'] as const;
	/** Days from today; Upcoming is its own mode. */
	let offset = $state(0);
	let showsUpcoming = $state(false);
	const picker = $derived(showsUpcoming ? 'Upcoming' : offset === 0 ? 'Today' : offset === -1 ? 'Yesterday' : undefined);

	let games = $state<Game[] | undefined>();
	let recent = $state<Game[]>([]);
	/** The games ahead, keyed by league and team so a page change never shows the last page's list. */
	let aheadFor = $state<{ key: string; games: Game[] } | undefined>();
	const pageKey = $derived(`${league.id}/${teamID}`);
	const ahead = $derived(aheadFor?.key === pageKey ? aheadFor.games : undefined);
	let table = $state<Standings | undefined>();
	let error = $state<string | undefined>();

	const involvesTeam = (g: Game) => !teamID || g.home.team.id === teamID || g.away.team.id === teamID;
	const team = $derived(
		[...(games ?? []), ...recent, ...(ahead ?? [])].flatMap((g) => [g.home.team, g.away.team]).find((t) => t.id === teamID) ??
			table?.groups.flatMap((g) => g.entries).find((e) => e.team.id === teamID)?.team
	);
	const title = $derived(teamID ? (team?.displayName ?? '') : league.abbreviation);

	async function refresh(o = offset) {
		try {
			const day = await scoreboard(league, startOfDay(o));
			if (o === offset) [games, error] = [day, undefined];
		} catch (e) {
			if (o === offset) error = e instanceof Error ? e.message : String(e);
		}
	}

	// The chosen day, polled every 15 seconds while it has a game live or to come, as ScoreboardPoller does.
	$effect(() => {
		const o = offset;
		league;
		games = undefined;
		refresh(o);
		const timer = setInterval(() => games?.some((g) => g.status !== 'final') && refresh(o), 15_000);
		return () => clearInterval(timer);
	});
	// Finals don't change, so recent results load once per visit; the standings too.
	$effect(() => {
		recent = [];
		if (offset === 0) recentResults(league, new Date()).then((r) => (recent = r)).catch(() => {});
	});
	$effect(() => {
		table = undefined;
		loadStandings(league).then((s) => (table = s)).catch(() => {});
	});
	// The next week of league games, or the next three weeks of a team's (weekly sports play less often).
	$effect(() => {
		const key = pageKey;
		if (!showsUpcoming || ahead) return;
		upcoming(league, teamID ? 21 : 7).then((games) => (aheadFor = { key, games }));
	});

	function choose(day: string) {
		showsUpcoming = day === 'Upcoming';
		offset = day === 'Yesterday' ? -1 : 0;
	}
	function shift(by: number) {
		showsUpcoming = false;
		offset += by;
	}

	const shown = $derived((games ?? []).filter(involvesTeam));
	/** Today's finals plus recent ones, newest first; a game that just finished appears once. */
	const finals = $derived.by(() => {
		const today = shown.filter((g) => g.status === 'final');
		const ids = new Set(today.map((g) => g.id));
		return [...today, ...recent.filter((g) => !ids.has(g.id) && involvesTeam(g))].sort((a, b) => b.startDate.getTime() - a.startDate.getTime());
	});
	const dayKey = (d: Date) => new Date(d).setHours(0, 0, 0, 0);
	const dayTitle = (key: number) => new Date(key).toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
	function byDay(list: Game[]): [number, Game[]][] {
		const groups = new Map<number, Game[]>();
		for (const g of list) groups.set(dayKey(g.startDate), [...(groups.get(dayKey(g.startDate)) ?? []), g]);
		return [...groups];
	}
	const subtitle = $derived(showsUpcoming ? 'Coming up' : startOfDay(offset).toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }));
	const gameLink = (g: Game) => `/game?league=${league.id}&id=${g.id}&day=${dayKey(g.startDate)}`;
	const teamLink = (id: string) => `/league?league=${league.id}&team=${id}`;
</script>

<svelte:head><title>{title || league.abbreviation} · Halftime</title></svelte:head>
<Backdrop color="#0d1f45" />

<header data-tauri-drag-region>
	<div class="titles" data-tauri-drag-region>
		<h1>{#if !teamID}<img src={leagueLogo(league)} alt="" width="24" height="24" />{:else if team?.logo}<img src={team.logo} alt="" width="26" height="26" />{/if}{title}</h1>
		<span class="subtitle">{subtitle}</span>
	</div>
	<div class="controls">
		<div class="group glass">
			<button aria-label="Previous day" title="Previous day" onclick={() => shift(-1)}>
				<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M10 3 5 8l5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" /></svg>
			</button>
			<button disabled={offset === 0 && !showsUpcoming} onclick={() => choose('Today')}>Today</button>
			<button aria-label="Next day" title="Next day" onclick={() => shift(1)}>
				<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M6 3l5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" /></svg>
			</button>
		</div>
		<button class="round glass" title="Refresh" aria-label="Refresh" onclick={() => ((aheadFor = undefined), refresh())}>
			<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M13 8a5 5 0 1 1-1.5-3.55M13 2.5v3h-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>
		</button>
	</div>
</header>

{#snippet section(name: string, list: Game[])}
	{#if list.length}
		<section class="sports-card">
			<h2>{name}</h2>
			{#each list as game, i (game.id)}
				{#if i > 0}<hr />{/if}
				<a class="row" href={gameLink(game)}><ScoreCard {game} /></a>
			{/each}
		</section>
	{/if}
{/snippet}

<main>
	<div class="picker"><GlassPicker options={[...days]} bind:selected={() => picker as (typeof days)[number], choose} /></div>

	{#if showsUpcoming}
		{#if !ahead}
			<p class="message">Loading…</p>
		{:else if ahead.filter(involvesTeam).length === 0}
			<p class="message">No {team?.shortName ?? league.abbreviation} games in the next {teamID ? 'three weeks' : 'week'}.</p>
		{:else}
			{#each byDay(ahead.filter(involvesTeam)) as [key, list] (key)}{@render section(dayTitle(key), list)}{/each}
		{/if}
	{:else if !games}
		<p class="message">{error ? `Couldn’t load scores: ${error}` : 'Loading…'}</p>
	{:else}
		{@render section('Live', shown.filter((g) => g.status === 'live'))}
		{@render section('Upcoming', shown.filter((g) => g.status === 'scheduled'))}
		{#if offset === 0}
			{#if shown.length === 0 && finals.length}
				<p class="message small">There are no {team?.shortName ?? league.abbreviation} games today.</p>
				<h1 class="heading">Recent Results</h1>
			{/if}
			{#each byDay(finals) as [key, list] (key)}{@render section(key === dayKey(new Date()) ? 'Final' : dayTitle(key), list)}{/each}
		{:else}
			{@render section('Final', shown.filter((g) => g.status === 'final'))}
		{/if}
		{#if shown.length === 0 && (offset !== 0 || finals.length === 0)}
			<p class="message">There are no {team?.shortName ?? league.abbreviation} games on this day.</p>
		{/if}

		{#if !teamID && offset === 0 && table}
			<!-- StandingsView: one card per conference or division. -->
			{#each table.groups as group}
				<section class="sports-card">
					<h2>{group.name}</h2>
					<table>
						<thead><tr><th colspan="3"></th>{#each table.columns as c}<th class="num">{c}</th>{/each}</tr></thead>
						<tbody>
							{#each group.entries as entry, i (entry.team.id)}
								<tr>
									<td class="rank">{i + 1}</td>
									<td class="logo"><img src={entry.team.logo} alt="" width="22" height="22" /></td>
									<td class="name"><a href={teamLink(entry.team.id)}>{entry.team.shortName}</a></td>
									{#each entry.values as v}<td class="num">{v}</td>{/each}
								</tr>
							{/each}
						</tbody>
					</table>
				</section>
			{/each}
		{/if}
	{/if}
</main>

<style>
	header {
		position: sticky;
		top: 0;
		z-index: 2;
		min-height: 52px;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 6px 16px 6px var(--titlebar-inset);
		box-sizing: border-box;
	}
	.titles {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	h1 {
		display: flex;
		align-items: center;
		gap: 8px;
		margin: 0;
		font-size: 17px;
		font-weight: 700;
		white-space: nowrap;
	}
	h1 img {
		filter: drop-shadow(0 0 0.6px rgba(255, 255, 255, 0.9));
	}
	.subtitle {
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	.controls {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.group {
		display: flex;
		align-items: center;
		border-radius: 999px;
		padding: 2px;
	}
	.group button {
		height: 28px;
		min-width: 28px;
		padding: 0 10px;
		border-radius: 999px;
		display: grid;
		place-items: center;
		font-size: var(--subheadline);
		font-weight: 500;
	}
	.group button:hover:not(:disabled) {
		background: rgba(255, 255, 255, 0.1);
	}
	.group button:disabled {
		color: var(--tertiary);
	}
	.round {
		width: 32px;
		height: 32px;
		border-radius: 50%;
		display: grid;
		place-items: center;
	}
	main {
		max-width: 760px;
		margin: 0 auto;
		padding: 20px;
		box-sizing: border-box;
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.picker {
		display: flex;
		justify-content: center;
	}
	.row {
		display: block;
		border-radius: 12px;
	}
	.row:hover {
		background: rgba(255, 255, 255, 0.04);
	}
	.heading {
		font-size: var(--title3);
	}
	.message {
		text-align: center;
		color: var(--secondary);
		margin: 60px 0;
	}
	.message.small {
		margin: 20px 0 0;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		margin: 4px 0;
	}
	th {
		font-size: var(--caption);
		font-weight: 400;
		color: var(--secondary);
		padding-bottom: 6px;
	}
	td {
		padding: 5px 0;
	}
	.num {
		text-align: right;
		padding-left: 12px;
		width: 1%;
		white-space: nowrap;
	}
	.rank {
		width: 24px;
		color: var(--secondary);
	}
	.logo {
		width: 30px;
	}
	.name a:hover {
		text-decoration: underline;
	}
</style>
