/* global axios */
import ApiClient from './ApiClient';

class LiveReportsAPI extends ApiClient {
  constructor() {
    super('live_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getConversationMetric(params = {}) {
    return axios.get(`${this.url}/conversation_metrics`, { params });
  }

  getGroupedConversations({ groupBy } = { groupBy: 'assignee_id' }) {
    return axios.get(`${this.url}/grouped_conversation_metrics`, {
      params: { group_by: groupBy },
    });
  }

  getJourneyMetrics({ since, teamId } = {}) {
    return axios.get(`${this.url}/journey_metrics`, {
      params: { since, team_id: teamId },
    });
  }
}

export default new LiveReportsAPI();
