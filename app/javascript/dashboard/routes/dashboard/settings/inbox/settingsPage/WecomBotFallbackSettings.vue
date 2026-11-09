<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});

const store = useStore();
const { t } = useI18n();
const MIN_TIMEOUT_SECONDS = 60;
const MAX_TIMEOUT_SECONDS = 300;
const DEFAULT_TIMEOUT_SECONDS = 120;
const timeoutSeconds = ref(DEFAULT_TIMEOUT_SECONDS);
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
    timeoutSeconds.value =
      inbox.bot_fallback_timeout_seconds ?? DEFAULT_TIMEOUT_SECONDS;
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
        bot_fallback_timeout_seconds: timeoutSeconds.value,
      },
    });
    useAlert(
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.SUCCESS')
    );
  } catch (error) {
    useAlert(
      error.message ||
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.TITLE')
    "
    :help-text="
      t(
        'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.DESCRIPTION'
      )
    "
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <fieldset
        :disabled="disabled"
        class="flex flex-col gap-4 border-0 p-0 m-0 disabled:opacity-50"
      >
        <p class="text-n-slate-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.REQUIRED_NOTICE'
            )
          }}
        </p>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.TIMEOUT_RANGE'
            )
          }}
          <input
            v-model.number="timeoutSeconds"
            type="number"
            :min="MIN_TIMEOUT_SECONDS"
            :max="MAX_TIMEOUT_SECONDS"
            step="1"
            required
          />
        </label>
        <NextButton
          type="submit"
          :disabled="!isTimeoutValid || isSaving"
          :is-loading="isSaving"
        >
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.BOT_FALLBACK.SAVE'
            )
          }}
        </NextButton>
      </fieldset>
    </form>
  </SettingsFieldSection>
</template>
