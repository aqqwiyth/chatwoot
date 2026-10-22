<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();
const I18N_PREFIX =
  'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK';
const MIN_TIMEOUT_SECONDS = 1;
const MAX_TIMEOUT_SECONDS = 3600;
const DEFAULT_TIMEOUT_SECONDS = 30;
const enabled = ref(false);
const timeoutSeconds = ref(DEFAULT_TIMEOUT_SECONDS);
const target = ref('wecom_platform');
const isSaving = ref(false);
const isTimeoutValid = computed(
  () =>
    Number.isInteger(timeoutSeconds.value) &&
    timeoutSeconds.value >= MIN_TIMEOUT_SECONDS &&
    timeoutSeconds.value <= MAX_TIMEOUT_SECONDS
);

watch(
  () => props.inbox,
  inbox => {
    enabled.value = inbox.bot_fallback_enabled ?? false;
    timeoutSeconds.value =
      inbox.bot_fallback_timeout_seconds ?? DEFAULT_TIMEOUT_SECONDS;
    target.value = inbox.bot_fallback_target ?? 'wecom_platform';
  },
  { immediate: true }
);

const save = async () => {
  if (!isTimeoutValid.value || isSaving.value) return;

  isSaving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        bot_fallback_enabled: enabled.value,
        bot_fallback_timeout_seconds: timeoutSeconds.value,
        bot_fallback_target: target.value,
      },
    });
    useAlert(t(`${I18N_PREFIX}.SUCCESS`));
  } catch (error) {
    useAlert(error.message || t(`${I18N_PREFIX}.ERROR`));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="t(`${I18N_PREFIX}.TITLE`)"
    :help-text="t(`${I18N_PREFIX}.DESCRIPTION`)"
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <SettingsToggleSection
        v-model="enabled"
        :header="t(`${I18N_PREFIX}.ENABLE`)"
        :description="t(`${I18N_PREFIX}.BOT_NOTICE`)"
      />
      <label>
        {{ t(`${I18N_PREFIX}.TIMEOUT`) }}
        <input
          v-model.number="timeoutSeconds"
          type="number"
          :min="MIN_TIMEOUT_SECONDS"
          :max="MAX_TIMEOUT_SECONDS"
          step="1"
          required
        />
      </label>
      <label>
        {{ t(`${I18N_PREFIX}.TARGET`) }}
        <select v-model="target">
          <option value="wecom_platform">
            {{ t(`${I18N_PREFIX}.WECOM_PLATFORM`) }}
          </option>
          <option value="chatwoot">
            {{ t(`${I18N_PREFIX}.CHATWOOT`) }}
          </option>
        </select>
      </label>
      <NextButton
        type="submit"
        :disabled="!isTimeoutValid || isSaving"
        :is-loading="isSaving"
      >
        {{ t(`${I18N_PREFIX}.SAVE`) }}
      </NextButton>
    </form>
  </SettingsFieldSection>
</template>
