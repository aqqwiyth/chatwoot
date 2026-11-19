<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import WecomOpenData from './WecomOpenData.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const emit = defineEmits(['enabledChange']);
const store = useStore();
const { t } = useI18n();
const enabled = ref(true);
watch(enabled, value => emit('enabledChange', value), { immediate: true });
const queueEnabled = ref(true);
const queueAutoAssign = ref(false);
const maxConcurrent = ref(10);
const assignedMessage = ref('');
const outsideMessage = ref('');
const busyMessage = ref('');
const saving = ref(false);
const loadingDirectory = ref(false);
const syncing = ref(false);
const directoryLoaded = ref(false);
const departments = ref([]);
const departmentId = ref('');
const members = ref([]);
const selected = ref([]);
const selectedNames = ref({});
const platformDepartments = ref([]);
const openDataReady = ref(false);
const openDataError = ref(false);
const isIsv = computed(() => props.inbox.credential_mode === 'isv');
const messagesValid = computed(
  () => outsideMessage.value.trim() && busyMessage.value.trim()
);

watch(
  () => props.inbox,
  inbox => {
    enabled.value = inbox.human_reception_enabled ?? true;
    queueEnabled.value = inbox.reception_queue_enabled ?? true;
    queueAutoAssign.value = inbox.reception_queue_auto_assign ?? false;
    maxConcurrent.value = inbox.max_concurrent_receptions ?? 10;
    assignedMessage.value = inbox.session_assigned_message || '';
    outsideMessage.value = inbox.outside_reception_hours_message || '';
    busyMessage.value = inbox.reception_busy_message || '';
  },
  { immediate: true }
);

const save = async () => {
  if (!messagesValid.value || saving.value) return;
  saving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        human_reception_enabled: enabled.value,
        reception_queue_enabled: queueEnabled.value,
        reception_queue_auto_assign: queueAutoAssign.value,
        max_concurrent_receptions: maxConcurrent.value,
        session_assigned_message: assignedMessage.value.trim(),
        outside_reception_hours_message: outsideMessage.value.trim(),
        reception_busy_message: busyMessage.value.trim(),
      },
    });
    useAlert(
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SUCCESS')
    );
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.ERROR')
    );
  } finally {
    saving.value = false;
  }
};

const loadScript = src =>
  new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = src;
    script.referrerPolicy = 'origin';
    script.onload = resolve;
    script.onerror = reject;
    document.head.appendChild(script);
  });

const initializeOpenData = async () => {
  if (!isIsv.value || openDataReady.value) return;
  openDataError.value = false;
  try {
    const url = window.location.href.split('#')[0];
    const { data } = await InboxesAPI.getWecomJsSignature(props.inbox.id, url);
    if (!window.wx) {
      await loadScript('https://res.wx.qq.com/open/js/jweixin-1.2.0.js');
    }
    await loadScript(
      'https://open.work.weixin.qq.com/wwopen/js/jwxwork-1.0.0.js'
    );
    const { wx } = window;
    if (/MicroMessenger/i.test(navigator.userAgent)) {
      await new Promise((resolve, reject) => {
        wx.config({
          beta: true,
          appId: data.corpid,
          timestamp: data.timestamp,
          nonceStr: data.nonceStr,
          signature: data.configSignature,
          jsApiList: [],
        });
        wx.ready(resolve);
        wx.error(reject);
      });
    }
    await new Promise((resolve, reject) => {
      wx.agentConfig({
        corpid: data.corpid,
        agentid: data.agentid,
        timestamp: data.timestamp,
        nonceStr: data.nonceStr,
        signature: data.agentSignature,
        jsApiList: [],
        success: resolve,
        fail: reject,
      });
    });
    if (!window.WWOpenData) throw new Error('WeCom open-data unavailable');
    if (window.WWOpenData.on) {
      window.WWOpenData.on('error', () => {
        openDataReady.value = false;
        openDataError.value = true;
      });
    }
    if (window.WWOpenData.checkSession) {
      await new Promise((success, fail) => {
        window.WWOpenData.checkSession({ success, fail });
      });
    }
    openDataReady.value = true;
  } catch (error) {
    openDataError.value = true;
  }
};

const loadDirectory = async () => {
  loadingDirectory.value = true;
  try {
    const { data } = await InboxesAPI.getWecomReception(props.inbox.id);
    departments.value = data.departments;
    selectedNames.value = { ...data.servicer_names, ...selectedNames.value };
    selected.value = data.servicers
      .filter(item => item.userid)
      .map(item => item.userid);
    platformDepartments.value = data.servicers
      .filter(item => item.department_id)
      .map(item => item.department_id);
    directoryLoaded.value = true;
    await initializeOpenData();
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t(
          'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.DIRECTORY_ERROR'
        )
    );
  } finally {
    loadingDirectory.value = false;
  }
};

