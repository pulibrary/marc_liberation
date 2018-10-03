require 'rails_helper'

describe Dump do
  subject(:dump) { described_class.new }

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

    it 'exports updated records' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(updated_ids, dump_file.id)
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

    it 'exports created records' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(created_ids, dump_file.id)
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

    it 'exports voyager records' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(BibDumpJob).to have_received(:set).with(queue: priority)
      expect(BibDumpJob).to have_received(:perform_later).with(bib_ids, dump_file.id)
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

    it 'exports updated records from ReCAP to a file using RecapDumpJob' do
      dump_file = DumpFile.find_by(dump_file_type: dump_file_type)
      expect(dump_file).to be_a DumpFile
      expect(dump.dump_files).to eq [dump_file]
      expect(RecapDumpJob).to have_received(:perform_later).with(updated_barcodes, dump_file.id)
    end
  end
end
