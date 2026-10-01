<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';

const { t } = useI18n();
const store = useCaptainConfigStore();
const routes = ['editor', 'assistant', 'copilot', 'embedding'];
const drafts = reactive({});
routes.forEach(routeKey => {
  drafts[routeKey] = { provider: 'openai', model: '', endpoint: '', api_key: '' };
});

const syncDrafts = overrides => {
  overrides.forEach(route => {
    drafts[route.route_key] = { provider: route.provider || 'openai', model: route.model || '', endpoint: route.endpoint || '', api_key: '' };
  });
};

watch(() => store.routeOverrides, syncDrafts, { immediate: true });

const save = async routeKey => {
  try {
    await store.updateRouteOverride(routeKey, drafts[routeKey]);
    useAlert(t('CAPTAIN_SETTINGS.API.SUCCESS'));
  } catch (error) {
    useAlert(t('CAPTAIN_SETTINGS.API.ERROR'));
  }
};
</script>

<template>
  <div class="grid gap-3">
    <div v-for="routeKey in routes" :key="routeKey" class="grid grid-cols-1 md:grid-cols-6 gap-2 items-center">
      <span class="text-sm font-medium">{{ routeKey }}</span>
      <select v-model="drafts[routeKey].provider" class="border rounded px-2 py-1 text-sm"><option value="openai">OpenAI</option><option value="aliyun">Alibaba</option><option value="custom">Custom</option></select>
      <input v-model="drafts[routeKey].model" class="border rounded px-2 py-1 text-sm" placeholder="Model" />
      <input v-model="drafts[routeKey].endpoint" class="border rounded px-2 py-1 text-sm" placeholder="Endpoint" />
      <input v-model="drafts[routeKey].api_key" type="password" class="border rounded px-2 py-1 text-sm" placeholder="API key" />
      <button type="button" class="button" @click="save(routeKey)">{{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.SAVE_ROUTE') }}</button>
    </div>
    <p class="text-xs text-slate-500">{{ t('CAPTAIN_SETTINGS.MODEL_CONFIG.EMBEDDING_DIMENSIONS') }}</p>
  </div>
</template>
