require 'rails_helper'

RSpec.describe Dump, type: :model do
  before(:all) { system 'rake db:seed' }
  after(:all) { DumpFileType.destroy_all }

  let(:partner_recap) { 'PARTNER_RECAP' }
  let(:princeton_recap) { 'PRINCETON_RECAP' }
  let(:princeton_recap_dump_type) { DumpType.find_by(constant: princeton_recap) }
  let(:partner_recap_dump_type) { DumpType.find_by(constant: partner_recap) }
  let(:test_create_time) { '2017-04-29 20:10:29'.to_time }
  let(:event_success) { Event.create(start: '2020-10-20 19:00:15', finish: '2020-10-20 19:00:41', error: nil, success: true, created_at: "2020-10-20 19:00:41", updated_at: "2020-10-20 19:00:41") }
  let(:dump_princeton_recap_success) { Dump.create(event_id: event_success.id, dump_type_id: princeton_recap_dump_type.id, created_at: "2020-10-20 19:00:15", updated_at: "2020-10-20 19:00:41") }

  describe '#last_incremental_update' do
    it 'returns nil when no dump object is there' do
      Dump.destroy_all
      timestamp = Dump.send(:last_incremental_update, partner_recap)
      expect(timestamp).to be_nil
    end

    it 'sets to create time of previous partner recap dump when there' do
      Dump.create(dump_type: partner_recap_dump_type, created_at: test_create_time)
      timestamp = Dump.send(:last_incremental_update, partner_recap)
      expect(timestamp).to eq(test_create_time)
    end
  end

  describe '#incremental_update_timestamp' do
    it 'returns yesterday when no environment variable or dump object is there' do
      ENV['TIMESTAMP'] = nil
      Dump.destroy_all
      timestamp = Dump.send(:incremental_update_timestamp, partner_recap).to_time.strftime("%Y%m%d")
      expect(timestamp).to eq((DateTime.now - 1).to_time.strftime("%Y%m%d"))
    end

    it 'sets to create time of previous partner recap dump when there' do
      Dump.create(dump_type: partner_recap_dump_type, created_at: test_create_time)
      timestamp = Dump.send(:incremental_update_timestamp, partner_recap)
      expect(timestamp).to eq(test_create_time.strftime('%Y-%m-%d %H:%M:%S.%6N %z'))
    end

    it 'sets to environment variable when there' do
      ENV['TIMESTAMP'] = '2017-07-01'
      timestamp = Dump.send(:incremental_update_timestamp, partner_recap).to_time.strftime("%Y%m%d")
      expect(timestamp).to eq(ENV['TIMESTAMP'].to_time.strftime("%Y%m%d"))
    end

    it 'sets to create time of the last created successful Princeton Recap dump if it exists' do
      ENV['TIMESTAMP'] = nil
      allow(described_class).to receive(:last_recap_dump).and_return(dump_princeton_recap_success)
      timestamp = Dump.send(:incremental_update_timestamp, princeton_recap)
      expect(timestamp).to eq dump_princeton_recap_success.created_at.to_time.strftime('%Y-%m-%d %H:%M:%S.%6N %z')
    end
  end
end
