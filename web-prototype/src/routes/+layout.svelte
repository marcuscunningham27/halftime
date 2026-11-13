<script lang="ts">
	// ContentView.swift's sidebar: Home and Fantasy, search, followed leagues then teams, every league, Settings.
	import { page } from '$app/state';
	import { leagues, leagueLogo, allTeams, type League, type Team } from '$lib/espn';
	import { follows } from '$lib/follows.svelte';
	import FollowButton from '$lib/FollowButton.svelte';
	let { children } = $props();
	// In the Tauri window the title bar is transparent, so the sidebar leaves room for the traffic lights.
	const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
	const items = [
		{ href: '/', title: 'Home', icon: 'M3 8.5 10 3l7 5.5V17h-4.5v-5h-5v5H3z' },
		{ href: '/fantasy', title: 'Fantasy', icon: 'M10 2.5l2.2 4.6 5 .6-3.7 3.5 1 5L10 13.8 5.5 16.2l1-5L2.8 7.7l5-.6z' }
	];
	// A game page belongs to Home; a team page is its own row when followed, else its league's.
	const current = $derived.by(() => {
		const path = page.url.pathname, q = page.url.searchParams;
		if (path.startsWith('/fantasy')) return '/fantasy';
		if (path.startsWith('/settings')) return '/settings';
		if (path.startsWith('/league')) return q.get('team') ? `/league?league=${q.get('league')}&team=${q.get('team')}` : `/league?league=${q.get('league')}`;
		return '/';
	});
	const leagueHref = (id: string) => `/league?league=${id}`;
	const teamHref = (leagueID: string, teamID: string) => `/league?league=${leagueID}&team=${teamID}`;
	const leagueOf = (id: string) => leagues.find((l) => l.id === id);

	let query = $state('');
	let teams = $state<{ league: League; team: Team }[]>([]);
	const text = $derived(query.trim().toLowerCase());
	$effect(() => {
		if (text && teams.length === 0) allTeams().then((t) => (teams = t));
	});
	const matchingLeagues = $derived(leagues.filter((l) => l.abbreviation.toLowerCase().includes(text) || l.name.toLowerCase().includes(text)));
	const matchingTeams = $derived(teams.filter(({ team }) => team.displayName.toLowerCase().includes(text) || team.abbreviation.toLowerCase() === text));
	// Leaving for another page clears the search.
	$effect(() => {
		page.url.href;
		query = '';
	});
</script>

