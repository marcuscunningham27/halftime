<script lang="ts" module>
	import type { Game } from './espn';
	import type { Player } from './fantasy';
	/** One NFL game and your players in it: stat lines and points once it has started. */
	export type Line = { player: Player; isStarter: boolean; points?: number; stats: string[] };
	export type Entry = { game: Game; lines: Line[] };
</script>

<script lang="ts">
	// FantasyView's Past Week and Upcoming lists: each game's score card, then your players in it.
	import ScoreCard from './ScoreCard.svelte';
	let { entries, empty }: { entries: Entry[]; empty: string } = $props();
	const teamLogo = (g: Game, abbr?: string) => [g.away.team, g.home.team].find((t) => t.abbreviation === abbr)?.logo;
	const started = (g: Game) => g.status !== 'scheduled';
</script>

{#if entries.length === 0}
	<div class="empty-state">{empty}</div>
{/if}
{#each entries as entry (entry.game.id)}
	<section class="sports-card">
		<a class="game" href="/game?league=nfl&id={entry.game.id}&day={new Date(entry.game.startDate).setHours(0, 0, 0, 0)}">
			<ScoreCard game={entry.game} showsDate />
		</a>
		<hr />
		{#each entry.lines as line (line.player.id)}
			{@const p = line.player}
			<div class="line" class:bench={!line.isStarter}>
				<span class="photo">
					{#if p.position === 'DEF' && teamLogo(entry.game, p.team)}<img src={teamLogo(entry.game, p.team)} alt="" width="30" height="30" />
					{:else if p.photo}<img class="headshot" src={p.photo} alt="" />{/if}
				</span>
				<div class="info">
					<span>
						<strong>{p.name}</strong>
						<span class="dim">{[p.team, p.position].filter(Boolean).join(' - ')}</span>
						{#if !line.isStarter}<span class="bn">BN</span>{/if}
					</span>
					{#if started(entry.game)}
						{#each line.stats as stat}<span class="caption">{stat}</span>{/each}
						{#if line.stats.length === 0 && p.position !== 'DEF'}<span class="caption">{entry.game.status === 'live' ? 'No stats yet' : 'No stats'}</span>{/if}
					{/if}
				</div>
				{#if started(entry.game)}
					<span class="points"><b>{line.points === undefined ? '–' : line.points.toFixed(1)}</b><small>PTS</small></span>
				{/if}
			</div>
		{/each}
	</section>
{/each}

<style>
	.game {
		display: block;
		border-radius: 12px;
	}
	.game:hover {
		background: rgba(255, 255, 255, 0.04);
	}
	.line {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 6px 0;
	}
	.line.bench {
		opacity: 0.7;
	}
	.photo {
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
	.headshot {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.dim, .caption, small {
		color: var(--secondary);
	}
	.dim {
		font-size: var(--subheadline);
	}
	.caption {
		font-size: var(--caption);
	}
	.bn {
		margin-left: 4px;
		padding: 1px 5px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.15);
		font-size: var(--caption);
		font-weight: 700;
	}
	.points {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
	}
	.points b {
		font: 700 28px/1 'Chakra Petch', sans-serif;
	}
	small {
		font-size: var(--caption);
		font-weight: 600;
	}
</style>
