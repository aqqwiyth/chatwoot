<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

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
        <label>
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
            {{ `${member.name} (${member.userid})` }}
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
            <span>{{ selectedNames[userid] || userid }}</span>
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
