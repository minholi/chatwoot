<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { getUnixTime, startOfDay } from 'date-fns';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import { formatDuration } from 'shared/helpers/timeHelper';
import LiveReportsAPI from 'dashboard/api/liveReports';

import MetricCard from './overview/MetricCard.vue';
import JourneyMetricsTable from './overview/JourneyMetricsTable.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// The queue changes minute by minute, so refresh faster than the other overview cards.
const JOURNEY_REFRESH_INTERVAL_MS = 30000;
const TEAM_METRIC_KEYS = [
  'waiting',
  'longest_wait',
  'in_service',
  'resolved',
  'average_wait',
  'average_first_reply',
  'average_handling',
];
const AGENT_METRIC_KEYS = [
  'in_service',
  'awaiting_first_reply',
  'resolved',
  'average_first_reply',
  'average_handling',
];

const { t } = useI18n();
const store = useStore();
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const metrics = ref({ summary: {}, teams: [], agents: [] });
const isLoading = ref(true);
const selectedTeam = ref(null);
const [showDropdown, toggleDropdown] = useToggle();

const fetchData = async () => {
  try {
    const { data } = await LiveReportsAPI.getJourneyMetrics({
      since: getUnixTime(startOfDay(new Date())),
      teamId: selectedTeam.value || undefined,
    });
    metrics.value = data;
  } finally {
    isLoading.value = false;
  }
};

const { startRefetching } = useLiveRefresh(
  fetchData,
  JOURNEY_REFRESH_INTERVAL_MS
);

const teamMenuList = computed(() => [
  { label: t('OVERVIEW_REPORTS.TEAM_CONVERSATIONS.ALL_TEAMS'), value: null },
  ...teams.value.map(team => ({ label: team.name, value: team.id })),
]);

const selectedTeamLabel = computed(
  () =>
    teamMenuList.value.find(item => item.value === selectedTeam.value)?.label
);

const handleTeamChange = ({ value }) => {
  toggleDropdown(false);
  selectedTeam.value = value;
  fetchData();
};

const formatCount = value => value ?? 0;
const formatTime = value =>
  value === null || value === undefined ? '---' : formatDuration(value);

const sections = computed(() => {
  const { summary } = metrics.value;
  return [
    {
      key: 'now',
      title: t('OVERVIEW_REPORTS.JOURNEY.NOW'),
      stats: [
        {
          key: 'waiting',
          label: t('OVERVIEW_REPORTS.JOURNEY.WAITING'),
          value: formatCount(summary.waiting),
        },
        {
          key: 'longest_wait',
          label: t('OVERVIEW_REPORTS.JOURNEY.LONGEST_WAIT'),
          value: formatTime(summary.longest_wait),
        },
        {
          key: 'in_service',
          label: t('OVERVIEW_REPORTS.JOURNEY.IN_SERVICE'),
          value: formatCount(summary.in_service),
        },
        {
          key: 'awaiting_first_reply',
          label: t('OVERVIEW_REPORTS.JOURNEY.AWAITING_FIRST_REPLY'),
          value: formatCount(summary.awaiting_first_reply),
        },
      ],
    },
    {
      key: 'today',
      title: t('OVERVIEW_REPORTS.JOURNEY.TODAY'),
      stats: [
        {
          key: 'resolved',
          label: t('OVERVIEW_REPORTS.JOURNEY.RESOLVED'),
          value: formatCount(summary.resolved),
        },
        {
          key: 'average_wait',
          label: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_WAIT'),
          value: formatTime(summary.average_wait),
        },
        {
          key: 'average_first_reply',
          label: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_FIRST_REPLY'),
          value: formatTime(summary.average_first_reply),
        },
        {
          key: 'average_handling',
          label: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_HANDLING'),
          value: formatTime(summary.average_handling),
        },
        {
          key: 'average_bot_time',
          label: t('OVERVIEW_REPORTS.JOURNEY.AVERAGE_BOT_TIME'),
          value: formatTime(summary.average_bot_time),
        },
      ],
    },
  ];
});

const teamRows = computed(() =>
  metrics.value.teams
    .map(teamMetrics => ({
      ...teamMetrics,
      name:
        teams.value.find(team => team.id === teamMetrics.team_id)?.name ||
        `#${teamMetrics.team_id}`,
    }))
    .sort((a, b) => b.waiting - a.waiting || b.in_service - a.in_service)
);

const agentRows = computed(() =>
  metrics.value.agents
    .map(agentMetrics => ({
      ...agentMetrics,
      name:
        agents.value.find(agent => agent.id === agentMetrics.assignee_id)
          ?.name || `#${agentMetrics.assignee_id}`,
    }))
    .sort((a, b) => b.in_service - a.in_service || b.resolved - a.resolved)
);

onMounted(() => {
  store.dispatch('teams/get');
  store.dispatch('agents/get');
  fetchData();
  startRefetching();
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <MetricCard
      :header="t('OVERVIEW_REPORTS.JOURNEY.HEADER')"
      :is-loading="isLoading"
      :loading-message="t('OVERVIEW_REPORTS.JOURNEY.LOADING_MESSAGE')"
    >
      <template v-if="teams.length" #control>
        <div
          v-on-clickaway="() => toggleDropdown(false)"
          class="relative flex items-center group z-50"
        >
          <Button
            sm
            slate
            faded
            :label="selectedTeamLabel"
            class="capitalize rounded-md group-hover:bg-n-alpha-2"
            @click="toggleDropdown()"
          />
          <DropdownMenu
            v-if="showDropdown"
            :menu-items="teamMenuList"
            class="mt-1 ltr:right-0 rtl:left-0 top-full"
            label-class="capitalize"
            @action="handleTeamChange($event)"
          />
        </div>
      </template>
      <div class="flex flex-col w-full gap-6">
        <div
          v-for="section in sections"
          :key="section.key"
          class="flex flex-col gap-3"
        >
          <span class="text-xs font-medium uppercase text-n-slate-11">
            {{ section.title }}
          </span>
          <div class="grid grid-cols-2 gap-4 md:grid-cols-5">
            <div v-for="stat in section.stats" :key="stat.key" class="min-w-0">
              <h3 class="mb-0 text-base text-n-slate-11">{{ stat.label }}</h3>
              <p class="mt-1 mb-0 text-3xl text-n-slate-12">
                {{ stat.value }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </MetricCard>
    <MetricCard :header="t('OVERVIEW_REPORTS.JOURNEY.TEAMS_HEADER')">
      <JourneyMetricsTable
        :rows="teamRows"
        :name-header="t('OVERVIEW_REPORTS.JOURNEY.TEAM')"
        :metric-keys="TEAM_METRIC_KEYS"
        :empty-message="t('OVERVIEW_REPORTS.JOURNEY.NO_DATA')"
      />
    </MetricCard>
    <MetricCard :header="t('OVERVIEW_REPORTS.JOURNEY.AGENTS_HEADER')">
      <JourneyMetricsTable
        :rows="agentRows"
        :name-header="t('OVERVIEW_REPORTS.JOURNEY.AGENT')"
        :metric-keys="AGENT_METRIC_KEYS"
        :empty-message="t('OVERVIEW_REPORTS.JOURNEY.NO_DATA')"
      />
    </MetricCard>
  </div>
</template>
