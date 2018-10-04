require 'rails_helper'

describe Dump do
  subject(:dump) { described_class.new }
  let(:mock_time) { Time.zone.at(1) }

  before do
    allow(Time).to receive(:now).at_least(:once).and_return(mock_time)
  end

  describe '.dump_bib_ids' do
    subject(:dump) { described_class.dump_bib_ids }

    before do
      allow(VoyagerHelpers::SyncFu).to receive(:bib_ids_to_file)
      dump
    end

    it 'constructs an Event and exports the voyager IDs to a file' do
      event = Event.first
      expect(event).not_to be_nil

      dump_file = DumpFile.find_by(dump: dump)
      expect(dump_file).not_to be_nil

      dump_type = dump.dump_type
      expect(dump_type).not_to be_nil

      expect(dump_type.label).to eq 'All Bib IDs'
      expect(dump_type.constant).to eq 'BIB_IDS'
      expect(VoyagerHelpers::SyncFu).to have_received(:bib_ids_to_file).with('data/1')
      expect(dump.dump_files).to eq([dump_file])
      expect(dump.updated_at).to eq(Time.now)
    end
  end

  describe '.dump_holding_ids' do
    subject(:dump) { described_class.dump_holding_ids }

    before do
      allow(VoyagerHelpers::SyncFu).to receive(:holding_ids_to_file)
      dump
    end

    it 'constructs an Event and exports the voyager IDs to a file' do
      event = Event.first
      expect(event).not_to be_nil

      dump_file = DumpFile.find_by(dump: dump)
      expect(dump_file).not_to be_nil

      dump_type = dump.dump_type
      expect(dump_type).not_to be_nil

      expect(dump_type.label).to eq 'All Holding IDs'
      expect(dump_type.constant).to eq 'HOLDING_IDS'
      expect(VoyagerHelpers::SyncFu).to have_received(:holding_ids_to_file).with('data/1')
      expect(dump.dump_files).to eq([dump_file])
      expect(dump.updated_at).to eq(Time.now)
    end
  end

  describe '.dump_recap_records' do
    subject(:dump) { described_class.dump_recap_records }

    let(:yesterday) { Time.now - 1.day }

    before do
      allow(VoyagerHelpers::SyncFu).to receive(:recap_barcodes_since)
      dump
    end

    it 'constructs an Event and exports the voyager IDs to a file' do
      event = Event.first
      expect(event).not_to be_nil

      dump_type = dump.dump_type
      expect(dump_type).not_to be_nil

      expect(dump_type.label).to eq 'Updated Princeton ReCAP Records'
      expect(dump_type.constant).to eq 'PRINCETON_RECAP'
      expect(VoyagerHelpers::SyncFu).to have_received(:recap_barcodes_since).with(yesterday)
      expect(dump.updated_at).to eq(Time.now)
    end
  end

  describe '.diff_since_last' do
    let(:change_report) { instance_double(VoyagerHelpers::ChangeReport) }

    before do
      bib_ids_dump_type = DumpType.find_by(constant: 'BIB_IDS')
      holding_ids_dump_type = DumpType.find_by(constant: 'HOLDING_IDS')

      event1 = Event.create(start: Time.now, finish: Time.now + 1, success: true)
      event2 = Event.create(start: Time.now + 1, finish: Time.now + 2, success: true)
      dump1 = Dump.create(dump_type: bib_ids_dump_type, event: event1)
      dump2 = Dump.create(dump_type: bib_ids_dump_type, event: event2)
      dump_file_type = DumpFileType.find_by(constant: 'BIB_IDS')
      dump_file1 = DumpFile.create(dump: dump1, dump_file_type: dump_file_type)
      dump_file2 = DumpFile.create(dump: dump2, dump_file_type: dump_file_type)

      event3 = Event.create(start: Time.now, finish: Time.now + 1, success: true)
      event4 = Event.create(start: Time.now + 1, finish: Time.now + 2, success: true)
      dump3 = Dump.create(dump_type: holding_ids_dump_type, event: event3)
      dump4 = Dump.create(dump_type: holding_ids_dump_type, event: event4)
      dump_file_type = DumpFileType.find_by(constant: 'HOLDING_IDS')
      dump_file1 = DumpFile.create(dump: dump3, dump_file_type: dump_file_type)
      dump_file2 = DumpFile.create(dump: dump4, dump_file_type: dump_file_type)

      allow(change_report).to receive(:merge_in_holding_report)
      allow(change_report).to receive(:created).and_return(['test-created-id'])
      allow(change_report).to receive(:updated).and_return(['test-updated-id'])
      allow(change_report).to receive(:deleted).and_return(['test-deleted-id'])
      allow(VoyagerHelpers::SyncFu).to receive(:compare_id_dumps).and_return(change_report)

      described_class.diff_since_last
    end

    it 'compares the Voyager record exports' do
      dump_type = DumpType.find_by(constant: 'CHANGED_RECORDS')
      dump = Dump.find_by(dump_type: dump_type)
      expect(dump).not_to be_nil

      expect(dump.create_ids).to eq(['test-created-id'])
      expect(dump.update_ids).to eq(['test-updated-id'])
      expect(dump.delete_ids).to eq(['test-deleted-id'])
    end
  end

  describe '#dump_updated_records' do
    let(:updated_ids) do
      ["ea", "eb", "ec", "ed", "ei", "em", "es", "fa", "fb", "fc", "fd", "fi", "fm", "fs"]
    end
    let(:dump_file_type) { DumpFileType.create(constant: 'UPDATED_RECORDS') }
    let(:priority) { 'default' }

    before do
      allow(BibDumpJob).to receive(:set).and_return(BibDumpJob)
      allow(BibDumpJob).to receive(:perform_later)
      dump_file_type

      dump.dump_updated_records
    end

    it 'exports updated records using the BibDumpJob and sets the last updated time' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(updated_ids, dump_file.id)
      expect(dump_file.updated_at).to eq Time.now
    end
  end

  describe '#dump_created_records' do
    let(:created_ids) do
      ["ea", "eb", "ec", "ed", "ei", "em", "es", "fa", "fb", "fc", "fd", "fi", "fm", "fs"]
    end
    let(:dump_file_type) { DumpFileType.create(constant: 'NEW_RECORDS') }
    let(:priority) { 'default' }

    before do
      allow(BibDumpJob).to receive(:set).and_return(BibDumpJob)
      allow(BibDumpJob).to receive(:perform_later)
      dump_file_type

      dump.dump_created_records
    end

    it 'exports created records using the BibDumpJob and sets the last updated time' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(created_ids, dump_file.id)
      expect(dump_file.updated_at).to eq Time.now
    end
  end

  describe '#dump_bib_records' do
    let(:bib_ids) do
      ['test-bib-id']
    end
    let(:dump_file_type) { DumpFileType.create(constant: 'BIB_RECORDS') }
    let(:priority) { 'default' }

    before do
      allow(BibDumpJob).to receive(:set).and_return(BibDumpJob)
      allow(BibDumpJob).to receive(:perform_later)
      dump_file_type

      dump.dump_bib_records(bib_ids)
    end

    it 'exports voyager records using the BibDumpJob and sets the last updated time' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(bib_ids, dump_file.id)
      expect(dump_file.updated_at).to eq Time.now
    end
  end

  describe '#dump_updated_recap_records' do
    let(:updated_barcodes) do
      ['test-recap-barcode']
    end
    let(:dump_file_type) { DumpFileType.create(constant: 'RECAP_RECORDS') }

    before do
      allow(RecapDumpJob).to receive(:perform_later)
      dump_file_type

      dump.dump_updated_recap_records(updated_barcodes)
    end

    it 'exports updated records from ReCAP using the RecapDumpJob and sets the last updated time' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(RecapDumpJob).to have_received(:perform_later).with(updated_barcodes, dump_file.id)
      expect(dump_file.updated_at).to eq Time.now
    end
  end
end
