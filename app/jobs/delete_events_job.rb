class DeleteEventsJob < ActiveJob::Base
  def perform(dump_type:, older_than:)
    start = Event.arel_table[:start]
    ids = Event
          .joins(dump: :dump_type)
          .where('dump_types.constant': dump_type)
          .where(start.lt(older_than))
          .map(&:id)

    Event.destroy(ids)
  end
end
