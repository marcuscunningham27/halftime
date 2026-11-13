<script lang="ts">
	import { page } from '$app/state';
	import { leagues, leagueLogo } from '$lib/espn';
	let { children } = $props();
	// In the Tauri window the title bar is transparent, so the sidebar leaves room for the traffic lights.
	const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
	const items = [
		{ href: '/', title: 'Home', icon: 'M3 8.5 10 3l7 5.5V17h-4.5v-5h-5v5H3z' },
		{ href: '/fantasy', title: 'Fantasy', icon: 'M10 2.5l2.2 4.6 5 .6-3.7 3.5 1 5L10 13.8 5.5 16.2l1-5L2.8 7.7l5-.6z' }
	];
	// A game page belongs to Home; a team page to its league.
	const current = $derived(
		page.url.pathname.startsWith('/fantasy') ? '/fantasy'
		: page.url.pathname.startsWith('/league') ? `/league?league=${page.url.searchParams.get('league')}`
		: '/'
	);
	// shortcut: lists every league until following lands; the Swift sidebar shows followed leagues and teams.
	const leagueItems = leagues.map((l) => ({ href: `/league?league=${l.id}`, title: l.abbreviation, logo: leagueLogo(l) }));
</script>

<div class="app" class:tauri={inTauri}>
	<!-- The macOS 26 sidebar: a floating glass panel inset from the window edge, over the page's colour. -->
	<nav class="sidebar glass" data-tauri-drag-region>
		{#each items as item}
			<a href={item.href} class:on={current === item.href} aria-current={current === item.href ? 'page' : undefined}>
				<svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><path d={item.icon} fill="currentColor" /></svg>
				{item.title}
			</a>
		{/each}
		<hr />
		{#each leagueItems as item}
			<a href={item.href} class:on={current === item.href} aria-current={current === item.href ? 'page' : undefined}>
				<img src={item.logo} alt="" width="16" height="16" />
				{item.title}
			</a>
		{/each}
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
		.sidebar hr {
			display: none;
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
