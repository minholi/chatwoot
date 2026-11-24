# Marcos da jornada de atendimento humano do ciclo atual da conversa:
#   started_at           - entrada na fila humana (status passa a open vindo do bot, de uma resolução ou já na criação)
#   opened_at            - primeira atribuição a um agente humano no ciclo (igual a started_at se já havia agente)
#   human_first_reply_at - primeira resposta pública de agente humano depois de started_at
#   closed_at            - conversa marcada como resolvida
# Voltar para o bot (pending) ou reabrir uma conversa resolvida inicia um novo ciclo e zera os marcos.
# Sair de snoozed não é um novo ciclo.
module ConversationJourneyHandler
  extend ActiveSupport::Concern

  JOURNEY_KEYS = %w[started_at opened_at human_first_reply_at closed_at].freeze

  included do
    # Conversas que pesam nos indicadores ao vivo: abertas já na jornada humana, ou que entraram na fila ou foram
    # resolvidas desde `since`. Uma conversa atribuída ou respondida no período ou ainda está aberta ou foi resolvida nele.
    scope :in_journey_since, lambda { |since|
      where(status: :open).where.not(started_at: nil)
                          .or(where(started_at: since..))
                          .or(where(closed_at: since..))
    }
  end

  def record_human_first_reply(message)
    return if started_at.blank? || human_first_reply_at.present?

    # update_columns: sem callbacks nem CONVERSATION_UPDATED, para não reavaliar regras de automação "conversa atualizada".
    # O valor chega ao painel no evento que a própria resposta dispara logo depois (waiting_since/first_reply).
    update_columns(human_first_reply_at: [message.created_at, started_at].max, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def track_journey
    now = new_record? ? created_at : Time.current
    track_journey_status(now) if new_record? || status_changed?
    self.opened_at = now if human_assigned_in_queue?
  end

  def human_assigned_in_queue?
    assignee_id_changed? && assignee_id.present? && open? && started_at.present? && opened_at.blank?
  end

  def track_journey_status(now)
    case status
    when 'open'
      start_journey_cycle(now) unless status_was == 'snoozed' && !new_record?
    when 'pending'
      reset_journey
    when 'resolved'
      self.closed_at = now
    end
  end

  def start_journey_cycle(now)
    reset_journey
    self.started_at = now
    self.opened_at = now if assignee_id.present?
  end

  def reset_journey
    JOURNEY_KEYS.each { |key| self[key] = nil }
  end
end
