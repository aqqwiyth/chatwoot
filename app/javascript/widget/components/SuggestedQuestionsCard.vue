<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';

const QUESTIONS_PER_PAGE = 3;
const store = useStore();
const page = ref(0);
const questions = window.chatwootWebChannel.suggestedQuestions || [];
const pageCount = Math.ceil(questions.length / QUESTIONS_PER_PAGE);
const visibleQuestions = computed(() => {
  const start = page.value * QUESTIONS_PER_PAGE;
  return questions.slice(start, start + QUESTIONS_PER_PAGE);
});
const showCard = computed(() => {
  const { allowMessagesAfterResolved } = window.chatwootWebChannel;
  const { status } = store.getters['conversationAttributes/getConversationParams'];
  return (
    questions.length > 0 &&
    store.getters['conversation/getShowSuggestedQuestions'] &&
    (allowMessagesAfterResolved || status !== 'resolved')
  );
});

const nextPage = () => {
  page.value = (page.value + 1) % pageCount;
};

const sendQuestion = question => {
  store.dispatch('conversation/sendMessage', { content: question });
};
</script>

<template>
  <section
    v-if="showCard"
    class="mb-4 max-w-72 rounded-lg border border-n-weak bg-n-background p-4 text-n-slate-12"
    :aria-label="$t('COMPONENTS.SUGGESTED_QUESTIONS.TITLE')"
  >
    <div class="mb-3 flex items-center justify-between gap-3">
      <span class="font-medium">
        {{ $t('COMPONENTS.SUGGESTED_QUESTIONS.TITLE') }}
      </span>
      <button
        v-if="pageCount > 1"
        type="button"
        class="text-sm text-n-brand"
        @click="nextPage"
      >
        {{ $t('COMPONENTS.SUGGESTED_QUESTIONS.NEXT') }}
      </button>
    </div>
    <div class="flex flex-col items-start gap-2">
      <button
        v-for="(question, index) in visibleQuestions"
        :key="`${page}-${index}`"
        type="button"
        class="text-start text-sm text-n-brand"
        @click="sendQuestion(question)"
      >
        {{ question }}
      </button>
    </div>
  </section>
</template>
