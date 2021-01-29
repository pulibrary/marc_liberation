require 'rails_helper'

RSpec.describe LocationDataService, type: :service do
  subject(:service) { described_class.new }

  before do
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/libraries.json")
      )

    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries/arch/locations")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/locations1.json")
      )

    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/libraries/main/locations")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: file_fixture("alma/locations2.json")
      )
  end

  describe "#delete_existing_and_repopulate" do
    before do
      # Setup dummy records to test if existing records are deleted
      test_library = Locations::Library.create(code: 'test', label: 'test')
      Locations::HoldingLocation.new(code: 'test', label: 'test') do |test_location|
        test_location.library = test_library
        test_location.save
      end
    end

    it "deletes exsiting data and populates library and location data from Alma" do
      LocationDataService.delete_existing_and_repopulate
      library_record = Locations::Library.find_by(code: 'main')
      location_record1 = Locations::HoldingLocation.find_by(code: 'main$stacks')
      location_record2 = Locations::HoldingLocation.find_by(code: 'arch$reserves')

      expect(Locations::Library.count).to eq 2
      expect(Locations::HoldingLocation.count).to eq 13
      expect(library_record.label).to eq 'Main Library'
      expect(location_record1.label).to eq 'Main Library - Main Library Stacks'
      expect(location_record1.open).to be true
      expect(location_record2.open).to be false
    end
  end
end
