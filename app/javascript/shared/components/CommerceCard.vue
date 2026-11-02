<script setup>
defineProps({
  item: { type: Object, required: true },
  interactive: { type: Boolean, default: false },
});
const emit = defineEmits(['select']);
</script>

<template>
  <component
    :is="interactive && item.action ? 'button' : 'div'"
    type="button"
    class="flex w-64 max-w-full gap-3 rounded-lg border border-n-weak bg-n-background p-3 text-start text-n-slate-12"
    @click="interactive && item.action && emit('select', item.action)"
  >
    <img :src="item.media_url || item.mediaUrl" alt="" class="h-16 w-16 rounded object-cover" />
    <span class="flex min-w-0 flex-col gap-1">
      <span class="break-words font-medium">{{ item.title }}</span>
      <span class="break-all text-xs text-n-slate-11">{{ item.order_id || item.orderId }}</span>
      <span class="break-all text-xs text-n-slate-11">{{ item.product_id || item.productId }}</span>
      <span v-if="item.price" class="text-sm">{{ item.price }}</span>
    </span>
  </component>
</template>
