# Indicadores ao vivo da jornada de atendimento humano, no padrão do monitoramento que a operação usava na Blip:
#   agora    - em espera na fila, maior espera, em atendimento, aguardando 1ª resposta
#   no dia   - finalizados e médias (TME, 1ª resposta, TMA, tempo no bot) dos marcos ocorridos desde `since`
# Usa os marcos gravados em conversations por ConversationJourneyHandler. Durações em segundos.
class V2::Reports::JourneyMetricsBuilder
  COLUMNS = %i[team_id assignee_id status created_at started_at opened_at human_first_reply_at closed_at].freeze
  # Conversa que nasce direto na fila humana tem started_at igual a created_at: não passou pelo bot.
  MIN_BOT_SECONDS = 1

  pattr_initialize [:account!, :since!, :team_id]

  def summary
    metrics_for(rows)
  end

  def by_team
    grouped_metrics(:team_id)
  end

  def by_agent
    grouped_metrics(:assignee_id)
  end

  private

  def rows
    @rows ||= begin
      scope = account.conversations.in_journey_since(since)
      scope = scope.where(team_id: team_id) if team_id
      scope.pluck(*COLUMNS).map { |values| COLUMNS.zip(values).to_h }
    end
  end

  def grouped_metrics(key)
    rows.group_by { |row| row[key] }.filter_map do |id, group_rows|
      metrics_for(group_rows).merge(key => id) if id
    end
  end

  def metrics_for(group_rows)
    live_metrics(group_rows).merge(day_metrics(group_rows))
  end

  def live_metrics(group_rows)
    waiting = group_rows.select { |row| waiting?(row) }
    in_service = group_rows.select { |row| in_service?(row) }

    {
      waiting: waiting.size,
      longest_wait: waiting.map { |row| (now - row[:started_at]).round }.max,
      in_service: in_service.size,
      awaiting_first_reply: in_service.count { |row| row[:human_first_reply_at].nil? }
    }
  end

  def day_metrics(group_rows)
    {
      resolved: group_rows.count { |row| in_period?(row[:closed_at]) },
      average_wait: average_duration(group_rows, :started_at, :opened_at),
      average_first_reply: average_duration(group_rows, :opened_at, :human_first_reply_at),
      average_handling: average_duration(group_rows, :opened_at, :closed_at),
      average_bot_time: average_duration(group_rows.select { |row| bot_handled?(row) }, :created_at, :started_at)
    }
  end

  def waiting?(row)
    row[:status] == 'open' && row[:started_at].present? && row[:opened_at].nil?
  end

  def in_service?(row)
    row[:status] == 'open' && row[:opened_at].present?
  end

  def bot_handled?(row)
    row[:started_at].present? && row[:started_at] - row[:created_at] >= MIN_BOT_SECONDS
  end

  def in_period?(time)
    time.present? && time >= since
  end

  # Média das etapas que terminaram no período.
  def average_duration(group_rows, from, to)
    durations = group_rows.filter_map do |row|
      row[to] - row[from] if row[from].present? && in_period?(row[to])
    end
    return if durations.empty?

    (durations.sum / durations.size).round
  end

  def now
    @now ||= Time.current
  end
end
