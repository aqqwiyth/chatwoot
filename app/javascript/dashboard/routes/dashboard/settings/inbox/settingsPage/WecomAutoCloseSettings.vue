<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const SCOPES = ['ai', 'handoff_auto', 'handoff_manual', 'direct'];
const MANUAL_SCOPE = 'handoff_manual';
const TIMEOUT_OPTIONS = [0, 10, 20, 30, 60, 720, 2880];
const MESSAGE_BYTE_LIMIT = 1024;

const blankConfig = () => ({
  auto_close_after_minutes: 0,
  satisfaction_enabled: false,
  satisfaction_message: '',
  ending_message: '',
});

const store = useStore();
const { t } = useI18n();
const isSaving = ref(false);
const form = reactive(
  Object.fromEntries(SCOPES.map(scope => [scope, blankConfig()]))
);

watch(
  () => props.inbox,
  inbox => {
    const configs = inbox.end_configs || [];
    SCOPES.forEach(scope => {
      const config =
        configs.find(item => item.scope === scope) || blankConfig();
      Object.assign(form[scope], {
        auto_close_after_minutes: config.auto_close_after_minutes ?? 0,
        satisfaction_enabled: config.satisfaction_enabled ?? false,
        satisfaction_message: config.satisfaction_message ?? '',
        ending_message: config.ending_message ?? '',
      });
    });
  },
  { immediate: true }
);

const byteSize = value => new TextEncoder().encode(value || '').length;

const scopeLabels = {
  ai: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPES.AI'
  ),
  handoff_auto: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPES.HANDOFF_AUTO'
  ),
  handoff_manual: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPES.HANDOFF_MANUAL'
  ),
  direct: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPES.DIRECT'
  ),
};

const scopeHelp = {
  ai: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPE_HELP.AI'
  ),
  handoff_auto: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPE_HELP.HANDOFF_AUTO'
  ),
  handoff_manual: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPE_HELP.HANDOFF_MANUAL'
  ),
  direct: t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SCOPE_HELP.DIRECT'
  ),
};

const timeoutLabel = value => {
  if (value === 0) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.DISABLED'
    );
  }
  if (value === 60) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.HOUR'
    );
  }
  if (value >= 720) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.HOURS',
      { count: value / 60 }
    );
  }

  return t(
    'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.MINUTES',
    { count: value }
  );
};

const isValid = computed(() =>
  SCOPES.every(scope => {
    const endingMessage = form[scope].ending_message.trim();
    if (byteSize(endingMessage) > MESSAGE_BYTE_LIMIT) return false;
    if (!form[scope].satisfaction_enabled) return true;

    const satisfactionMessage = form[scope].satisfaction_message.trim();
    if (
      !satisfactionMessage ||
      byteSize(satisfactionMessage) > MESSAGE_BYTE_LIMIT
    ) {
      return false;
    }

    return (
      byteSize(
        [endingMessage, satisfactionMessage].filter(Boolean).join('\n')
      ) <= MESSAGE_BYTE_LIMIT
    );
  })
);

const save = async () => {
  isSaving.value = true;
  try {
    const endConfigs = SCOPES.map(scope => ({
      scope,
      auto_close_after_minutes: form[scope].auto_close_after_minutes,
      satisfaction_enabled: form[scope].satisfaction_enabled,
      satisfaction_message: form[scope].satisfaction_message.trim(),
      ending_message: form[scope].ending_message.trim(),
    }));
    await store.dispatch('inboxes/updateWecomEndConfigs', {
      id: props.inbox.id,
      endConfigs,
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
  <form class="flex flex-col gap-8" @submit.prevent="save">
    <SettingsFieldSection
      :label="
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.TITLE')
      "
      :help-text="
        t(
          'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.DESCRIPTION'
        )
      "
    />
    <SettingsFieldSection
      v-for="scope in SCOPES"
      :key="scope"
      :label="scopeLabels[scope]"
      :help-text="scopeHelp[scope]"
    >
      <div class="flex flex-col gap-4">
        <label v-if="scope !== MANUAL_SCOPE">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.TIMEOUT'
            )
          }}
          <select v-model.number="form[scope].auto_close_after_minutes">
            <option
              v-for="option in TIMEOUT_OPTIONS"
              :key="option"
              :value="option"
            >
              {{ timeoutLabel(option) }}
            </option>
          </select>
        </label>
        <p v-else class="text-n-slate-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.MANUAL_NO_TIMEOUT'
            )
          }}
        </p>
        <label class="flex items-center gap-2">
          <input v-model="form[scope].satisfaction_enabled" type="checkbox" />
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION'
            )
          }}
        </label>
        <p v-if="form[scope].satisfaction_enabled" class="text-n-slate-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_HELP'
            )
          }}
        </p>
        <label v-if="form[scope].satisfaction_enabled">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_MESSAGE'
            )
          }}
          <textarea v-model="form[scope].satisfaction_message" rows="2" />
          <span class="text-n-slate-11">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.INVITATION_LIMIT'
              )
            }}
          </span>
        </label>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.ENDING_MESSAGE'
            )
          }}
          <textarea v-model="form[scope].ending_message" rows="2" />
          <span class="text-n-slate-11">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.ENDING_MESSAGE_HELP'
              )
            }}
          </span>
        </label>
      </div>
    </SettingsFieldSection>
    <NextButton
      type="submit"
      :disabled="isSaving || !isValid"
      :is-loading="isSaving"
    >
      {{
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.AUTO_CLOSE.SAVE')
      }}
    </NextButton>
  </form>
</template>