const loadMembers = async () => {
  members.value = [];
  if (!departmentId.value) return;
  loadingDirectory.value = true;
  try {
    const { data } = await InboxesAPI.getWecomDepartmentMembers(
      props.inbox.id,
      departmentId.value
    );
    members.value = data.members;
    data.members.forEach(member => {
      selectedNames.value[member.userid] = member.name;
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t(
          'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.DIRECTORY_ERROR'
        )
    );
  } finally {
    loadingDirectory.value = false;
  }
};

const syncServicers = async () => {
  syncing.value = true;
  try {
    const { data } = await InboxesAPI.syncWecomServicers(
      props.inbox.id,
      selected.value,
      selectedNames.value
    );
    selected.value = data.servicers
      .filter(item => item.userid)
      .map(item => item.userid);
    selectedNames.value = { ...selectedNames.value, ...data.servicer_names };
    useAlert(
      t(
        'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SYNC_SUCCESS'
      )
    );
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t(
          'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SYNC_ERROR'
        )
    );
    // The platform may have applied part of a batch before reporting a failure.
    await loadDirectory();
  } finally {
    syncing.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    :label="
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.TITLE')
    "
    :help-text="
      t(
        'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.DESCRIPTION'
      )
    "
  >
    <form class="flex flex-col gap-4" @submit.prevent="save">
      <SettingsToggleSection
        v-model="enabled"
        :header="
          t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.ENABLE')
        "
      />
      <template v-if="enabled">
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.MAX_CONCURRENT'
            )
          }}
          <input
            v-model.number="maxConcurrent"
            type="number"
            min="1"
            required
          />
        </label>
        <SettingsToggleSection
          v-model="queueEnabled"
          :header="
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.QUEUE'
            )
          "
          :description="
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.QUEUE_HELP'
            )
          "
        />
        <SettingsToggleSection
          v-if="queueEnabled"
          v-model="queueAutoAssign"
          :header="
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.AUTO_QUEUE'
            )
          "
          :description="
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.AUTO_QUEUE_HELP'
            )
          "
        />
        <p class="text-body-main text-n-slate-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.HOURS_HELP'
            )
          }}
        </p>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.SESSION_ASSIGNED_MESSAGE'
            )
          }}
          <textarea v-model="assignedMessage" maxlength="500" />
        </label>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.OUTSIDE_MESSAGE'
            )
          }}
          <textarea v-model="outsideMessage" maxlength="500" required />
          <span class="text-n-slate-11">{{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.OUTSIDE_HELP'
            )
          }}</span>
        </label>
        <label>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.BUSY_MESSAGE'
            )
          }}
          <textarea v-model="busyMessage" maxlength="500" required />
          <span class="text-n-slate-11">{{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.BUSY_HELP'
            )
          }}</span>
        </label>
      </template>
      <NextButton
        type="submit"
        :is-loading="saving"
        :disabled="!messagesValid || saving"
      >
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SAVE')
        }}
      </NextButton>
    </form>
  </SettingsFieldSection>

  <SettingsFieldSection
    :label="
      t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SERVICERS')
    "
    :help-text="
      t(
        'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SERVICERS_HELP'
      )
    "
  >
    <fieldset
      :disabled="!enabled"
      class="flex flex-col gap-4 border-0 p-0 m-0 disabled:opacity-50"
    >
      <NextButton
        type="button"
        :is-loading="loadingDirectory"
        @click="loadDirectory"
      >
        {{
          t(
            'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.LOAD_DIRECTORY'
          )
        }}
      </NextButton>
      <template v-if="directoryLoaded">
        <p
          v-if="platformDepartments.length"
          class="text-body-main text-n-slate-11"
        >
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.PLATFORM_DEPARTMENTS',
              {
                ids: platformDepartments.join(', '),
              }
            )
          }}
        </p>
        <p v-if="openDataError" class="text-body-main text-n-ruby-11">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.OPEN_DATA_ERROR'
            )
          }}
        </p>
        <fieldset v-if="isIsv" class="flex flex-col gap-2 border-0 p-0 m-0">
          <legend>
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.DEPARTMENT'
              )
            }}
          </legend>
          <label
            v-for="department in departments"
            :key="department.id"
            class="flex items-center gap-2"
          >
            <input
              v-model="departmentId"
              type="radio"
              :value="department.id"
              @change="loadMembers"
            />
            <WecomOpenData
              v-if="openDataReady"
              type="departmentName"
              :openid="department.id"
            />
            <span v-else>{{ department.name }}</span>
            <span>{{ `(${department.id})` }}</span>
          </label>
        </fieldset>
        <label v-else>
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.DEPARTMENT'
            )
          }}
          <select v-model="departmentId" @change="loadMembers">
            <option value="">
              {{
                t(
                  'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SELECT_DEPARTMENT'
                )
              }}
            </option>
            <option
              v-for="department in departments"
              :key="department.id"
              :value="department.id"
            >
              {{ `${department.name} (${department.id})` }}
            </option>
          </select>
        </label>
        <div class="flex flex-wrap gap-4">
          <label
            v-for="member in members"
            :key="member.userid"
            class="flex items-center gap-2"
          >
            <input v-model="selected" type="checkbox" :value="member.userid" />
            <WecomOpenData
              v-if="isIsv && openDataReady"
              type="userName"
              :openid="member.userid"
            />
            <span v-else>{{ member.name }}</span>
            <span>{{ `(${member.userid})` }}</span>
          </label>
        </div>
        <div>
          <p class="text-heading-3">
            {{
              t(
                'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SELECTED'
              )
            }}
          </p>
          <div
            v-for="userid in selected"
            :key="userid"
            class="flex items-center gap-2"
          >
            <WecomOpenData
              v-if="isIsv && openDataReady"
              type="userName"
              :openid="userid"
            />
            <span v-else>{{ selectedNames[userid] || userid }}</span>
            <button
              type="button"
              class="text-n-brand"
              @click="selected = selected.filter(id => id !== userid)"
            >
              {{
                t(
                  'INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.REMOVE'
                )
              }}
            </button>
          </div>
        </div>
        <NextButton
          type="button"
          :is-loading="syncing"
          :disabled="syncing || loadingDirectory"
          @click="syncServicers"
        >
          {{
            t('INBOX_MGMT.SETTINGS_POPUP.WECOM_CUSTOMER_SERVICE.RECEPTION.SYNC')
          }}
        </NextButton>
      </template>
    </fieldset>
  </SettingsFieldSection>
</template>
