require 'rails_helper'

RSpec.describe AutomationRules::BusinessHoursService do
  let(:account) { create(:account) }
  # The inbox factory creates the default schedule: Mon-Fri 9:00-17:00, Sat-Sun closed.
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: true, timezone: 'UTC') }

  describe '#applicable?' do
    it 'is false when working hours are disabled' do
      inbox.update!(working_hours_enabled: false)

      expect(described_class.new(inbox: inbox).applicable?).to be false
    end

    it 'is false when every day is closed' do
      inbox.working_hours.find_each { |working_hour| working_hour.update!(closed_all_day: true) }

      expect(described_class.new(inbox: inbox).applicable?).to be false
    end

    it 'is true when working hours are enabled and at least one day is open' do
      expect(described_class.new(inbox: inbox).applicable?).to be true
    end
  end

  describe '#open?' do
    it 'is open inside the daily window' do
      monday_10am = Time.zone.parse('2024-01-15 10:00:00')

      expect(described_class.new(inbox: inbox, at: monday_10am).open?).to be true
    end

    it 'is open on both boundaries, matching WorkingHour#open_at?' do
      monday_9am = Time.zone.parse('2024-01-15 09:00:00')
      monday_5pm = Time.zone.parse('2024-01-15 17:00:00')

      expect(described_class.new(inbox: inbox, at: monday_9am).open?).to be true
      expect(described_class.new(inbox: inbox, at: monday_5pm).open?).to be true
    end

    it 'is closed outside the daily window' do
      monday_7am = Time.zone.parse('2024-01-15 07:00:00')
      monday_6pm = Time.zone.parse('2024-01-15 18:00:00')

      expect(described_class.new(inbox: inbox, at: monday_7am).open?).to be false
      expect(described_class.new(inbox: inbox, at: monday_6pm).open?).to be false
    end

    it 'is closed on a closed day' do
      saturday_10am = Time.zone.parse('2024-01-20 10:00:00')

      expect(described_class.new(inbox: inbox, at: saturday_10am).open?).to be false
    end

    it 'is open all day when the day is marked open_all_day' do
      inbox.working_hours.find_by(day_of_week: 6).update!(open_all_day: true, closed_all_day: false)
      saturday_10am = Time.zone.parse('2024-01-20 10:00:00')

      expect(described_class.new(inbox: inbox, at: saturday_10am).open?).to be true
    end

    it 'is closed when the day has no working hour row' do
      inbox.working_hours.find_by(day_of_week: 1).destroy!
      monday_10am = Time.zone.parse('2024-01-15 10:00:00')

      expect(described_class.new(inbox: inbox, at: monday_10am).open?).to be false
    end

    it 'is a no-op (open) when the schedule does not apply' do
      inbox.update!(working_hours_enabled: false)
      saturday_10am = Time.zone.parse('2024-01-20 10:00:00')

      expect(described_class.new(inbox: inbox, at: saturday_10am).open?).to be true
    end

    it 'agrees with Inbox#working_now? while the inbox is open' do
      travel_to(Time.zone.parse('2024-01-15 10:00:00')) do
        expect(described_class.new(inbox: inbox, at: Time.current).open?).to eq(inbox.working_now?)
      end
    end
  end

  describe '#next_opening' do
    it 'returns the opening later the same day when before the window' do
      monday_7am = Time.zone.parse('2024-01-15 07:00:00')

      expect(described_class.new(inbox: inbox, at: monday_7am).next_opening).to eq(Time.zone.parse('2024-01-15 09:00:00'))
    end

    it 'returns the next day opening when after the window' do
      monday_6pm = Time.zone.parse('2024-01-15 18:00:00')

      expect(described_class.new(inbox: inbox, at: monday_6pm).next_opening).to eq(Time.zone.parse('2024-01-16 09:00:00'))
    end

    it 'wraps from Saturday over the closed weekend to Monday' do
      saturday_10am = Time.zone.parse('2024-01-20 10:00:00')

      expect(described_class.new(inbox: inbox, at: saturday_10am).next_opening).to eq(Time.zone.parse('2024-01-22 09:00:00'))
    end

    it 'wraps from Friday after close over the closed weekend to Monday' do
      friday_6pm = Time.zone.parse('2024-01-19 18:00:00')

      expect(described_class.new(inbox: inbox, at: friday_6pm).next_opening).to eq(Time.zone.parse('2024-01-22 09:00:00'))
    end

    it 'wraps to the same weekday next week when that is the only open day' do
      inbox.working_hours.where.not(day_of_week: 1).find_each { |working_hour| working_hour.update!(closed_all_day: true) }
      monday_6pm = Time.zone.parse('2024-01-15 18:00:00')

      expect(described_class.new(inbox: inbox, at: monday_6pm).next_opening).to eq(Time.zone.parse('2024-01-22 09:00:00'))
    end

    it 'returns midnight on an open_all_day day' do
      inbox.working_hours.find_by(day_of_week: 6).update!(open_all_day: true, closed_all_day: false)
      friday_6pm = Time.zone.parse('2024-01-19 18:00:00')

      expect(described_class.new(inbox: inbox, at: friday_6pm).next_opening).to eq(Time.zone.parse('2024-01-20 00:00:00'))
    end

    it 'returns nil while the inbox is already open' do
      monday_10am = Time.zone.parse('2024-01-15 10:00:00')

      expect(described_class.new(inbox: inbox, at: monday_10am).next_opening).to be_nil
    end

    it 'returns nil when the schedule does not apply' do
      inbox.update!(working_hours_enabled: false)
      saturday_10am = Time.zone.parse('2024-01-20 10:00:00')

      expect(described_class.new(inbox: inbox, at: saturday_10am).next_opening).to be_nil
    end

    it 'returns nil when no day in the next week is open' do
      inbox.working_hours.find_each { |working_hour| working_hour.update!(closed_all_day: true) }
      monday_10am = Time.zone.parse('2024-01-15 10:00:00')

      expect(described_class.new(inbox: inbox, at: monday_10am).next_opening).to be_nil
    end

    it 'evaluates the schedule in the inbox timezone' do
      inbox.update!(timezone: 'America/Sao_Paulo')
      # Monday 07:00 UTC is Monday 04:00 in Sao Paulo, before the 9:00 opening.
      monday_7am_utc = Time.zone.parse('2024-01-15 07:00:00')

      expect(described_class.new(inbox: inbox, at: monday_7am_utc).next_opening).to eq(Time.zone.parse('2024-01-15 12:00:00 UTC'))
    end

    it 'is closed in a non-UTC timezone while UTC is inside the window' do
      inbox.update!(timezone: 'America/Sao_Paulo')
      monday_2pm_utc = Time.zone.parse('2024-01-15 14:00:00')
      monday_10pm_utc = Time.zone.parse('2024-01-15 22:00:00')

      expect(described_class.new(inbox: inbox, at: monday_2pm_utc).open?).to be true
      expect(described_class.new(inbox: inbox, at: monday_10pm_utc).open?).to be false
    end
  end
end
