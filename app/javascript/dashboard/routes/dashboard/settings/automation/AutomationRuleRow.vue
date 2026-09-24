<script setup>
import { computed } from 'vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import { formatDelay } from 'dashboard/helper/automationHelper';
import { getTime } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

const props = defineProps({
  automation: {
    type: Object,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'edit', 'delete', 'clone']);

const readableDate = date => messageStamp(new Date(date), 'LLL d, yyyy');
const readableDateWithTime = date =>
  messageStamp(new Date(date), 'LLL d, yyyy hh:mm a');

const formatWindowTime = minutes =>
  getTime(Math.floor(minutes / 60), minutes % 60);

const executionWindowLabel = computed(() => {
  const {
    execution_window_start_minutes: start,
    execution_window_end_minutes: end,
  } = props.automation;
  if (start == null || end == null) return '';
  return `${formatWindowTime(start)} - ${formatWindowTime(end)}`;
});

const automationActive = computed({
  get: () => props.automation.active,
  set: active => {
    const { id, name } = props.automation;
    emit('toggle', {
      id,
      name,
      status: !active,
    });
  },
});
</script>

<template>
  <BaseTableRow :item="automation">
    <template #default>
      <BaseTableCell class="max-w-0 w-full">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-body-main text-n-slate-12 truncate">
            {{ automation.name }}
          </span>
          <span
            v-if="automation.execution_delay"
            class="text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 whitespace-nowrap flex-shrink-0"
          >
            {{
              $t('AUTOMATION.LIST.DELAY_BADGE', {
                delay: formatDelay(automation.execution_delay),
              })
            }}
          </span>
          <span
            v-if="executionWindowLabel"
            class="text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 whitespace-nowrap flex-shrink-0"
          >
            {{
              $t('AUTOMATION.LIST.WINDOW_BADGE', {
                window: executionWindowLabel,
              })
            }}
          </span>
          <div class="w-px h-3 rounded-lg bg-n-weak flex-shrink-0" />
          <span class="text-body-main text-n-slate-11 truncate">
            {{ automation.description }}
          </span>
        </div>
      </BaseTableCell>

      <BaseTableCell>
        <ToggleSwitch v-model="automationActive" />
      </BaseTableCell>

      <BaseTableCell :title="readableDateWithTime(automation.created_on)">
        <span class="text-body-main text-n-slate-12 whitespace-nowrap">
          {{ readableDate(automation.created_on) }}
        </span>
      </BaseTableCell>

      <BaseTableCell align="end">
        <div class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.EDIT')"
            icon="i-woot-edit-pen"
            slate
            sm
            :is-loading="loading"
            @click="$emit('edit', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.CLONE.TOOLTIP')"
            icon="i-woot-clone"
            sm
            slate
            :is-loading="loading"
            @click="$emit('clone', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.DELETE')"
            :is-loading="loading"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="$emit('delete', automation)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
