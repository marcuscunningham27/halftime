<script lang="ts" generics="T extends string">
	// GlassPicker.swift: a glass capsule with a lighter pill that slides to the selection.
	let { options, selected = $bindable() }: { options: T[]; selected: T } = $props();
	let buttons: HTMLButtonElement[] = $state([]);
	const pill = $derived.by(() => {
		const b = buttons[options.indexOf(selected)];
		return b ? { left: b.offsetLeft, width: b.offsetWidth } : undefined;
	});
</script>

<div class="picker glass" role="tablist">
	{#if pill}<span class="pill" style:left="{pill.left}px" style:width="{pill.width}px"></span>{/if}
	{#each options as option, i}
		<button bind:this={buttons[i]} role="tab" aria-selected={option === selected} class:on={option === selected} onclick={() => (selected = option)}>
			{option}
		</button>
	{/each}
</div>

<style>
	.picker {
		position: relative;
		display: inline-flex;
		gap: 2px;
		padding: 3px;
		border-radius: 999px;
	}
	button {
		position: relative;
		z-index: 1;
		padding: 7px 16px;
		border-radius: 999px;
		font-size: var(--subheadline);
		font-weight: 500;
		color: var(--secondary);
	}
	button.on {
		color: var(--label);
		font-weight: 600;
	}
	.pill {
		position: absolute;
		top: 3px;
		bottom: 3px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.22);
		box-shadow: inset 0 0 0 0.5px rgba(255, 255, 255, 0.25);
		transition: left 0.3s cubic-bezier(0.3, 1.3, 0.5, 1), width 0.3s cubic-bezier(0.3, 1.3, 0.5, 1);
	}
</style>
