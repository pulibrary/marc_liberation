require 'rails_helper'

RSpec.describe AlmaFullDumpTransferJob, type: :job do
  let(:job_id) { "1436402400006421" }
  let(:name) do
    Net::SFTP::Protocol::V01::Name.new(
      "fulldump_1436402400006421_20201218_211210[050]_new_1.tar.gz",
      "-rw-rw-r--. 1 alma alma  49546443 Dec 18 16:50 fulldump_1436402400006421_20201218_211210[050]_new_1.tar.gz",
      attrs
    )
  end
  let(:remote_path1) { "/alma/publishing/fulldump_1436402400006421_20201218_211210[050]_new_1.tar.gz" }
  let(:remote_path2) { "/alma/publishing/fulldump_1436402400006421_20201218_211210[050]_new_2.tar.gz" }
  let(:local_path1) { File.join(MARC_LIBERATION_CONFIG['data_dir'], "fulldump_1436402400006421_20201218_211210[050]_new_1.tar.gz") }
  let(:local_path2) { File.join(MARC_LIBERATION_CONFIG['data_dir'], "fulldump_1436402400006421_20201218_211210[050]_new_2.tar.gz") }
  let(:attrs) { Net::SFTP::Protocol::V01::Attributes.new({}) }
  let(:name2) do
    Net::SFTP::Protocol::V01::Name.new(
      "fulldump_1436402400006421_20201218_211210[050]_new_2.tar.gz",
      "-rw-rw-r--. 1 alma alma   4916786 Dec 18 16:50 fulldump_1436402400006421_20201218_211210[050]_new_2.tar.gz",
      attrs
    )
  end
  let(:name3) do
    Net::SFTP::Protocol::V01::Name.new(
      "fulldump_1434819190006421_2020121520_new_1.xml.tar.gz",
      "-rw-rw-r--. 1 alma alma  49970147 Dec 15 15:55 fulldump_1434819190006421_2020121520_new_1.xml.tar.gz",
      attrs
    )
  end

  before do
    FactoryBot.create(:full_dump_file_type)
  end

  describe 'perform' do
    it 'downloads a file' do
      session_stub = instance_double(Net::SFTP::Session)
      dir_stub = instance_double(Net::SFTP::Operations::Dir)
      download_stub = instance_double(Net::SFTP::Operations::Download)
      allow(Net::SFTP).to receive(:start).and_yield(session_stub)
      allow(session_stub).to receive(:dir).and_return(dir_stub)
      allow(dir_stub).to receive(:entries).and_return([name, name2, name3])
      allow(session_stub).to receive(:download).and_return(download_stub)
      allow(download_stub).to receive(:wait)
      dump = FactoryBot.create(:empty_dump)
      described_class.perform_now(dump: dump, job_id: job_id)
      expect(session_stub).to have_received(:download).once.with(remote_path1, local_path1)
      expect(session_stub).to have_received(:download).once.with(remote_path2, local_path2)
      expect(Dump.all.count).to eq 1
      expect(Dump.first.dump_files.count).to eq 2
      expect(Dump.first.dump_files.map(&:dump_file_type).map(&:constant).uniq).to eq ["BIB_RECORDS"]
      expect(Dump.first.dump_files.first.path).to eq File.join(MARC_LIBERATION_CONFIG['data_dir'], "fulldump_1436402400006421_20201218_211210[050]_new_1.tar.gz")
    end
  end
end
