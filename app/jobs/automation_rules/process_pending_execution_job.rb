class AutomationRules::ProcessPendingExecutionJob < ApplicationJob
  queue_as :medium

  discard_on ActiveJob::DeserializationError

  def perform(pending_execution)
    # Account flag off pauses (not skips): leave the row pending so re-enabling resumes it.
    return unless pending_execution.account.feature_enabled?('delayed_automations')
    # Atomic claim: a duplicate enqueue (overlapping sweep or stale reclaim) loses here and returns.
    return unless pending_execution.claim!

    skip_reason = skip_reason_for(pending_execution)
    return pending_execution.update!(status: :skipped, skip_reason: skip_reason) if skip_reason
    return defer_outside_execution_window(pending_execution) unless within_execution_window?(pending_execution)

    execute(pending_execution)
  rescue StandardError => e
    # Row stays `processing`; the next sweep reclaims and retries it once the lock goes stale.
    ChatwootExceptionTracker.new(e, account: pending_execution.account).capture_exception
  end

  private

  def skip_reason_for(pending_execution)
    return 'expired' if pending_execution.due_at < AutomationRulePendingExecution::DUE_WINDOW.ago

    structural_skip_reason(pending_execution) || behavioral_skip_reason(pending_execution)
  end

  def structural_skip_reason(pending_execution)
    rule = pending_execution.automation_rule
    return 'rule_inactive' if rule.nil? || !rule.active?
    return 'conversation_gone' if pending_execution.conversation.nil?

    nil
  end

  def behavioral_skip_reason(pending_execution)
    return 'episode_moved' unless pending_execution.episode_current?
    return 'conditions_changed' unless conditions_still_match?(pending_execution)

    nil
  end

  def conditions_still_match?(pending_execution)
    AutomationRules::ConditionsFilterService.new(
      pending_execution.automation_rule,
      pending_execution.conversation,
      { message: pending_execution.message }
    ).perform.present?
  end

  def within_execution_window?(pending_execution)
    pending_execution.automation_rule.within_execution_window?(pending_execution.conversation.inbox.timezone)
  end

  # Outside the allowed window the row stays pending and is re-armed for the next opening, so the
  # actions run during the configured hours instead of being dropped for the episode.
  def defer_outside_execution_window(pending_execution)
    rule = pending_execution.automation_rule
    pending_execution.update!(
      status: :pending,
      due_at: rule.next_execution_window_start(pending_execution.conversation.inbox.timezone)
    )
  end

  # Marked before the actions run: a row that dies here stays `executing`, which no sweep reclaims,
  # so a message/email/webhook is never sent twice. Everything up to this point is still retryable.
  def execute(pending_execution)
    pending_execution.update!(status: :executing)
    AutomationRules::ActionService.new(
      pending_execution.automation_rule,
      pending_execution.account,
      pending_execution.conversation
    ).perform
    pending_execution.update!(status: :executed)
  end
end
