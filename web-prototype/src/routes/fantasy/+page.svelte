<script lang="ts">
	// FantasyView.swift: Lineup, Past Games, Upcoming, Season and News for the league picked from the title menu.
	import Backdrop from '$lib/Backdrop.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import LeagueSetup from '$lib/LeagueSetup.svelte';
	import FantasyGames, { type Entry } from '$lib/FantasyGames.svelte';
	import FantasySeason from '$lib/FantasySeason.svelte';
	import FantasyNews from '$lib/FantasyNews.svelte';
	import WeekBriefing from '$lib/WeekBriefing.svelte';
	import FantasyBadge from '$lib/FantasyBadge.svelte';
	import { nflWeek, summary, type Game, type GameDetail } from '$lib/espn';
	import * as F from '$lib/fantasy';

	let leagues = $state(F.store.leagues());
	let activeID = $state(F.store.activeID());
	const active = $derived(leagues.find((l) => F.refID(l) === activeID) ?? leagues[0]);
	let managing = $state(F.store.leagues().length === 0);
	let menuOpen = $state(false);
	const tabs = ['Lineup', 'Past Games', 'Upcoming', 'Season', 'News'] as const;
	let tab = $state<(typeof tabs)[number]>('Lineup');

	type Base = {
		league: F.LeagueRef;
		state: F.NFLState;
		team: F.Team;
		/** The upcoming week (this one while it has games left), and the latest with games under way or played. */
		week: number;
		latestWeek: number;
		games: Game[];
		matchup?: F.Matchup;
		projections: Record<string, number>;
		lastWeek: Record<string, number>;
		calendar?: F.Calendar;
		byes: Record<string, number>;
		news: Record<string, F.News[]>;
	};
	let base = $state<Base | undefined>();
	/** The week briefing, kept here so switching tabs doesn't rewrite it; cleared on each load. */
	let briefing = $state<string | undefined>();
	let error = $state<string | undefined>();

	// Each team's bye, from the 18 regular-season weeks; fetched once per season.
	const byeCache = new Map<string, Promise<Record<string, number>>>();
	function nflByes(season: string) {
		if (!byeCache.has(season)) {
			const weeks = Array.from({ length: 18 }, (_, i) => i + 1);
			byeCache.set(season, Promise.all(weeks.map((w) => nflWeek(season, w))).then((all) =>
				F.byes(new Map(all.map((games, i) => [i + 1, games.map((g) => ({ home: g.home.team.abbreviation, away: g.away.team.abbreviation }))])))
			));
		}
		// A failed week isn't kept, so the next load asks again.
		return byeCache.get(season)!.catch(() => (byeCache.delete(season), {}));
	}

	async function load(league: F.LeagueRef) {
		try {
			const state = await F.nflState(); // the NFL calendar, the same for every provider
			const current = F.weekOf(new Date(), state);
			const [team, currentGames] = await Promise.all([F.team(league, state.season), nflWeek(state.season, current)]);
			// The latest week is the current one once its games have kicked off, else the one before;
			// upcoming is the current week while it has games left to play, else the next.
			const latestWeek = currentGames.some((g) => g.status !== 'scheduled') ? current : Math.max(1, current - 1);
			const week = currentGames.some((g) => g.status === 'scheduled') ? current : current + 1;
			const games = week === current ? currentGames : await nflWeek(state.season, week);
			// Extras; any that fail just leave their part blank.
			const [projections, lastWeek, calendar, byes, newsLists] = await Promise.all([
				F.projections(league, state.season, week).catch(() => ({})),
				F.points(league, state.season, week - 1).catch(() => ({})),
				F.calendar(league, state).catch(() => undefined),
				nflByes(state.season),
				Promise.all(players(team).map((p) => (p.espnID ? F.news(p.espnID).catch(() => []) : Promise.resolve([] as F.News[]))))
			]);
			const matchup = await F.matchup(league, state.season, week, projections).catch(() => undefined);
			const news = Object.fromEntries(players(team).map((p, i) => [p.id, newsLists[i]]));
			if (league === active) [base, error] = [{ league, state, team, week, latestWeek, games, matchup, projections, lastWeek, calendar, byes, news }, undefined];
		} catch (e) {
			if (league === active) error = e instanceof Error ? e.message : String(e);
		}
	}

	$effect(() => {
		base = undefined;
		error = undefined;
		briefing = undefined;
		past = undefined;
		season = undefined;
		chosenWeek = undefined;
		if (active && !managing) load(active);
	});

	const players = (t: F.Team) => [...t.lineup.flatMap((s) => (s.player ? [s.player] : [])), ...t.bench];
	const involves = (g: Game, t: F.Team) => players(t).some((p) => p.team === g.away.team.abbreviation || p.team === g.home.team.abbreviation);

	/** "Passing: 22/37 C/ATT, 245 YDS, 2 TD" for each box score category the player appears in. */
	function stats(p: F.Player, g: Game, detail?: GameDetail): string[] {
		if (!detail) return [];
		// Name matches only look at the player's own team, so two same-named players in one game can't swap.
		const teamID = [g.away.team, g.home.team].find((t) => t.abbreviation === p.team)?.id;
		const id = p.espnID ?? detail.boxScores.filter((b) => b.teamID === teamID).flatMap((b) => b.rows).find((r) => F.sameName(r.name, p.name))?.id;
		const skipped = ['AVG', 'LONG', 'QBR', 'RTG', 'YDS/G'];
		return detail.boxScores.flatMap((box) => {
			const row = box.rows.find((r) => r.id === id);
			if (!row) return [];
			const category = box.title.split(' ').at(-1) ?? '';
			return [`${category}: ${box.labels.map((l, i) => (skipped.includes(l) ? '' : `${row.stats[i]} ${l}`)).filter(Boolean).join(', ')}`];
		});
	}

	function entry(g: Game, t: F.Team, points: Record<string, number>, detail?: GameDetail): Entry {
		const sides = [g.away.team.abbreviation, g.home.team.abbreviation];
		const starters = new Set(t.lineup.flatMap((s) => (s.player ? [s.player.id] : [])));
		const lines = players(t)
			.filter((p) => sides.includes(p.team ?? ''))
			.map((p) => ({ player: p, isStarter: starters.has(p.id), points: points[p.id], stats: stats(p, g, detail) }))
			.sort((a, b) => Number(b.isStarter) - Number(a.isStarter) || (b.points ?? 0) - (a.points ?? 0));
		return { game: g, lines };
	}

	// Past Games: the played week on show (nil follows the latest), loaded when the tab opens or the week changes.
	let chosenWeek = $state<number | undefined>();
	let past = $state<{ week: number; entries: Entry[] } | undefined>();
	const pastWeek = $derived(chosenWeek ?? base?.latestWeek);
	$effect(() => {
		const b = base, week = pastWeek;
		if (tab !== 'Past Games' || !b || !week || past?.week === week) return;
		(async () => {
			const played = (await nflWeek(b.state.season, week))
				.filter((g) => g.status !== 'scheduled' && involves(g, b.team))
				.sort((a, c) => Number(c.status === 'live') - Number(a.status === 'live') || c.startDate.getTime() - a.startDate.getTime());
			const [points, details] = await Promise.all([
				F.points(b.league, b.state.season, week).catch(() => ({}) as Record<string, number>),
				Promise.all(played.map((g) => summary(g).catch(() => undefined)))
			]);
			if (b === base && week === pastWeek) past = { week, entries: played.map((g, i) => entry(g, b.team, points, details[i])) };
		})();
	});

	// Season: every completed week's starters, and the standings.
	let season = $state<{ trend: F.SeasonTrend; standings: F.Standing[] } | undefined>();
	$effect(() => {
		const b = base;
		if (tab !== 'Season' || !b || season) return;
		const weeks = Array.from({ length: Math.max(0, b.week - 1) }, (_, i) => i + 1);
		Promise.all([F.season(b.league, b.state.season, weeks).catch(() => []), F.standings(b.league, b.state.season).catch(() => [])]).then(([results, standings]) => {
			if (b === base) season = { trend: F.seasonTrend(results), standings };
		});
	});

	function choose(league: F.LeagueRef) {
		activeID = F.refID(league);
		F.store.setActive(activeID);
		menuOpen = false;
	}

	/** "vs DAL · Sun 1:00 PM" or "@ KC · Live". */
	function nextGame(p: F.Player, games: Game[]): string | undefined {
		const g = games.find((g) => g.status !== 'final' && (g.home.team.abbreviation === p.team || g.away.team.abbreviation === p.team));
		if (!g) return;
		const home = g.home.team.abbreviation === p.team;
		const when = g.status === 'live' ? 'Live' : g.startDate.toLocaleString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' });
		return `${home ? 'vs' : '@'} ${home ? g.away.team.abbreviation : g.home.team.abbreviation} · ${when}`;
	}

	const teamLogo = (abbr: string | undefined, games: Game[]) =>
		games.flatMap((g) => [g.home.team, g.away.team]).find((t) => t.abbreviation === abbr)?.logo;

	function status(p: F.Player, onBye: boolean): [string, string] {
		if (onBye) return ['Bye', '#8e8e93'];
		const s = F.severity(p.injury);
		return s === 0 ? ['Healthy', '#30d158'] : s === 1 ? ['Q', '#ffd60a'] : s === 2 ? ['D', '#ff9f0a'] : [p.injury?.status ?? 'Out', '#ff453a'];
	}

	const fmt = (n: number | undefined, digits = 1) => (n === undefined ? '–' : n.toFixed(digits));
	const percent = (v: number) => `${Math.round(v * 100)}%`;
