<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';

const store = useStore();
const card = computed(() => store.getters['conversation/getCardPreview']);
const status = computed(() => store.getters['conversationAttributes/getConversationParams'].status);
const canSend = computed(() => window.chatwootWebChannel.allowMessagesAfterResolved || status.value !== 'resolved');

const dismiss = () => store.commit('conversation/setCardPreview', null);
const send = () => {
  store.dispatch('conversation/sendCard', card.value);
  dismiss();
};
</script>

<template>
  <div v-if="card && canSend" class="mx-4 mb-2 flex items-center gap-3 rounded-lg border border-n-weak bg-n-background p-3">
    <img :src="card.imageUrl" alt="" class="h-14 w-14 rounded object-cover" />
    <div class="min-w-0 flex-1 text-n-slate-12">
      <div class="break-words font-medium">{{ card.title }}</div>
      <div class="text-sm">{{ card.price }}</div>
    </div>
    <button type="button" class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white" @click="send">
      {{ $t('COMPONENTS.CARD_PREVIEW.SEND') }}
    </button>
    <button type="button" class="text-n-slate-11" :aria-label="$t('COMPONENTS.CARD_PREVIEW.DISMISS')" @click="dismiss">
      ×
    </button>
  </div>
</template>
