require 'rails_helper'

RSpec.describe Alma::Indexer do
  describe "#full_reindex!" do
    it "gets the latest full dump tar files, unzips it, and indexes all the contained files" do
      event = FactoryBot.create(:full_dump_event)
      solr_url = ENV["SOLR_URL"] || "http://#{ENV['lando_marc_liberation_test_solr_conn_host']}:#{ENV['lando_marc_liberation_test_solr_conn_port']}/solr/marc-liberation-core-test"
      stub_request(:get, "http://www.example.com/dump_files/#{event.dump.dump_files[0].id}")
        .to_return(status: 200, body: file_fixture("alma/full_dump/1.xml.tar.gz").read, headers: {})
      stub_request(:get, "http://www.example.com/dump_files/#{event.dump.dump_files[1].id}")
        .to_return(status: 200, body: file_fixture("alma/full_dump/2.xml.tar.gz").read, headers: {})
      solr = RSolr.connect(url: solr_url)
      solr.delete_by_query("*:*")

      indexer = described_class.new(solr_url: solr_url)
      indexer.full_reindex!

      solr.commit
      response = solr.get("select", params: { q: "*:*" })
      # There's one record in 1.xml, and one record in 2.xml
      expect(response['response']['numFound']).to eq 2
    end
    it "works even if there's no XML extension" do
      event = FactoryBot.create(:full_dump_event)
      solr_url = ENV["SOLR_URL"] || "http://#{ENV['lando_marc_liberation_test_solr_conn_host']}:#{ENV['lando_marc_liberation_test_solr_conn_port']}/solr/marc-liberation-core-test"
      stub_request(:get, "http://www.example.com/dump_files/#{event.dump.dump_files[0].id}")
        .to_return(status: 200, body: file_fixture("alma/full_dump/1.tar.gz").read, headers: {})
      stub_request(:get, "http://www.example.com/dump_files/#{event.dump.dump_files[1].id}")
        .to_return(status: 200, body: file_fixture("alma/full_dump/2.tar.gz").read, headers: {})
      solr = RSolr.connect(url: solr_url)
      solr.delete_by_query("*:*")

      indexer = described_class.new(solr_url: solr_url)
      indexer.full_reindex!

      solr.commit
      response = solr.get("select", params: { q: "*:*" })
      # There's one record in 1.xml, and one record in 2.xml
      expect(response['response']['numFound']).to eq 2
    end
  end

  describe "#index_file" do
    it "indexes a single uncompressed MARC XML file" do
      solr_url = ENV["SOLR_URL"] || "http://#{ENV['lando_marc_liberation_test_solr_conn_host']}:#{ENV['lando_marc_liberation_test_solr_conn_port']}/solr/marc-liberation-core-test"
      solr = RSolr.connect(url: solr_url)
      solr.delete_by_query("*:*")

      indexer = described_class.new(solr_url: solr_url)
      file_name = file_fixture("alma/full_dump/2.xml")
      indexer.index_file(file_name)

      solr.commit
      response = solr.get("select", params: { q: "*:*" })
      # There's only one record in 2.xml
      expect(response['response']['numFound']).to eq 1
    end
  end
end
