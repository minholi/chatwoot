class AutomationRules::BusinessHoursService
  DAYS_IN_WEEK = 7

  def initialize(inbox:, at: Time.current)
    @inbox = inbox
    @at = at
  end

  def applicable?
    @inbox.working_hours_enabled? && working_hours_by_day.values.any? { |working_hour| !working_hour.closed_all_day? }
  end

  def open?(time = @at)
    return true unless applicable?

    working_hour = working_hours_by_day[time.in_time_zone(timezone).wday]
    return false if working_hour.nil? || working_hour.closed_all_day?
    return true if working_hour.open_all_day?

    time.between?(time_in_zone(time, working_hour.open_hour, working_hour.open_minutes),
                  time_in_zone(time, working_hour.close_hour, working_hour.close_minutes))
  end

  def next_opening
    return nil unless applicable?
    return nil if open?

    local_date = @at.in_time_zone(timezone).to_date
    # A weekly schedule always has an opening within the next seven days, so the extra day covers the
    # case where today is the only open day and its window has already closed.
    (DAYS_IN_WEEK + 1).times do |offset|
      date = local_date + offset
      working_hour = working_hours_by_day[date.wday]
      next if working_hour.nil? || working_hour.closed_all_day?

      opening = opening_time(date, working_hour)
      return opening if opening > @at
    end

    nil
  end

  private

  def working_hours_by_day
    @working_hours_by_day ||= @inbox.working_hours.index_by(&:day_of_week)
  end

  def timezone
    @inbox.timezone.presence || 'UTC'
  end

  def opening_time(date, working_hour)
    return date.in_time_zone(timezone).beginning_of_day if working_hour.open_all_day?

    date.in_time_zone(timezone).change(hour: working_hour.open_hour, min: working_hour.open_minutes, sec: 0)
  end

  def time_in_zone(time, hour, minutes)
    time.in_time_zone(timezone).change(hour: hour, min: minutes)
  end
end
