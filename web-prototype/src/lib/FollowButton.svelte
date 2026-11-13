<script lang="ts">
	// FollowTeamButton / FollowLeagueButton: a star toggle, filled while following.
	import type { Team } from './espn';
	import { isFollowingLeague, isFollowingTeam, toggleLeague, toggleTeam } from './follows.svelte';
	let { leagueID, team, name, glass = false }: { leagueID: string; team?: Team; name: string; glass?: boolean } = $props();
	const on = $derived(team ? isFollowingTeam(leagueID, team.id) : isFollowingLeague(leagueID));
	const label = $derived(`${on ? 'Unfollow' : 'Follow'} ${name}`);
</script>

<button
	class="star"
	class:glass
	class:on
	aria-pressed={on}
	aria-label={label}
	title={label}
	onclick={(e) => {
		// Inside a link (a search result row), the star mustn't also open the page.
		e.preventDefault();
		e.stopPropagation();
		team ? toggleTeam(leagueID, team) : toggleLeague(leagueID);
	}}
>
	<svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true">
		<path d="M10 2.5l2.2 4.6 5 .6-3.7 3.5 1 5L10 13.8 5.5 16.2l1-5L2.8 7.7l5-.6z" fill={on ? 'currentColor' : 'none'} stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" />
	</svg>
</button>

<style>
	.star {
		display: inline-grid;
		place-items: center;
		width: 24px;
		height: 24px;
		border-radius: 50%;
		color: var(--secondary);
		flex: none;
	}
	.star.glass {
		width: 32px;
		height: 32px;
	}
	.star:hover,
	.star.on {
		color: var(--label);
	}
</style>
