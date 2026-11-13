<script lang="ts">
	// ScoreCard from ScoreStyle.swift: logo and name outside, big scores, status in the middle.
	import Football from './Football.svelte';
	import { type Game, type Competitor, headlineStatus, substatus, hasBall, isLosing } from './espn';
	// showsDate adds the local date under the status, for lists that span days (the Fantasy weeks).
	let { game, showsDate = false }: { game: Game; showsDate?: boolean } = $props();
</script>

{#snippet side(c: Competitor)}
	<div class="side">
		<img src={c.team.logo} alt="" width="40" height="40" />
		<span class="name">{c.team.shortName}</span>
	</div>
{/snippet}

{#snippet score(c: Competitor, home: boolean)}
	<div class="score" class:dim={isLosing(game, c) || c.score === undefined}>
		{#if hasBall(game, c) && home}<Football />{/if}
		{#if c.score !== undefined}<span class="digits">{c.score}</span>{:else}<span class="record">{c.record ?? ''}</span>{/if}
		{#if hasBall(game, c) && !home}<Football />{/if}
	</div>
{/snippet}

<div class="card">
	{@render side(game.away)}
	{@render score(game.away, false)}
	<div class="middle">
		{#if game.note}<span class="caption">{game.note}</span>{/if}
		<span class="status">
			{#if game.status === 'live'}<span class="dot"></span>{/if}
			{headlineStatus(game)}
		</span>
		{#if showsDate}<span class="caption">{game.startDate.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' })}</span>{/if}
		{#if substatus(game)}<span class="caption">{substatus(game)}</span>{/if}
		{#if game.status !== 'final' && game.broadcasts.length}
			<span class="tv glass" title={game.broadcasts.join(', ')}>
				<svg viewBox="0 0 16 16" width="10" height="10" aria-hidden="true"><rect x="1.5" y="3" width="13" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.5" /><path d="M5 14.5h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" /></svg>
				{game.broadcasts.slice(0, 2).join(' · ')}
			</span>
		{/if}
	</div>
	{@render score(game.home, true)}
	{@render side(game.home)}
</div>

<style>
	.card {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 10px 0;
	}
	.side {
		width: 96px;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
	}
	.name {
		font-size: var(--subheadline);
		font-weight: 600;
		color: var(--secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}
	.score {
		min-width: 56px;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 4px;
	}
	.digits {
		font: 700 40px/1 'Chakra Petch', sans-serif;
	}
	.record {
		font-size: var(--subheadline);
	}
	.dim {
		color: var(--secondary);
	}
		.middle {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 3px;
		text-align: center;
	}
	.status {
		font-size: var(--headline);
		font-weight: 700;
		display: flex;
		align-items: center;
		gap: 4px;
		white-space: nowrap;
	}
	.dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: #ff453a;
	}
	.caption {
		font-size: var(--caption);
		color: var(--secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}
	.tv {
		margin-top: 2px;
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px;
		border-radius: 999px;
		font-size: var(--caption);
		font-weight: 600;
		white-space: nowrap;
	}
</style>
