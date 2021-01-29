require 'rails_helper'

RSpec.describe DeleteEventsJob, type: :job do
  describe "#perform" do
    let(:copy_path) { File.join('tmp', 'delete_files_job') }
    after { FileUtils.rmtree(copy_path) }

    context "for full dump events with start date older than 6 months" do
      it "deletes full dump Events, their Dumps, DumpFiles, and files on disk" do
        old_event = FactoryBot.create(:full_dump_event).tap do |e|
          tmp_dump_files(e)
          e.start = Time.zone.now - 6.months
          e.save
        end
        new_event = FactoryBot.create(:full_dump_event).tap { |e| tmp_dump_files(e) }
        # doesn't delete old incremental events
        incremental_event = FactoryBot.create(:incremental_dump_event).tap do |e|
          tmp_dump_files(e)
          e.start = Time.zone.now - 6.months
          e.save
        end

        described_class.perform_now(dump_type: 'ALL_RECORDS', older_than: 6.months.ago)

        expect(Event.all.to_a.map(&:id)).to contain_exactly(new_event.id, incremental_event.id)
        expect(Dump.all.to_a.map(&:id)).to contain_exactly(new_event.dump.id, incremental_event.dump.id)
        expect(DumpFile.all.to_a.map(&:id)).to contain_exactly(*new_event.dump.dump_files.map(&:id) + incremental_event.dump.dump_files.map(&:id))
        expect(Dir.empty?(File.join(copy_path, old_event.id.to_s))).to be true
        expect(Dir.empty?(File.join(copy_path, new_event.id.to_s))).to be false
        expect(Dir.empty?(File.join(copy_path, incremental_event.id.to_s))).to be false
      end
    end

    context "for incremental dump events with start date older than 2 months" do
      it "deletes incremental dump Events, their Dumps, DumpFiles, and files on disk" do
        old_event = FactoryBot.create(:incremental_dump_event).tap do |e|
          tmp_dump_files(e)
          e.start = Time.zone.now - 2.months
          e.save
        end
        new_event = FactoryBot.create(:incremental_dump_event).tap { |e| tmp_dump_files(e) }
        # doesn't delete old full events
        full_event = FactoryBot.create(:full_dump_event).tap do |e|
          tmp_dump_files(e)
          e.start = Time.zone.now - 6.months
          e.save
        end

        described_class.perform_now(dump_type: 'CHANGED_RECORDS', older_than: 2.months.ago)

        expect(Event.all.to_a.map(&:id)).to contain_exactly(new_event.id, full_event.id)
        expect(Dump.all.to_a.map(&:id)).to contain_exactly(new_event.dump.id, full_event.dump.id)
        expect(DumpFile.all.to_a.map(&:id)).to contain_exactly(*(new_event.dump.dump_files.map(&:id) + full_event.dump.dump_files.map(&:id)))
        expect(Dir.empty?(File.join(copy_path, old_event.id.to_s))).to be true
        expect(Dir.empty?(File.join(copy_path, new_event.id.to_s))).to be false
        expect(Dir.empty?(File.join(copy_path, full_event.id.to_s))).to be false
      end
    end
  end
end

# copy the files somewhere and update their paths. We want to make
# sure they get deleted, but not actually delete them from their fixtures
# location
def tmp_dump_files(e)
  e.dump.dump_files.each do |df|
    new_dir = File.join(copy_path, e.id.to_s)
    FileUtils.mkdir_p(new_dir)
    FileUtils.copy(Rails.root.join(df.path), new_dir)
    df.path = File.join(new_dir, File.basename(df.path))
    df.save
  end
end