<div class="app" class:tauri={inTauri}>
	<!-- The macOS 26 sidebar: a floating glass panel inset from the window edge, over the page's colour. -->
	<nav class="sidebar glass" data-tauri-drag-region>
		<div class="rows">
			{#each items as item}
				<a class="main" href={item.href} class:on={current === item.href} aria-current={current === item.href ? 'page' : undefined}>
					<svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><path d={item.icon} fill="currentColor" /></svg>
					{item.title}
				</a>
			{/each}
			<label class="search glass">
				<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="7" cy="7" r="4.5" fill="none" stroke="currentColor" stroke-width="1.6" /><path d="M10.5 10.5 14 14" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" /></svg>
				<input bind:value={query} placeholder="Search teams and leagues" aria-label="Search teams and leagues" spellcheck="false" autocomplete="off" />
				{#if query}<button class="clear" aria-label="Clear" onclick={() => (query = '')}>×</button>{/if}
			</label>

			{#if text}
				<!-- Leagues and teams whose names match, each with a star to follow it. -->
				{#if matchingLeagues.length}
					<span class="section">Leagues</span>
					{#each matchingLeagues as l}
						<a href={leagueHref(l.id)}><img src={leagueLogo(l)} alt="" width="16" height="16" /><span class="grow">{l.name}</span><FollowButton leagueID={l.id} name={l.abbreviation} /></a>
					{/each}
				{/if}
				<span class="section">Teams</span>
				{#if matchingTeams.length === 0}<span class="note">{teams.length ? 'No matching teams' : 'Loading teams…'}</span>{/if}
				{#each matchingTeams.slice(0, 30) as { league, team } (league.id + team.id)}
					<a href={teamHref(league.id, team.id)}>
						<img src={team.logo} alt="" width="16" height="16" />
						<span class="grow two"><span>{team.displayName}</span><small>{league.abbreviation}</small></span>
						<FollowButton leagueID={league.id} {team} name={team.shortName} />
					</a>
				{/each}
			{:else}
				<span class="section">Following</span>
				{#if follows.leagues.length === 0 && follows.teams.length === 0}<span class="note">Nothing followed yet</span>{/if}
				{#each follows.leagues as id (id)}
					{@const l = leagueOf(id)}
					{#if l}
						<a href={leagueHref(id)} class:on={current === leagueHref(id)}><img src={leagueLogo(l)} alt="" width="16" height="16" />{l.abbreviation}</a>
					{/if}
				{/each}
				{#if follows.leagues.length && follows.teams.length}<hr />{/if}
				{#each follows.teams as { leagueID, team } (leagueID + team.id)}
					<a href={teamHref(leagueID, team.id)} class:on={current === teamHref(leagueID, team.id)}><img src={team.logo} alt="" width="16" height="16" />{team.displayName}</a>
				{/each}
				<span class="section">Leagues</span>
				{#each leagues as l}
					<a href={leagueHref(l.id)} class:on={current === leagueHref(l.id)}><img src={leagueLogo(l)} alt="" width="16" height="16" />{l.abbreviation}</a>
				{/each}
			{/if}
		</div>
		<a class="settings" href="/settings" class:on={current === '/settings'}>
			<svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><path d="M10 6.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm7 4.6v-2.2l-2-.4a5 5 0 0 0-.6-1.4l1.1-1.7-1.5-1.5-1.7 1.1a5 5 0 0 0-1.4-.6L10.5 2h-2.2l-.4 2a5 5 0 0 0-1.4.6L4.8 3.5 3.3 5l1.1 1.7a5 5 0 0 0-.6 1.4L2 8.9v2.2l2 .4c.1.5.3 1 .6 1.4l-1.1 1.7 1.5 1.5 1.7-1.1c.4.3.9.5 1.4.6l.4 2h2.2l.4-2c.5-.1 1-.3 1.4-.6l1.7 1.1 1.5-1.5-1.1-1.7c.3-.4.5-.9.6-1.4z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round" /></svg>
			Settings
		</a>
	</nav>
	<div class="content">{@render children()}</div>
</div>

<style>
	@font-face {
		font-family: 'Chakra Petch';
		src: url('/ChakraPetch-Bold.ttf') format('truetype');
		font-weight: 700;
	}

	/* macOS text styles in points (SwiftUI's .headline is 13 bold on the Mac, .subheadline 11, .caption 10). */
	:global(:root) {
		color-scheme: dark;
		--label: rgba(255, 255, 255, 0.92);
		--secondary: rgba(255, 255, 255, 0.55);
		--tertiary: rgba(255, 255, 255, 0.28);
		--separator: rgba(255, 255, 255, 0.12);
		--body: 13px;
		--headline: 13px;
		--subheadline: 11px;
		--caption: 10px;
		--title3: 15px;
		--sports-green: #2d6526;
		--glass: rgba(255, 255, 255, 0.08);
		--glass-edge: rgba(255, 255, 255, 0.22);
	}
	:global(html, body) {
		margin: 0;
		height: 100%;
		color: var(--label);
		font: var(--body) / 1.3 -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI Variable Text', 'Segoe UI', system-ui, sans-serif;
		-webkit-font-smoothing: antialiased;
		font-variant-numeric: tabular-nums;
		user-select: none;
		-webkit-user-select: none;
		cursor: default;
	}
	/* Only the root is painted, so the fixed backdrop (z-index -1) shows above it. */
	:global(html) {
		background: #000;
	}
	:global(a) {
		color: inherit;
		text-decoration: none;
	}
	:global(button) {
		font: inherit;
		color: inherit;
		background: none;
		border: 0;
		padding: 0;
		cursor: default;
	}
	:global(:focus-visible) {
		outline: 2px solid rgba(255, 255, 255, 0.7);
		outline-offset: 2px;
	}
	/* Liquid Glass stand-in: blurred, saturated backdrop with a bright hairline edge and top highlight. */
	:global(.glass) {
		background: var(--glass);
		backdrop-filter: blur(24px) saturate(180%);
		-webkit-backdrop-filter: blur(24px) saturate(180%);
		border: 0.5px solid var(--glass-edge);
		box-shadow:
			inset 0 1px 0 rgba(255, 255, 255, 0.18),
			0 4px 18px rgba(0, 0, 0, 0.18);
	}
	/* SportsCard: darkened, not grey, so the backdrop's colour shows through. */
	:global(.sports-card) {
		padding: 12px 16px;
		border-radius: 22px;
		background: rgba(0, 0, 0, 0.38);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
	}
	:global(.sports-card > h2) {
		margin: 0 0 4px;
		font-size: var(--headline);
	}
	:global(.sports-card hr) {
		border: 0;
		border-top: 1px solid var(--separator);
		margin: 0;
	}
	:global(.empty-state) {
		min-height: 160px;
		display: grid;
		place-items: center;
		color: var(--secondary);
	}
	.app {
		min-height: 100%;
		--titlebar-inset: 20px;
		--sidebar: 220px;
	}
	.sidebar {
		position: fixed;
		z-index: 3;
		top: 8px;
		bottom: 8px;
		left: 8px;
		width: calc(var(--sidebar) - 16px);
		box-sizing: border-box;
		padding: 14px 10px;
		border-radius: 18px;
		display: flex;
		flex-direction: column;
		gap: 2px;
		background: rgba(30, 30, 32, 0.32);
	}
	.tauri .sidebar {
		padding-top: 54px;
	}
	.rows {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		gap: 2px;
		scrollbar-width: none;
	}
	.section {
		margin: 10px 10px 2px;
		font-size: var(--caption);
		font-weight: 600;
		color: var(--secondary);
	}
	.note {
		padding: 4px 10px;
		color: var(--secondary);
	}
	.grow {
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.two {
		display: flex;
		flex-direction: column;
	}
	.two small {
		font-size: var(--caption);
		color: var(--secondary);
	}
	.search {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 6px 2px 2px;
		padding: 4px 8px;
		border-radius: 999px;
		color: var(--secondary);
	}
	.search input {
		flex: 1;
		min-width: 0;
		background: none;
		border: 0;
		outline: none;
		font: inherit;
		color: var(--label);
		user-select: text;
		-webkit-user-select: text;
	}
	.search:focus-within {
		outline: 3px solid rgba(10, 132, 255, 0.55);
	}
	.clear {
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--tertiary);
		color: #000;
		font-size: 12px;
		line-height: 16px;
	}
	.settings {
		margin-top: 6px;
	}
	.sidebar a {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 10px;
		border-radius: 8px;
		font-weight: 500;
	}
	.sidebar hr {
		border: 0;
		border-top: 1px solid var(--separator);
		margin: 6px 10px;
	}
	/* A thin white halo keeps dark logos (the Premier League's) visible on the glass. */
	.sidebar a img {
		filter: drop-shadow(0 0 0.6px rgba(255, 255, 255, 0.9)) drop-shadow(0 0 1.2px rgba(255, 255, 255, 0.5));
	}
	.sidebar a svg {
		color: var(--secondary);
	}
	.sidebar a.on {
		background: rgba(255, 255, 255, 0.14);
	}
	.sidebar a.on svg {
		color: var(--label);
	}
	.content {
		margin-left: var(--sidebar);
	}
	/* SwiftUI's soft scroll edge: content blurs and darkens as it slides under a page's sticky header. */
	.content :global(> header::before) {
		content: '';
		position: absolute;
		z-index: -1;
		inset: 0 0 -18px;
		background: linear-gradient(rgba(0, 0, 0, 0.35), transparent);
		backdrop-filter: blur(10px);
		-webkit-backdrop-filter: blur(10px);
		mask-image: linear-gradient(black 55%, transparent);
		-webkit-mask-image: linear-gradient(black 55%, transparent);
		pointer-events: none;
	}
	/* Phone width: the sidebar becomes a bar along the bottom. */
	@media (max-width: 640px) {
		.app {
			--sidebar: 0px;
		}
		.rows {
			flex-direction: row;
			overflow: visible;
		}
		.rows > :not(.main) {
			display: none;
		}
		.settings {
			margin-top: 0;
		}
		.sidebar {
			top: auto;
			left: 50%;
			bottom: 12px;
			width: auto;
			transform: translateX(-50%);
			flex-direction: row;
			padding: 6px;
			border-radius: 999px;
		}
		.content {
			padding-bottom: 72px;
		}
	}
</style>
