<script module lang="ts">
	/** Fantasy's icon: a V-neck jersey with a cut-out number 1 (fill-rule evenodd). The sidebar and the badge share it. */
	export const jersey = 'M6.6 2.4 2.6 4.4 1.4 9.3l3 .9.9-2.1v9.4h9.4V8.1l.9 2.1 3-.9-1.2-4.9-4-2L10 6.3zM9.3 9.4h1.9v5.6H9.8v-4.1l-.9.4z';
</script>

<script lang="ts">
	let { size = 14, label = 'Your fantasy player' }: { size?: number; label?: string } = $props();
</script>

<!-- Marks your fantasy players: a black jersey on a yellow disc. -->
<svg class="badge" viewBox="0 0 20 20" width={size} height={size} role="img" aria-label={label}>
	<circle cx="10" cy="10" r="9.5" fill="#ffd60a" />
	<path d={jersey} fill="#000" fill-rule="evenodd" transform="translate(10 10.3) scale(.64) translate(-10 -10)" />
</svg>

<style>
	.badge {
		flex: none;
		vertical-align: -2px;
	}
</style>
