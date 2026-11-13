<script lang="ts">
	// HomeView.swift: Yesterday / Today / Upcoming, each league's games in one card, live first.
	import Backdrop from '$lib/Backdrop.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import ScoreCard from '$lib/ScoreCard.svelte';
	import { leagues as allLeagues, leagueLogo, scoreboard, startOfDay, ordered, orderLeagues, type Game } from '$lib/espn';
	import { isFollowingTeam } from '$lib/follows.svelte';
	import { settings } from '$lib/settings.svelte';

	// Sections in the order dragged into in the sidebar.
	const leagues = $derived(orderLeagues(allLeagues, settings.leagueOrder));
	const days = ['Yesterday', 'Today', 'Upcoming'] as const;
	let day = $state<(typeof days)[number]>('Today');
	let games = $state<Game[] | undefined>();
	let error = $state<string | undefined>();
	const offset = $derived(days.indexOf(day) - 1);
	/** Followed teams' games come first under My Teams, and aren't repeated in their league. */
	const mine = $derived(ordered((games ?? []).filter((g) => isFollowingTeam(g.league.id, g.home.team.id) || isFollowingTeam(g.league.id, g.away.team.id))));
	const mineIDs = $derived(new Set(mine.map((g) => g.id)));

	async function refresh(forOffset = offset) {
		try {
			// The fixed list: fetching doesn't care about order, and reading the ordered one would refetch on every reorder.
			const result = (await Promise.all(allLeagues.map((l) => scoreboard(l, startOfDay(forOffset)).catch(() => [])))).flat();
			if (forOffset === offset) [games, error] = [result, undefined];
		} catch (e) {
			error = String(e);
		}
	}

	// Reloads on a new day and polls every 15 seconds, as ScoreboardPoller does.
	$effect(() => {
		const o = offset;
		games = undefined;
		refresh(o);
		const timer = setInterval(() => refresh(o), 15_000);
		return () => clearInterval(timer);
	});
</script>

<svelte:head><title>Halftime</title></svelte:head>
<Backdrop color="#2d6526" flat />

<header data-tauri-drag-region>
	<div class="brand" data-tauri-drag-region>
		<span class="mark glass" aria-hidden="true"><i class="line"></i><i class="ring"></i><i class="spot"></i></span>
		<h1>Halftime</h1>
	</div>
	<button class="round glass" title="Refresh" aria-label="Refresh" onclick={() => refresh()}>
		<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M13 8a5 5 0 1 1-1.5-3.55M13 2.5v3h-3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" /></svg>
	</button>
</header>

<main>
	<div class="picker"><GlassPicker options={[...days]} bind:selected={day} /></div>
	<section class="card">
		{#if games === undefined}
			<div class="empty"><span class="spinner" aria-label="Loading"></span></div>
		{:else if games.length === 0}
			<div class="empty">
				<svg viewBox="0 0 24 24" width="36" height="36" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="1.6" /><path d="M3 10h18M8 3v4M16 3v4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" /></svg>
				<strong>No Games {day}</strong>
				{#if error}<span>{error}</span>{/if}
			</div>
		{:else}
			{#if mine.length}
				<h2><svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true"><path d="M10 2.5l2.2 4.6 5 .6-3.7 3.5 1 5L10 13.8 5.5 16.2l1-5L2.8 7.7l5-.6z" fill="currentColor" /></svg>My Teams</h2>
				{#each mine as game, j (game.id)}
					{#if j > 0}<hr />{/if}
					<a href="/game?league={game.league.id}&id={game.id}&day={startOfDay(offset).getTime()}" class="row"><ScoreCard {game} /></a>
				{/each}
			{/if}
			{#each leagues as league, i}
				{@const leagueGames = ordered(games.filter((g) => g.league.id === league.id && !mineIDs.has(g.id)))}
				{#if leagueGames.length}
					{#if mine.length || (i > 0 && games.some((g) => leagues.indexOf(g.league) < i && !mineIDs.has(g.id)))}<hr class="section" />{/if}
					<h2><a href="/league?league={league.id}"><img src={leagueLogo(league)} alt="" width="20" height="20" />{league.abbreviation}<svg class="chevron" viewBox="0 0 16 16" width="10" height="10" aria-hidden="true"><path d="M6 3l5 5-5 5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" /></svg></a></h2>
					{#each leagueGames as game, j (game.id)}
						{#if j > 0}<hr />{/if}
						<a href="/game?league={league.id}&id={game.id}&day={startOfDay(offset).getTime()}" class="row"><ScoreCard {game} /></a>
					{/each}
				{/if}
			{/each}
		{/if}
	</section>
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
	.brand {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	h1 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
		letter-spacing: -0.01em;
	}
	/* HalftimeMark: halfway line, centre circle and spot on a clear glass tile. */
	.mark {
		position: relative;
		width: 32px;
		height: 32px;
		border-radius: 8px;
		display: grid;
		place-items: center;
		color: rgba(255, 255, 255, 0.9);
		overflow: hidden;
	}
	.mark i {
		position: absolute;
		background: currentColor;
	}
	.mark .line { width: 1.8px; height: 100%; }
	.mark .ring { width: 14px; height: 14px; border-radius: 50%; background: none; border: 1.8px solid currentColor; box-sizing: border-box; }
	.mark .spot { width: 3.2px; height: 3.2px; border-radius: 50%; }
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
	}
	.picker {
		display: flex;
		justify-content: center;
		margin-bottom: 14px;
	}
	/* SportsCard: darkened, not grey, so the backdrop's colour shows through. */
	.card {
		padding: 12px 16px;
		border-radius: 22px;
		background: rgba(0, 0, 0, 0.38);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
	}
	h2 {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 10px 0 0;
		font-size: var(--headline);
		font-weight: 700;
	}
	h2 a {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.chevron {
		color: var(--secondary);
	}
	h2 img {
		filter: drop-shadow(0 0 0.6px rgba(255, 255, 255, 0.9)) drop-shadow(0 0 1.2px rgba(255, 255, 255, 0.5));
	}
	hr {
		border: 0;
		border-top: 1px solid var(--separator);
		margin: 0;
	}
	hr.section {
		margin-top: 6px;
	}
	.row {
		display: block;
		border-radius: 12px;
	}
	a.row:hover {
		background: rgba(255, 255, 255, 0.04);
	}
	.empty {
		min-height: 200px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 8px;
		color: var(--secondary);
	}
	.empty strong {
		color: var(--label);
		font-size: 17px;
	}
	.spinner {
		width: 18px;
		height: 18px;
		border-radius: 50%;
		border: 2px solid var(--tertiary);
		border-top-color: var(--label);
		animation: spin 0.8s linear infinite;
	}
	@keyframes spin {
		to { transform: rotate(1turn); }
	}
</style>
