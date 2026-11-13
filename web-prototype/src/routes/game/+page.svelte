<script lang="ts">
	// GameDetailView.swift: header, NFL Gamecast, recap, then Overview / Stats / Play-By-Play / Box Score.
	// shortcut: no Ask About the Game card or AI summary yet.
	import { page } from '$app/state';
	import Backdrop from '$lib/Backdrop.svelte';
	import FieldView from '$lib/FieldView.svelte';
	import Court from '$lib/Court.svelte';
	import Rink from '$lib/Rink.svelte';
	import Pitch from '$lib/Pitch.svelte';
	import Gamecast from '$lib/Gamecast.svelte';
	import Football from '$lib/Football.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import Overview from '$lib/tabs/Overview.svelte';
	import TeamStats from '$lib/tabs/TeamStats.svelte';
	import PlayByPlay from '$lib/tabs/PlayByPlay.svelte';
	import BoxScore from '$lib/tabs/BoxScore.svelte';
	import {
		leagueByID, scoreboard, summary, startOfDay, fieldState, headlineStatus, hasBall, isLosing, periodLabel, backdropHex, hex,
		possession, type Game, type GameDetail, type Competitor
	} from '$lib/espn';

	const id = page.url.searchParams.get('id');
	// The game's day as a fixed time (local midnight), so a live game past midnight is still found on the next poll.
	const dayParam = Number(page.url.searchParams.get('day'));
	const day = dayParam ? new Date(dayParam) : startOfDay(0);
	const league = leagueByID(page.url.searchParams.get('league'));
	const football = league.id === 'nfl';

	let game = $state<Game | undefined>();
	let detail = $state<GameDetail | undefined>();
	const tabs = ['Overview', 'Stats', 'Play-By-Play', 'Box Score'] as const;
	let tab = $state<(typeof tabs)[number] | undefined>();
	let recapOpen = $state(false);
	const drives = $derived(detail?.drives);
	let error = $state<string | undefined>();

	async function load() {
		try {
			// A miss keeps the game already shown rather than blanking the page.
			const current = (await scoreboard(league, day)).find((g) => g.id === id) ?? game;
			if (!current) throw new Error('Game not found');
			game = current;
			// Before kickoff there are no stats yet, so start on the overview.
			tab ??= current.status === 'scheduled' ? 'Overview' : 'Stats';
			detail = await summary(current);
			error = undefined;
		} catch (e) {
			error = String(e);
		}
	}

	// Polls every 15 seconds until the game is over, so a page opened before kickoff goes live by itself.
	$effect(() => {
		load();
		const timer = setInterval(() => game?.status !== 'final' && load(), 15_000);
		return () => clearInterval(timer);
	});

	const field = $derived(football && game ? fieldState(game, drives) : undefined);
	const plays = $derived(detail?.plays ?? []);
	/** Located shots: basketball without free throws (they all come from the same spot), hockey shots and goals. */
	const shots = $derived(
		league.id === 'nba' ? plays.filter((p) => p.location && p.isShot && !/free throw/i.test(p.type ?? ''))
		: league.id === 'nhl' ? plays.filter((p) => p.location && /shot|goal/i.test(p.type ?? ''))
		: []
	);
	// A surface shows while live, or afterwards when there's something to draw on it.
	const hasSurface = $derived(game?.status === 'live' || shots.length > 0 || (detail?.shots.length ?? 0) > 0);
	const ballWith = $derived(game?.status === 'live' ? possession(plays, game.away.team.id, game.home.team.id) : undefined);
</script>

<svelte:head><title>{game ? `${game.away.team.abbreviation} @ ${game.home.team.abbreviation}` : 'Game'} · Halftime</title></svelte:head>
<Backdrop color={game ? hex(backdropHex(game.home.team)) : '#1c1c1e'} />

