class AddExecutionWindowToAutomationRules < ActiveRecord::Migration[7.1]
  def change
    add_column :automation_rules, :execution_window_start_minutes, :integer
    add_column :automation_rules, :execution_window_end_minutes, :integer
  end
end
