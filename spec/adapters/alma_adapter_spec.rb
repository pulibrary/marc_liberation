require 'rails_helper'

RSpec.describe AlmaAdapter do
  subject(:adapter) { described_class.new }

  let(:unsuppressed) { "991227850000541" }
  let(:unsuppressed_two) { "991227840000541" }
  let(:unsuppressed_two_loc_two_items) { "99223608406421" }
  let(:unsuppressed_loc_with_two_holdings) { "99229556706421" }
  let(:suppressed) { "99222441306421" }
  let(:holdings_991227840000541) { file_fixture("alma/#{unsuppressed_two}_holdings.xml").read }
  let(:bib_items_po) { "99227515106421" }
  let(:bib_items_po_json) { file_fixture("alma/#{bib_items_po}_po.json") }
  let(:bib_items_list_unsuppressed_json) { file_fixture("alma/bib_items_list_#{unsuppressed}.json") }
  let(:unsuppressed_two_loc_two_items_json) { file_fixture("alma/#{unsuppressed_two_loc_two_items}_two_locations_two_items.json") }
  let(:unsuppressed_loc_with_two_holdings_json) { file_fixture("alma/#{unsuppressed_loc_with_two_holdings}_two_loc_two_holdings_sort_library_asc.json") }

  def stub_alma_ids(ids:, status:, fixture: nil)
    json_body = file_fixture("alma/#{fixture}.json")
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs?expand=p_avail,e_avail,d_avail,requests&mms_id=#{Array.wrap(ids).join(',')}")
      .to_return(status: status, body: json_body)
  end

  before do
    stub_request(:get, "https://ALMA/almaws/v1/bibs/991227850000541/holdings?apikey=TESTME")
      .to_return(status: 200, body: holdings_991227840000541, headers: {
                   'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                   'Content-Type' => 'application/xml;charset=UTF-8',
                   'Accept' => 'application/xml',
                   'User-Agent' => 'Faraday v1.0.1'
                 })
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/#{bib_items_po}/holdings/ALL/items?expand=due_date_policy,due_date&order_by=library&direction=asc&limit=100")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: bib_items_po_json
      )
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/#{unsuppressed}/holdings/ALL/items?expand=due_date_policy,due_date&order_by=library&direction=asc&limit=100")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: bib_items_list_unsuppressed_json
      )
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/#{unsuppressed_two_loc_two_items}/holdings/ALL/items?expand=due_date_policy,due_date&order_by=library&direction=asc&limit=100")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: unsuppressed_two_loc_two_items_json
      )
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/#{unsuppressed_loc_with_two_holdings}/holdings/ALL/items?expand=due_date_policy,due_date&order_by=library&direction=asc&limit=100")
      .with(
        headers: {
          'Accept' => 'application/json',
          'Authorization' => 'apikey TESTME'
        }
      )
      .to_return(
        status: 200,
        headers: { "content-Type" => "application/json" },
        body: unsuppressed_loc_with_two_holdings_json
      )
  end
  describe "#get_bib_record" do
    context "when an unsuppressed bib is provided" do
      it "returns one record" do
        unsuppressed_id = "991227850000541"
        stub_alma_ids(ids: unsuppressed_id, status: 200, fixture: "unsuppressed_991227850000541")

        expect(adapter.get_bib_record(unsuppressed_id)['001'].value).to eq "991227850000541"
      end
    end
    context "when a suppressed bib is provided" do
      it "returns nil" do
        id = "99222441306421"
        stub_alma_ids(ids: id, status: 200, fixture: "suppressed_#{id}")
        expect(adapter.get_bib_record(suppressed)).to be nil
      end
    end
    context "when a record is not found" do
      it "returns nil" do
        stub_alma_ids(ids: "1234", status: 200, fixture: "not_found")

        expect(adapter.get_bib_record("1234")).to be nil
      end
    end
    context "when a bad ID is given" do
      it "returns nil" do
        stub_alma_ids(ids: "bananas", status: 400, fixture: "bad_request")

        expect(adapter.get_bib_record("bananas")).to be nil
      end
    end

    context "record with no physical inventory" do
      it "doesn't have an AVA tag" do
        id = "99171146000521"
        stub_alma_ids(ids: id, status: 200, fixture: "#{id}_no_AVA")

        expect(adapter.get_bib_record(id)['AVA']).to be nil
      end
    end

    context "record with electronic inventory" do
      it "has an AVE tag" do
        id = "99171146000521"
        stub_alma_ids(ids: id, status: 200, fixture: "#{id}_no_AVA")

        expect(adapter.get_bib_record(id)['AVE']).not_to be nil
      end
    end
  end

  describe "#get_bib_records" do
    context "if a string of bibs is provided" do
      it "returns multiple unsuppressed records" do
        ids = ["991227850000541", "991227840000541", "99222441306421"]
        stub_alma_ids(ids: ids, status: 200, fixture: "unsuppressed_suppressed")

        expect(adapter.get_bib_records(ids)[0]['001'].value).to eq unsuppressed_two
        expect(adapter.get_bib_records(ids)[1]['001'].value).to eq unsuppressed
        expect(adapter.get_bib_records(ids).count).to eq 2
      end
    end
  end

  describe '#get_holding_records' do
    it "returns the holdings for a bib" do
      expect(adapter.get_holding_records(unsuppressed)).to be_a(String)
    end
  end

  describe ".get_items_for_bib" do
    it "returns a Hash" do
      expect(adapter.get_items_for_bib(unsuppressed)).to be_a Hash
    end

    # no need to check for a 959 in Alma. This will be a check after the index
    context "A record with order information" do
      it "has a PO line" do
        expect(adapter.get_items_for_bib(bib_items_po)["main"].first["items"].first).to include("po_line" => "POL-8129")
        # we added a PO for a holding
        # MMS ID 99227515106421 Holdings ID 2284011070006421 Item ID 2384011050006421
        # it has in the AVA $e unavailable <subfield code="e">unavailable</subfield>
        # we might want to test this on the item level or in the availability.
        # TODO What does the AVA tag display after the PO is accepted.
        # TODO test what info is returned when this process type is complete.
      end
      it "has a process_type of ACQ-acquisition" do
        expect(adapter.get_items_for_bib(bib_items_po)["main"].first["items"].first).to include("process_type" => { "desc" => "Acquisition", "value" => "ACQ" })
      end
      it "has a barcode" do
        expect(adapter.get_items_for_bib(bib_items_po)["main"].first["items"].first).to include("barcode" => "A19129")
      end
      it "has an item" do
        expect(adapter.get_items_for_bib(bib_items_po)["main"].first["items"].first).to include("pid" => "2384011050006421")
      end
      it "has a base_status" do
        expect(adapter.get_items_for_bib(bib_items_po)["main"].first["items"].first).to include("base_status" => { "desc" => "Item not in place", "value" => "0" })
      end
    end

    context "A record with two locations and two items in each location" do
      it "returns a hash with 2 locations" do
        items = adapter.get_items_for_bib(unsuppressed_two_loc_two_items)
        expect(items.keys).to eq ["offsite", "RESERVES"]
        expect(items.values.map(&:count)).to eq [1, 1] # each array has a single holdings hash
        expect(items["offsite"].first["items"].count).to eq 2
        expect(items["offsite"].first.keys).to eq ["holding_id", "call_number", "items"]
      end
      describe "the first item in the offsite location" do
        it "has an item id" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["offsite"].first["items"][0]).to include("pid" => "2382260930006421")
        end
        it "is in the Main library" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["offsite"].first["items"][0]).to include("library" => { "desc" => "Main Library", "value" => "MAIN" }, "location" => { "desc" => "Building 9", "value" => "offsite" })
        end
        it "has base_status 'Item in place'" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["offsite"].first["items"][0]).to include("base_status" => { "value" => "1", "desc" => "Item in place" })
        end
        it "has a due_date_policy" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["offsite"].first["items"][0]).to include("due_date_policy" => "Loanable")
        end
      end
      describe "the first item in the RESERVES location" do
        it "has an item id" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["RESERVES"].first["items"][0]).to include("pid" => "2382260850006421")
        end
        it "is in the Main library" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["RESERVES"].first["items"][0]).to include("library" => { "desc" => "Main Library", "value" => "MAIN" }, "location" => { "desc" => "Course Reserves", "value" => "RESERVES" })
        end
        it "has base_status 'Item in place'" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["RESERVES"].first["items"][0]).to include("base_status" => { "value" => "1", "desc" => "Item in place" })
        end
        it "has a due_date_policy" do
          expect(adapter.get_items_for_bib(unsuppressed_two_loc_two_items)["RESERVES"].first["items"][0]).to include("due_date_policy" => "Loanable")
        end
      end
    end

    context "A record with two locations and two different holdings in one location" do
      describe "location main" do
        it "has two holdings with two items in each" do
          items = adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)
          expect(items["main"].first["items"].count).to eq 2
          expect(adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)["main"][0]["items"][0]).to include("pid" => "2384629900006421")
          expect(adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)["main"][0]["items"][1]).to include("pid" => "2384621860006421")
          expect(adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)["main"][1]["items"][0]).to include("pid" => "2384621850006421")
          expect(adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)["main"][1]["items"][1]).to include("pid" => "2384621840006421")
        end
      end
      describe "location music" do
        it "has one holding" do
          expect(adapter.get_items_for_bib(unsuppressed_loc_with_two_holdings)["music"].count).to eq 1
        end
      end
    end
  end

  describe "a record that has an ARK" do
    xit "exposes the ark" do
      # find an alma record with an ark.princeton.edu
    end
  end

  describe "a record with no item" do
    # it has a holding
    # it doesn't have an item. This should be checked on the Holding
    xit "has a holding" do
    end
  end
end