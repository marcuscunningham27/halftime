<script lang="ts">
	// FantasyView.swift's Lineup tab: matchup card, then starters and bench with this week's projection and last week's points.
	// shortcut: Past Week, Upcoming, Season and News tabs and the AI briefing aren't ported; add them if the prototype is a go.
	import Backdrop from '$lib/Backdrop.svelte';
	import LeagueSetup from '$lib/LeagueSetup.svelte';
	import { nflWeek, type Game } from '$lib/espn';
	import * as F from '$lib/fantasy';

	let leagues = $state(F.store.leagues());
	let activeID = $state(F.store.activeID());
	const active = $derived(leagues.find((l) => F.refID(l) === activeID) ?? leagues[0]);
	let managing = $state(F.store.leagues().length === 0);
	let menuOpen = $state(false);

	type Base = { team: F.Team; week: number; games: Game[]; matchup?: F.Matchup; projections: Record<string, number>; lastWeek: Record<string, number> };
	let base = $state<Base | undefined>();
	let error = $state<string | undefined>();

	async function load(league: F.LeagueRef) {
		try {
			const state = await F.nflState(); // the NFL calendar, the same for every provider
			const current = F.weekOf(new Date(), state);
			const [team, currentGames] = await Promise.all([F.team(league, state.season), nflWeek(state.season, current)]);
			// Upcoming is the current week while it has games left to play, else the next.
			const week = currentGames.some((g) => g.status === 'scheduled') ? current : current + 1;
			const games = week === current ? currentGames : await nflWeek(state.season, week);
			// Extras for the lineup; any that fail just leave their numbers blank.
			const [projections, lastWeek] = await Promise.all([
				F.projections(league, state.season, week).catch(() => ({})),
				F.points(league, state.season, week - 1).catch(() => ({}))
			]);
			const matchup = await F.matchup(league, state.season, week, projections).catch(() => undefined);
			if (league === active) [base, error] = [{ team, week, games, matchup, projections, lastWeek }, undefined];
		} catch (e) {
			if (league === active) error = e instanceof Error ? e.message : String(e);
		}
	}

	$effect(() => {
		base = undefined;
		error = undefined;
		if (active && !managing) load(active);
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

	function status(p: F.Player): [string, string] {
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
				<hr />
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
			{@const [text, color] = status(p)}
			{@const logo = p.position === 'DEF' ? teamLogo(p.team, b.games) : undefined}
			<span class="photo">
				{#if logo}<img src={logo} alt="" width="30" height="30" />{:else if p.photo}<img src={p.photo} alt="" class="headshot" />{/if}
			</span>
			<div class="info">
				<span><strong>{p.name}</strong> <span class="secondary">{[p.team, p.position].filter(Boolean).join(' - ')}</span></span>
				<span class="caption">
					<span class="tag" style:--c={color} title={p.injury ? [p.injury.status, p.injury.detail].filter(Boolean).join(' · ') : text}>{text}</span>
					{nextGame(p, b.games) ?? 'No game to come this week'}
				</span>
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
		{#if base.matchup}
			{@const chance = F.winProbability(base.matchup)}
			<section class="card">
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
		<section class="card">
			{@render columns('Starters', base.week)}
			{#each base.team.lineup as slot}{@render row(slot.label, slot.player, base)}{/each}
		</section>
		{#if base.team.bench.length}
			<section class="card bench">
				{@render columns('Bench', base.week)}
				{#each base.team.bench as p (p.id)}{@render row('BN', p, base)}{/each}
			</section>
		{/if}
	{/if}
</main>

<style>
	header {
		position: sticky;
		top: 0;
		z-index: 2;
		height: 52px;
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 16px 0 var(--titlebar-inset);
	}
	.menu {
		position: relative;
	}
	.title {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 10px;
		border-radius: 8px;
		font-size: var(--headline);
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
		top: 34px;
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
		gap: 16px;
	}
	.card {
		padding: 12px 16px;
		border-radius: 22px;
		background: rgba(0, 0, 0, 0.38);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
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
	.message {
		text-align: center;
		color: var(--secondary);
		margin-top: 80px;
	}
</style>
