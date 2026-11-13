<script lang="ts">
	// TeamStatsView: big values either side, label in the middle, comparison bars underneath.
	import { type Game, type TeamStat, hex } from '../espn';
	let { game, stats }: { game: Game; stats: TeamStat[] } = $props();

	/** Reads "306", "5.6", "2/10" or "5-16" (as made of attempted), "45%" and "29:34" (as minutes). */
	function number(text: string): number {
		if (text.includes(':')) {
			const [m, s] = text.split(':').map(Number);
			return m + s / 60 || 0;
		}
		if (text.includes('%')) return parseFloat(text) || 0;
		return parseFloat(text.split(/[/-]/)[0]) || 0;
	}
</script>

{#if stats.length === 0}
	<div class="empty-state">No Team Stats Yet</div>
{:else}
	<section class="sports-card">
		<div class="head">
			<img src={game.away.team.logo} alt={game.away.team.shortName} width="22" height="22" />
			<h2>Team Stats</h2>
			<img src={game.home.team.logo} alt={game.home.team.shortName} width="22" height="22" />
		</div>
		{#each stats as stat}
			{@const away = number(stat.away)}
			{@const home = number(stat.home)}
			{@const share = away + home > 0 ? away / (away + home) : 0.5}
			<div class="row" role="group" aria-label="{stat.label}: {game.away.team.shortName} {stat.away}, {game.home.team.shortName} {stat.home}">
				<div class="values"><span class="value">{stat.away}</span><span class="label">{stat.label}</span><span class="value">{stat.home}</span></div>
				<div class="bars">
					<span style:width="calc((100% - 6px) * {share})" style:background={hex(game.away.team.color)} style:opacity={away >= home ? 1 : 0.45}></span>
					<span style:flex="1" style:background={hex(game.home.team.color)} style:opacity={home >= away ? 1 : 0.45}></span>
				</div>
			</div>
		{/each}
	</section>
{/if}

<style>
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-bottom: 8px;
	}
	.head h2 {
		margin: 0;
		font-size: var(--headline);
	}
	.row {
		padding: 7px 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.values {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 8px;
	}
	.value {
		font: 700 28px/1 'Chakra Petch', sans-serif;
	}
	.label {
		font-size: var(--subheadline);
		color: var(--secondary);
		text-align: center;
	}
	.bars {
		display: flex;
		gap: 6px;
		height: 5px;
	}
	.bars span {
		border-radius: 3px;
	}
</style>
