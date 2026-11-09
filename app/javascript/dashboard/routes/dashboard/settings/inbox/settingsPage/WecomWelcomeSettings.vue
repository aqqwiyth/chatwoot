<script setup>
import { ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import GreetingsEditor from 'shared/components/GreetingsEditor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const store = useStore();
const { t } = useI18n();
const enabled = ref(false);
const message = ref('');
const saving = ref(false);
watch(
  () => props.inbox,
  inbox => {
    enabled.value = inbox.greeting_enabled ?? false;
    message.value = inbox.greeting_message || '';
  },
  { immediate: true }
);

const save = async () => {
  saving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      greeting_enabled: enabled.value,
      greeting_message: message.value,
    });
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.SUCCESS'));
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.ERROR')
    );
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.TAB_WELCOME')"
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <SettingsToggleSection
        v-model="enabled"
        :header="
          t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_GREETING_TOGGLE.LABEL')
        "
        :description="
          t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_GREETING_TOGGLE.HELP_TEXT')
        "
      />
      <GreetingsEditor
        v-if="enabled"
        v-model="message"
        :richtext="false"
        :label="
          t('INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_GREETING_MESSAGE.LABEL')
        "
        :placeholder="
          t(
            'INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_GREETING_MESSAGE.PLACEHOLDER'
          )
        "
      />
      <NextButton type="submit" :disabled="saving" :is-loading="saving">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.SAVE') }}
      </NextButton>
    </form>
  </SettingsFieldSection>
</template>
