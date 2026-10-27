# == Schema Information
#
# Table name: csat_survey_responses
#
#  id                         :bigint           not null, primary key
#  csat_review_notes          :text
#  feedback_message           :text
#  rating                     :integer          not null
#  review_notes_updated_at    :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  assigned_agent_id          :bigint
#  contact_id                 :bigint           not null
#  conversation_id            :bigint           not null
#  message_id                 :bigint           not null
#  review_notes_updated_by_id :bigint
#
# Indexes
#
#  index_csat_survey_responses_on_account_id                  (account_id)
#  index_csat_survey_responses_on_assigned_agent_id           (assigned_agent_id)
#  index_csat_survey_responses_on_contact_id                  (contact_id)
#  index_csat_survey_responses_on_conversation_id             (conversation_id)
#  index_csat_survey_responses_on_message_id                  (message_id) UNIQUE
#  index_csat_survey_responses_on_review_notes_updated_by_id  (review_notes_updated_by_id)
#
class CsatSurveyResponse < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :message
  belongs_to :assigned_agent, class_name: 'User', optional: true, inverse_of: :csat_survey_responses
  belongs_to :review_notes_updated_by, class_name: 'User', optional: true

  validates :rating, presence: true, inclusion: { in: [1, 2, 3, 4, 5] }
  validates :account_id, presence: true
  validates :contact_id, presence: true
  validates :conversation_id, presence: true

  after_create_commit :dispatch_create_event
  after_update_commit :dispatch_update_event

  scope :filter_by_created_at, ->(range) { where(created_at: range) if range.present? }
  scope :filter_by_assigned_agent_id, ->(user_ids) { where(assigned_agent_id: user_ids) if user_ids.present? }
  scope :filter_by_inbox_id, ->(inbox_id) { joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id.present? }
  scope :filter_by_team_id, ->(team_id) { joins(:conversation).where(conversations: { team_id: team_id }) if team_id.present? }
  # filter by rating value
  scope :filter_by_rating, ->(rating) { where(rating: rating) if rating.present? }

  def webhook_data
    {
      account: account.webhook_data,
      id: id,
      rating: rating,
      feedback_message: feedback_message,
      csat_review_notes: csat_review_notes,
      review_notes_updated_at: review_notes_updated_at&.to_i,
      message_id: message_id,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      conversation: conversation.webhook_data,
      contact: contact.webhook_data,
      inbox: conversation.inbox.webhook_data,
      assigned_agent: assigned_agent&.webhook_data
    }
  end

  private

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(CSAT_SURVEY_RESPONSE_CREATED, Time.zone.now, csat_survey_response: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(CSAT_SURVEY_RESPONSE_UPDATED, Time.zone.now,
                                            csat_survey_response: self, changed_attributes: previous_changes)
  end
end
