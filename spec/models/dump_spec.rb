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
