<script lang="ts">
	// BoxScoreView: game leaders, then player stat tables, away team first.
	import Leaders from './Leaders.svelte';
	import FantasyBadge from '../FantasyBadge.svelte';
	import { isRostered } from '../roster.svelte';
	import type { Game, BoxScore, Leader } from '../espn';
	let { game, boxScores, leaders }: { game: Game; boxScores: BoxScore[]; leaders: Leader[] } = $props();
	const ordered = $derived([game.away.team.id, game.home.team.id].flatMap((id) => boxScores.filter((b) => b.teamID === id)));
</script>

{#if boxScores.length === 0 && leaders.length === 0}
	<div class="empty-state">No Box Score Yet</div>
{:else}
	<div class="stack">
		<Leaders {game} {leaders} />
		{#each ordered as box}
			<section class="sports-card">
				<h2>{box.title}</h2>
				<div class="scroll">
					<table>
						<thead><tr><th>Player</th>{#each box.labels as label}<th>{label}</th>{/each}</tr></thead>
						<tbody>
							{#each box.rows as row (row.id)}
								{@const yours = game.league.id === 'nfl' && isRostered(row.id, row.name)}
								<tr class:yours><td>{row.name} {#if yours}<FantasyBadge />{/if}</td>{#each row.stats as stat}<td>{stat}</td>{/each}</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</section>
		{/each}
	</div>
{/if}

<style>
	.stack {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.scroll {
		overflow-x: auto;
		scrollbar-width: none;
	}
	table {
		border-collapse: collapse;
		width: 100%;
		margin: 6px 0;
		white-space: nowrap;
	}
	th, td {
		text-align: right;
		padding: 3.5px 0 3.5px 14px;
	}
	th:first-child, td:first-child {
		text-align: left;
		padding-left: 0;
	}
	th {
		font-size: var(--caption);
		font-weight: 400;
		color: var(--secondary);
		border-bottom: 1px solid var(--separator);
		padding-bottom: 7px;
	}
	tr.yours td:first-child {
		color: #ffd60a;
	}
	tbody tr:first-child td {
		padding-top: 7px;
	}
</style>
