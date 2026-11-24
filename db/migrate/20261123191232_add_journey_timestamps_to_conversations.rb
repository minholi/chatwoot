class AddJourneyTimestampsToConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :conversations, :started_at, :datetime
    add_column :conversations, :opened_at, :datetime
    add_column :conversations, :human_first_reply_at, :datetime
    add_column :conversations, :closed_at, :datetime
  end
end
