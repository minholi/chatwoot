require 'rails_helper'

RSpec.describe V2::Reports::JourneyMetricsBuilder do
  subject(:builder) { described_class.new(account: account, since: now.beginning_of_day, team_id: team_id) }

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:now) { Time.zone.parse('2026-11-24 15:00:00') }
  let(:team_id) { nil }

  around { |example| travel_to(now) { example.run } }

  # update_columns grava os marcos exatos de cada cenário; os callbacks da jornada os recalculariam com o horário atual.
  # rubocop:disable Rails/SkipsModelValidations
  before do
    # Na fila há 30 min, depois de 5 min com o bot
    create(:conversation, account: account, team: team)
      .update_columns(created_at: now - 35.minutes, started_at: now - 30.minutes, opened_at: nil)
    # Na fila há 10 min, nasceu direto na fila (sem bot), de outro time
    create(:conversation, account: account, team: other_team)
      .update_columns(created_at: now - 10.minutes, started_at: now - 10.minutes, opened_at: nil)
    # Em atendimento: 4 min de fila, ainda sem resposta do agente
    create(:conversation, account: account, team: team)
      .update_columns(assignee_id: agent.id, created_at: now - 20.minutes, started_at: now - 20.minutes, opened_at: now - 16.minutes)
    # Resolvida hoje: 2 min de fila, 1 min até a 1ª resposta, 20 min de atendimento
    create(:conversation, account: account, team: team, status: :resolved)
      .update_columns(assignee_id: agent.id, created_at: now - 60.minutes, started_at: now - 60.minutes, opened_at: now - 58.minutes,
                      human_first_reply_at: now - 57.minutes, closed_at: now - 38.minutes)
    # Resolvida ontem: fora dos indicadores de hoje
    create(:conversation, account: account, team: team, status: :resolved)
      .update_columns(assignee_id: agent.id, created_at: now - 2.days, started_at: now - 2.days, opened_at: now - 2.days, closed_at: now - 1.day)
  end
  # rubocop:enable Rails/SkipsModelValidations

  describe '#summary' do
    it 'returns the live queue and the averages of the stages finished today' do
      expect(builder.summary).to eq(
        waiting: 2,
        longest_wait: 30.minutes.to_i,
        in_service: 1,
        awaiting_first_reply: 1,
        resolved: 1,
        average_wait: 3.minutes.to_i,
        average_first_reply: 1.minute.to_i,
        average_handling: 20.minutes.to_i,
        average_bot_time: 5.minutes.to_i
      )
    end

    it 'returns no averages when nothing finished today' do
      Conversation.where(account: account).update_all(opened_at: nil, human_first_reply_at: nil, closed_at: nil, status: :open) # rubocop:disable Rails/SkipsModelValidations

      expect(builder.summary).to include(average_wait: nil, average_first_reply: nil, average_handling: nil, resolved: 0)
    end

    context 'when filtered by team' do
      let(:team_id) { other_team.id }

      it 'only counts the conversations of that team' do
        expect(builder.summary).to include(waiting: 1, longest_wait: 10.minutes.to_i, in_service: 0, resolved: 0, average_bot_time: nil)
      end
    end
  end

  describe '#by_team' do
    it 'returns the metrics of each team' do
      metrics = builder.by_team.index_by { |team_metrics| team_metrics[:team_id] }

      expect(metrics[team.id]).to include(waiting: 1, in_service: 1, resolved: 1, average_wait: 3.minutes.to_i)
      expect(metrics[other_team.id]).to include(waiting: 1, in_service: 0, resolved: 0)
    end
  end

  describe '#by_agent' do
    it 'returns the metrics of each assigned agent' do
      expect(builder.by_agent).to contain_exactly(
        include(assignee_id: agent.id, in_service: 1, awaiting_first_reply: 1, resolved: 1, average_handling: 20.minutes.to_i)
      )
    end
  end
end
