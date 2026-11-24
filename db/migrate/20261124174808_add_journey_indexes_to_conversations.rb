class AddJourneyIndexesToConversations < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :conversations, [:account_id, :started_at], algorithm: :concurrently
    add_index :conversations, [:account_id, :closed_at], algorithm: :concurrently
  end
end