</script>

<svelte:head><title>{active?.name ?? 'Fantasy'} · Halftime</title></svelte:head>
<Backdrop color="#0d1f45" />

<header data-tauri-drag-region>
	<div class="menu">
		<button class="title" onclick={() => (menuOpen = !menuOpen)} aria-haspopup="menu" aria-expanded={menuOpen}>
			<FantasyBadge size={24} label="" />
			{active?.name ?? 'Fantasy'}
			<svg viewBox="0 0 12 12" width="9" height="9" aria-hidden="true"><path d="M2.5 4.5 6 8l3.5-3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" /></svg>
		</button>
		{#if menuOpen}
			<!-- The league dropdown, grouped by app, as the Swift toolbar menu. -->
			<div class="dropdown glass" role="menu">
				{#each [['sleeper', 'Sleeper'], ['espn', 'ESPN Fantasy']] as [provider, title]}
					{@const group = leagues.filter((l) => l.provider === provider)}
					{#if group.length}
						<span class="group">{title}</span>
						{#each group as league (F.refID(league))}
							<button role="menuitemradio" aria-checked={league === active} onclick={() => choose(league)}>
								<span class="check">{league === active ? '✓' : ''}</span>{league.name}
							</button>
						{/each}
					{/if}
				{/each}
				<!-- Only separates leagues from Manage Leagues…; with none added it would sit alone at the top. -->
				{#if leagues.length}<hr />{/if}
				<button role="menuitem" onclick={() => ((managing = true), (menuOpen = false))}><span class="check"></span>Manage Leagues…</button>
			</div>
		{/if}
	</div>
	{#if active && !managing}
		<button class="round glass" title="Refresh" aria-label="Refresh" onclick={() => load(active)}>
			<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M13 8a5 5 0 1 1-1.5-3.55M13 2.5v3h-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>
		</button>
	{/if}
</header>

{#snippet columns(title: string, week: number)}
	<div class="columns"><h2>{title}</h2><span>PROJ</span><span>WK {Math.max(1, week - 1)}</span></div>
{/snippet}

{#snippet row(label: string, p: F.Player | undefined, b: Base)}
	<div class="player">
		<span class="slot">{label}</span>
		{#if p}
			{@const bye = p.team ? b.byes[p.team] : undefined}
			{@const onBye = bye === b.week}
			{@const [text, color] = status(p, onBye)}
			{@const logo = p.position === 'DEF' ? teamLogo(p.team, b.games) : undefined}
			<span class="photo">
				{#if logo}<img src={logo} alt="" width="30" height="30" />{:else if p.photo}<img src={p.photo} alt="" class="headshot" />{/if}
			</span>
			<div class="info">
				<span><strong>{p.name}</strong> <span class="secondary">{[p.team, p.position].filter(Boolean).join(' - ')}</span></span>
				<span class="caption">
					<span class="tag" style:--c={color} title={p.injury ? [p.injury.status, p.injury.detail].filter(Boolean).join(' · ') : text}>{text}</span>
					{nextGame(p, b.games) ?? (onBye ? 'On bye this week' : 'No game to come this week')}
					{#if bye && !onBye}· Bye Wk {bye}{/if}
				</span>
				{#if b.news[p.id]?.[0]}<span class="news" title={b.news[p.id][0].story ?? b.news[p.id][0].headline}>{b.news[p.id][0].headline}</span>{/if}
			</div>
			<span class="num">{fmt(b.projections[p.id])}</span>
			<span class="num dim">{fmt(b.lastWeek[p.id])}</span>
		{:else}
			<span class="secondary empty">Empty</span>
		{/if}
	</div>
{/snippet}

{#snippet side(s: F.Side, leading: boolean)}
	<div class="side" class:trailing={!leading}>
		<div class="who">
			<span class="avatar">{#if s.avatar}<img src={s.avatar} alt="" />{/if}</span>
			<span class="names">{#if s.manager}<small>@{s.manager}</small>{/if}<strong>{s.teamName}</strong></span>
		</div>
		<span class="big">{s.points > 0 ? s.points.toFixed(2) : '–'}</span>
		<span class="proj"><small>PROJ</small> {s.projected.toFixed(2)}</span>
	</div>
{/snippet}

<main>
	{#if managing}
		<LeagueSetup bind:leagues onclose={() => ((managing = false), (activeID = F.store.activeID()))} />
	{:else if error}
		<p class="message" role="alert">{error}</p>
	{:else if !base}
		<p class="message">Loading your team…</p>
	{:else}
		<div class="tabs"><GlassPicker options={[...tabs]} bind:selected={tab} /></div>
		{#if tab === 'Past Games'}
			<label class="week-picker">
				<span class="sr-only">Week</span>
				<select bind:value={() => pastWeek, (w) => (chosenWeek = w === base?.latestWeek ? undefined : w)}>
					{#each Array.from({ length: base.latestWeek }, (_, i) => base!.latestWeek - i) as w}<option value={w}>Week {w}</option>{/each}
				</select>
			</label>
			{#if past && past.week === pastWeek}
				<FantasyGames entries={past.entries} empty="None of your players played this week." />
			{:else}<p class="message">Loading week…</p>{/if}
		{:else if tab === 'Upcoming'}
			<h1 class="week-title">Week {base.week}</h1>
			<FantasyGames
				entries={base.games.filter((g) => g.status === 'scheduled' && involves(g, base!.team)).sort((a, c) => a.startDate.getTime() - c.startDate.getTime()).map((g) => entry(g, base!.team, {}))}
				empty="None of your players have games coming up."
			/>
		{:else if tab === 'Season'}
			{#if season}<FantasySeason trend={season.trend} standings={season.standings} />{:else}<p class="message">Loading the season…</p>{/if}
		{:else if tab === 'News'}
			<FantasyNews team={base.team} byes={base.byes} week={base.week} calendar={base.calendar} news={base.news} provider={base.league.provider === 'sleeper' ? 'Sleeper' : 'ESPN Fantasy'} />
		{:else}
		{#if base.matchup}
			{@const chance = F.winProbability(base.matchup)}
			<section class="sports-card">
				<h2>Week {base.week} Matchup</h2>
				<div class="matchup">
					{@render side(base.matchup.me, true)}
					<span class="vs">VS</span>
					{#if base.matchup.opponent}{@render side(base.matchup.opponent, false)}{:else}<span class="secondary bye">Bye week</span>{/if}
				</div>
				{#if chance !== undefined}
					<div class="chance" role="img" aria-label="Win chance {percent(chance)} to {percent(1 - chance)}">
						<div class="bar">
							<span style:width="{chance * 100}%" style:background={chance >= 0.5 ? '#30d158' : '#ff375f'}></span>
							<span style:background={chance < 0.5 ? '#30d158' : '#ff375f'}></span>
						</div>
						<div class="labels"><b>{percent(chance)}</b><small>Win chance</small><b>{percent(1 - chance)}</b></div>
					</div>
				{/if}
			</section>
		{/if}
		<WeekBriefing team={base.team} week={base.week} matchup={base.matchup} projections={base.projections} byes={base.byes} news={base.news} bind:briefing />
		<section class="sports-card">
			{@render columns('Starters', base.week)}
			{#each base.team.lineup as slot}{@render row(slot.label, slot.player, base)}{/each}
		</section>
		{#if base.team.bench.length}
			<section class="sports-card bench">
				{@render columns('Bench', base.week)}
				{#each base.team.bench as p (p.id)}{@render row('BN', p, base)}{/each}
			</section>
		{/if}
		{/if}
	{/if}
</main>

<style>
	header {
		justify-content: space-between;
	}
	.menu {
		position: relative;
	}
	/* The same size as a league page's title, the jersey standing in for the league logo. The padding is pulled back
	   so the badge lines up where a league logo starts; it's only there for the hover highlight. */
	.title {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-left: -8px;
		padding: 4px 10px 4px 8px;
		border-radius: 10px;
		font-size: 17px;
		font-weight: 700;
	}
	.title:hover {
		background: rgba(255, 255, 255, 0.08);
	}
	.title svg {
		color: var(--secondary);
	}
	.dropdown {
		position: absolute;
		top: calc(100% + 4px);
		left: 0;
		min-width: 230px;
		padding: 5px;
		border-radius: 12px;
		background: rgba(40, 40, 44, 0.72);
		display: flex;
		flex-direction: column;
	}
	.dropdown .group {
		padding: 4px 10px 2px;
		font-size: var(--caption);
		font-weight: 600;
		color: var(--secondary);
	}
	.dropdown button {
		display: flex;
		align-items: center;
		padding: 4px 8px;
		border-radius: 6px;
		text-align: left;
	}
	.dropdown button:hover {
		background: #0a84ff;
	}
	.check {
		width: 18px;
		font-size: 11px;
	}
	.dropdown hr {
		border: 0;
		border-top: 1px solid var(--separator);
		margin: 4px 8px;
	}
	main {
		max-width: 760px;
		margin: 0 auto;
		padding: 20px;
		box-sizing: border-box;
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	h2 {
		margin: 0;
		font-size: var(--headline);
	}
	.matchup {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 10px 0;
	}
	.side {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 10px;
	}
	.side.trailing {
		align-items: flex-end;
	}
	.who {
		display: flex;
		align-items: center;
		gap: 10px;
		min-width: 0;
		max-width: 100%;
	}
	.trailing .who {
		flex-direction: row-reverse;
	}
	.names {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.trailing .names {
		align-items: flex-end;
	}
	.names strong, .names small {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}
	small {
		font-size: var(--caption);
		color: var(--secondary);
	}
	.avatar, .photo {
		flex: none;
		width: 44px;
		height: 44px;
		border-radius: 50%;
		overflow: hidden;
		display: grid;
		place-items: center;
		background: rgba(255, 255, 255, 0.12);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.25);
	}
	.avatar img, .headshot {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.big {
		font: 700 34px/1 'Chakra Petch', sans-serif;
	}
	.proj {
		font-size: var(--caption);
		font-weight: 600;
	}
	.vs {
		flex: none;
		width: 36px;
		height: 36px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		background: rgba(255, 255, 255, 0.1);
		font-size: var(--caption);
		font-weight: 800;
		color: var(--secondary);
	}
	.bye {
		flex: 1;
		text-align: center;
	}
	.chance {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding-bottom: 6px;
	}
	.bar {
		display: flex;
		gap: 3px;
		height: 6px;
	}
	.bar span {
		border-radius: 3px;
		min-width: 4px;
	}
	.bar span:last-child {
		flex: 1;
	}
	.labels {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: var(--caption);
	}
	.columns {
		display: flex;
		align-items: center;
		padding-bottom: 4px;
		font-size: var(--caption);
		font-weight: 600;
		color: var(--secondary);
	}
	.columns h2 {
		flex: 1;
		color: var(--label);
	}
	.columns span, .num {
		width: 56px;
		text-align: right;
	}
	.player {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 6px 0;
	}
	.bench .player {
		opacity: 0.7;
	}
	.slot {
		flex: none;
		width: 44px;
		padding: 3px 0;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.12);
		text-align: center;
		font-size: var(--caption);
		font-weight: 700;
	}
	.info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.info > span:first-child {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.secondary {
		color: var(--secondary);
		font-size: var(--subheadline);
	}
	.caption {
		font-size: var(--caption);
		color: var(--secondary);
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.tag {
		padding: 1px 6px;
		border-radius: 999px;
		font-weight: 700;
		color: var(--c);
		background: color-mix(in srgb, var(--c) 18%, transparent);
	}
	.num {
		flex: none;
		font: 700 20px/1 'Chakra Petch', sans-serif;
	}
	.num.dim {
		color: var(--secondary);
	}
	.empty {
		flex: 1;
	}
	.tabs {
		display: flex;
		justify-content: center;
	}
	.news {
		font-size: var(--caption);
		color: var(--tertiary);
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.week-title, .week-picker select {
		margin: 0;
		font-size: 22px;
		font-weight: 700;
	}
	/* "Week 6 ⌄", a menu of every played week. */
	.week-picker select {
		appearance: none;
		-webkit-appearance: none;
		background: none;
		border: 0;
		color: var(--label);
		padding-right: 18px;
		background-image: linear-gradient(45deg, transparent 50%, var(--secondary) 50%), linear-gradient(135deg, var(--secondary) 50%, transparent 50%);
		background-position: right 6px center, right 1px center;
		background-size: 5px 5px;
		background-repeat: no-repeat;
		font-family: inherit;
	}
	.week-picker select option {
		font-size: 13px;
		color: initial;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
	}
	.message {
		text-align: center;
		color: var(--secondary);
		margin-top: 80px;
	}
</style>
