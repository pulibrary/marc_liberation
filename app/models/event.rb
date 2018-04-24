class Event < ActiveRecord::Base
  has_one :dump

  before_destroy do
    self.dump.destroy unless self.dump.nil?
  end

  class << self

    def record
      event = Event.new
      event.start = Time.now.utc
      event.success = true
      yield(event)
    rescue Exception => e
      event.success = false
      event.error = "#{e.class}: #{e.message}"
      STDERR.puts e.message if defined?(Rake)
    ensure
      event.finish = Time.now.utc
      event.save!
      return event
    end

    # Keep 3 most recent full dumps and 8 most recent dumps of each other type
    def delete_old_events
      delete_ids = Dump
        .where(dump_type: DumpType.find_by(constant: 'ALL_RECORDS'))
        .order("id DESC").offset(3).pluck(:event_id)
      delete_ids << Dump
        .where(dump_type: DumpType.find_by(constant: 'CHANGED_RECORDS'))
        .order("id DESC").offset(8).pluck(:event_id)
      delete_ids << Dump
        .where(dump_type: DumpType.find_by(constant: 'HOLDING_IDS'))
        .order("id DESC").offset(8).pluck(:event_id)
      delete_ids << Dump
        .where(dump_type: DumpType.find_by(constant: 'BIB_IDS'))
        .order("id DESC").offset(8).pluck(:event_id)
      delete_ids.flatten!.compact!
      Event.destroy(delete_ids)
    end

  end # class << self

end