<header data-tauri-drag-region>
	<a class="round glass" href="/" aria-label="Back">
		<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M10 3 5 8l5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" /></svg>
	</a>
	{#if game}<span class="title" data-tauri-drag-region>{game.away.team.abbreviation} @ {game.home.team.abbreviation}</span>{/if}
</header>

{#snippet side(c: Competitor, home: boolean)}
	{@const won = game!.status === 'final' && !isLosing(game!, c) && c.score !== (home ? game!.away.score : game!.home.score)}
	<div class="side">
		<div class="big-score" class:dim={isLosing(game!, c)}>
			{#if won && home}<span class="winner" aria-label="Winner">▶</span>{/if}
			<span class="digits">{c.score ?? '–'}</span>
			{#if won && !home}<span class="winner" aria-label="Winner">◀</span>{/if}
			{#if hasBall(game!, c)}<Football />{/if}
		</div>
		<img src={c.team.logo} alt="" width="48" height="48" />
		<a class="team-name" href="/league?league={league.id}&team={c.team.id}"><strong>{c.team.shortName}</strong></a>
		{#if c.record}<span class="secondary">{c.record}</span>{/if}
	</div>
{/snippet}

<main>
	{#if game}
		<!-- The summary's scores by period stand in when the scoreboard has none (soccer's halves). -->
		{@const scores = (c: Competitor) => (c.periodScores.length ? c.periodScores : detail?.periodScores[c.team.id] ?? [])}
		{@const periods = Math.max(scores(game.away).length, scores(game.home).length, league.regulationPeriods)}
		<p class="league">{game.note ?? league.abbreviation}</p>
		<div class="teams">
			{@render side(game.away, false)}
			<div class="centre">
				<span class="status">{#if game.status === 'live'}<span class="dot"></span>{/if}{headlineStatus(game)}</span>
				{#if game.status === 'scheduled'}
					<span class="secondary">{game.startDate.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</span>
				{:else}
					<table class="linescore" aria-label="Score by period">
						<thead><tr><th></th>{#each { length: periods } as _, i}<th>{periodLabel(league, i + 1)}</th>{/each}<th>T</th></tr></thead>
						<tbody>
							{#each [game.away, game.home] as c, r}
								<tr class:split={r === 1}>
									<td class="abbr">{c.team.abbreviation}</td>
									{#each { length: periods } as _, i}<td>{scores(c)[i] ?? '–'}</td>{/each}
									<td class="total">{c.score ?? '–'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				{/if}
			</div>
			{@render side(game.home, true)}
		</div>

		{#if field}
			<Gamecast {game} {plays}><FieldView {game} {field} /></Gamecast>
		{:else if hasSurface && league.id === 'nba'}
			<Gamecast {game} {plays}><Court {game} {shots} possession={ballWith} /></Gamecast>
		{:else if hasSurface && league.id === 'nhl'}
			<Gamecast {game} {plays}><Rink {game} {shots} /></Gamecast>
		{:else if hasSurface && league.periodStyle === 'halves' && detail}
			<Gamecast {game} {plays}><Pitch {game} shots={detail.shots} teamStats={detail.teamStats} /></Gamecast>
		{/if}

		{#if detail?.overview.recap}
			{@const recap = detail.overview.recap}
			<section class="sports-card recap">
				<h2>Recap</h2>
				<strong class="headline">{recap.headline}</strong>
				{#each recapOpen ? recap.paragraphs : recap.paragraphs.slice(0, 2) as paragraph}<p>{paragraph}</p>{/each}
				{#if recap.paragraphs.length > 2}
					<button class="more" onclick={() => (recapOpen = !recapOpen)}>{recapOpen ? 'Show Less' : 'Read More'}</button>
				{/if}
			</section>
		{/if}

		{#if tab}
			<div class="tabs"><GlassPicker options={[...tabs]} bind:selected={tab} /></div>
			{#if !detail}
				<p class="secondary centre-msg">Loading…</p>
			{:else if tab === 'Overview'}
				<Overview {game} overview={detail.overview} />
			{:else if tab === 'Stats'}
				<TeamStats {game} stats={detail.teamStats} />
			{:else if tab === 'Play-By-Play'}
				<PlayByPlay {game} drives={detail.drives} plays={detail.plays} />
			{:else}
				<BoxScore {game} boxScores={detail.boxScores} leaders={detail.overview.leaders} />
			{/if}
		{/if}
	{:else if error}
		<p class="secondary centre-msg">Couldn’t load game: {error}</p>
	{:else}
		<p class="secondary centre-msg">Loading…</p>
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
		gap: 12px;
		padding: 0 16px 0 var(--titlebar-inset);
	}
	.title {
		font-size: 15px;
		font-weight: 700;
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
		gap: 18px;
	}
	.league {
		margin: 0;
		text-align: center;
		font-size: var(--subheadline);
		font-weight: 600;
		color: var(--secondary);
	}
	.teams {
		display: flex;
		align-items: flex-start;
		max-width: 600px;
		width: 100%;
		margin: 0 auto;
	}
	.side {
		min-width: 150px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
	}
	.big-score {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.digits {
		font: 700 72px/1 'Chakra Petch', sans-serif;
	}
	.team-name:hover {
		text-decoration: underline;
	}
	.winner {
		font-size: 12px;
	}
	.dim, .secondary {
		color: var(--secondary);
	}
	.centre {
		flex: 1;
		padding-top: 26px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
	}
	.status {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--headline);
		font-weight: 700;
	}
	.dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: #ff453a;
	}
	.linescore {
		margin-top: 14px;
		width: 100%;
		max-width: 320px;
		border-collapse: collapse;
		font-size: var(--caption);
	}
	.linescore th {
		font-weight: 400;
		color: var(--secondary);
		padding-bottom: 5px;
	}
	.linescore td {
		text-align: center;
		padding: 2.5px 0;
	}
	.linescore tr.split td {
		border-top: 1px solid var(--separator);
	}
	.linescore .abbr {
		text-align: left;
		width: 34px;
		font-weight: 600;
	}
	.linescore .total {
		font-weight: 600;
	}
	.recap .headline {
		font-size: var(--title3);
	}
	.recap p {
		margin: 8px 0 0;
		line-height: 1.45;
		user-select: text;
		-webkit-user-select: text;
	}
	.more {
		margin-top: 8px;
		color: #64a8ff;
		font-weight: 600;
	}
	.tabs {
		display: flex;
		justify-content: center;
	}
	.centre-msg {
		text-align: center;
		margin-top: 80px;
	}
</style>
