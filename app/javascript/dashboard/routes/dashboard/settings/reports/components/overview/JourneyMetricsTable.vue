<script setup>
import { computed, h } from 'vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import { useI18n } from 'vue-i18n';
import { formatDuration } from 'shared/helpers/timeHelper';

import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Table from 'dashboard/components/table/Table.vue';

const props = defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
  nameHeader: {
    type: String,
    required: true,
  },
  // Metric keys from the journey_metrics endpoint, in display order.
  metricKeys: {
    type: Array,
    required: true,
  },
  emptyMessage: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const DURATION_KEYS = [
  'longest_wait',
  'average_wait',
  'average_first_reply',
  'average_handling',
  'average_bot_time',
];

const metricLabels = computed(() => ({
  waiting: t('OVERVIEW_REPORTS.JOURNEY.WAITING'),
  longest_wait: t('OVERVIEW_REPORTS.JOURNEY.LONGEST_WAIT'),
  in_service: t('OVERVIEW_REPORTS.JOURNEY.IN_SERVICE'),
  awaiting_first_reply: t('OVERVIEW_REPORTS.JOURNEY.AWAITING_FIRST_REPLY'),
  resolved: t('OVERVIEW_REPORTS.JOURNEY.RESOLVED'),
  average_wait: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_WAIT'),
  average_first_reply: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_FIRST_REPLY'),
  average_handling: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_HANDLING'),
  average_bot_time: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_BOT_TIME'),
}));

const formatMetric = (key, value) => {
  if (value === null || value === undefined) return '---';
  if (DURATION_KEYS.includes(key)) return formatDuration(value);
  return value;
};

const renderCell = cellProps =>
  h(
    'span',
    { class: 'text-n-slate-12' },
    formatMetric(cellProps.column.id, cellProps.getValue())
  );

const columnHelper = createColumnHelper();
const columns = computed(() => [
  columnHelper.accessor('name', {
    header: props.nameHeader,
    cell: cellProps =>
      h('span', { class: 'text-n-slate-12' }, cellProps.getValue()),
    size: 220,
  }),
  ...props.metricKeys.map(key =>
    columnHelper.accessor(key, {
      id: key,
      header: metricLabels.value[key],
      cell: renderCell,
      size: 130,
    })
  ),
]);

const table = useVueTable({
  get data() {
    return props.rows;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
</script>

<template>
  <div class="flex flex-col flex-1">
    <Table v-if="rows.length" :table="table" />
    <EmptyState v-else :title="emptyMessage" />
  </div>
</template>
