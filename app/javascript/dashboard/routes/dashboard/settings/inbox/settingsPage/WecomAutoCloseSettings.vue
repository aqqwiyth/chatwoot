<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const store = useStore();
const { t } = useI18n();
const timeout = ref(0);
const invitationEnabled = ref(false);
const invitationMessage = ref('');
const isSaving = ref(false);
const invitationMessageValid = computed(
  () =>
    !invitationEnabled.value ||
    (invitationMessage.value.trim().length > 0 &&
      new TextEncoder().encode(invitationMessage.value.trim()).length <= 1024)
);

watch(
  () => props.inbox,
  inbox => {
    timeout.value = inbox.auto_close_after_minutes ?? 0;
    invitationEnabled.value = inbox.satisfaction_invitation_enabled ?? false;
    invitationMessage.value =
      inbox.satisfaction_invitation_message ?? '你对本次服务是否满意？';
  },
  { immediate: true }
);

const save = async () => {
  isSaving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        auto_close_after_minutes: timeout.value,
        satisfaction_invitation_enabled: invitationEnabled.value,
        satisfaction_invitation_message: invitationMessage.value.trim(),
      },
    });
    useAlert(
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SUCCESS')
    );
  } catch (error) {
    useAlert(
      error.message ||
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.TITLE')
    "
    :help-text="
      t(
        'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.DESCRIPTION'
      )
    "
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <label>
        {{
          t(
            'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.TIMEOUT'
          )
        }}
        <select v-model.number="timeout">
          <option :value="0">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.DISABLED'
              )
            }}
          </option>
          <option :value="10">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.MINUTES',
                { count: 10 }
              )
            }}
          </option>
          <option :value="30">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.MINUTES',
                { count: 30 }
              )
            }}
          </option>
          <option :value="60">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.HOUR'
              )
            }}
          </option>
          <option :value="720">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.HOURS',
                { count: 12 }
              )
            }}
          </option>
          <option :value="2880">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.HOURS',
                { count: 48 }
              )
            }}
          </option>
        </select>
      </label>
      <label class="flex items-center gap-2">
        <input v-model="invitationEnabled" type="checkbox" />
        {{
          t(
            'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION'
          )
        }}
      </label>
      <template v-if="invitationEnabled">
        <p class="text-n-slate-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_HELP'
            )
          }}
        </p>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_MESSAGE'
            )
          }}
          <textarea v-model="invitationMessage" required />
          <span class="text-n-slate-11">{{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_LIMIT'
            )
          }}</span>
        </label>
      </template>
      <NextButton
        type="submit"
        :disabled="isSaving || !invitationMessageValid"
        :is-loading="isSaving"
      >
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SAVE')
        }}
      </NextButton>
    </form>
  </SettingsFieldSection>
</template>
