require 'rails_helper'

RSpec.describe BibliographicController, type: :controller do
  render_views
  let(:unsuppressed) { "991227850000541" }
  let(:unsuppressed_xml) { file_fixture("alma/unsuppressed_#{unsuppressed}.xml").read }
  let(:marc_991227850000541) { MARC::XMLReader.new(StringIO.new(unsuppressed_xml)).first }
  let(:bib_id) { '1234567' }
  let(:bib_record) { instance_double(MARC::Record) }
  let(:file_path) { Rails.root.join('spec', 'fixtures', "#{bib_id}.mrx") }
  let(:bib_record_xml) { File.read(file_path) }
  let(:one_bib) { "991227850000541" }

  before do
    # allow(bib_record).to receive(:to_xml).and_return bib_record_xml
    # allow(VoyagerHelpers::Liberator).to receive(:get_bib_record).and_return bib_record
    allow(AlmaAdapter::Bib).to receive(:get_bib_record).and_return(marc_991227850000541)
  end

  describe '#update' do
    before { skip("Replace with Alma") }
    it 'does not enqueue a job unless the client is authenticated' do
      post :update, params: { bib_id: bib_id }
      expect(response).to redirect_to user_cas_omniauth_authorize_path
    end

    context 'when authenticated as an administrator' do
      login_admin

      it 'enqueues an Index Job for a bib. record using a bib. ID' do
        post :update, params: { bib_id: bib_id }
        expect(response).to redirect_to(index_path)
        expect(flash[:notice]).to be_present
        expect(flash[:notice]).to eq "Reindexing job scheduled for #{bib_id}"
      end
      context 'renders a flash message' do
        let(:bib_record) { nil }
        it 'when record is not found or is suppressed' do
          post :update, params: { bib_id: bib_id }

          expect(response).not_to redirect_to(index_path)
          expect(flash[:notice]).not_to be_present
          expect(response.body).to eq("Record #{bib_id} not found or suppressed")
        end
      end
    end
  end

  describe '#bib' do
    # let(:bib_id) { '10002695' }
    #     let(:bib_record) do
    #       MARC::XMLReader.new(file_path.to_s).first
    #     end
    #     let(:ark) { "ark:/88435/d504rp938" }
    #     let(:docs) do
    #       [
    #         {
    #           id: "b65cd851-ef01-45f2-b5bd-28c6616574ca",
    #           internal_resource_tsim: [
    #             "ScannedResource"
    #           ],
    #           internal_resource_ssim: [
    #             "ScannedResource"
    #           ],
    #           internal_resource_tesim: [
    #             "ScannedResource"
    #           ],
    #           identifier_tsim: [
    #             ark
    #           ],
    #           identifier_ssim: [
    #             ark
    #           ],
    #           identifier_tesim: [
    #             ark
    #           ],
    #           source_metadata_identifier_tsim: [
    #             bib_id
    #           ],
    #           source_metadata_identifier_ssim: [
    #             bib_id
    #           ],
    #           source_metadata_identifier_tesim: [
    #             bib_id
    #           ]
    #
    #         }
    #       ]
    #     end
    #     let(:pages) do
    #       {
    #         "current_page": 1,
    #         "next_page": 2,
    #         "prev_page": nil,
    #         "total_pages": 1,
    #         "limit_value": 10,
    #         "offset_value": 0,
    #         "total_count": 1,
    #         "first_page?": true,
    #         "last_page?": true
    #       }
    #     end
    #     let(:results) do
    #       {
    #         "response": {
    #           "docs": docs,
    #           "facets": [],
    #           "pages": pages
    #         }
    #       }
    #     end
    #     let(:solr_doc) do
    #       {
    #         "id" => ["10002695"],
    #         "electronic_access_1display" => ["{\"http://arks.princeton.edu/ark:/88435/d504rp938\":[\"Table of contents\"]}"]
    #       }
    #     end
    #     let(:indexer) { instance_double(Traject::Indexer) }
    #     before do
    #       stub_request(:get, "https://figgy.princeton.edu/catalog.json?f%5Bidentifier_tesim%5D%5B0%5D=ark&page=1&q=&rows=1000000").to_return(status: 200, body: JSON.generate(results))
    #       allow(indexer).to receive(:map_record).and_return(solr_doc)
    #       stub_const("TRAJECT_INDEXER", indexer)
    #       stub_ezid(shoulder: "88435", blade: "d504rp938")
    #     end

    it 'generates JSON-LD' do
      pending "Replace with Alma"
      get :bib_jsonld, params: { bib_id: unsuppressed }
      expect(response.body).not_to be_empty
      json_ld = JSON.parse(response.body)
      expect(json_ld).to include 'identifier'
      expect(json_ld['identifier']).to include 'http://arks.princeton.edu/ark:/88435/d504rp938'
    end

    context "it returns an xml record" do
      it 'renders a marc xml record' do
        get :bib, params: { bib_id: unsuppressed }, format: :xml
        expect(response.body).not_to be_empty
        expect(response.body).to include("record xmlns='http://www.loc.gov/MARC21/slim'")
        expect(response.body).to eq(marc_991227850000541.to_xml.to_s)
      end
    end

    context 'when an error is encountered while querying Voyager' do
      before do
        allow(Rails.logger).to receive(:error)
        allow(AlmaAdapter::Bib).to receive(:get_bib_record).and_raise("it's broken")
      end
      it 'returns a 400 HTTP response and logs an error' do
        get :bib, params: { bib_id: bib_id }

        expect(response.status).to be 400
        expect(Rails.logger).to have_received(:error).with("Failed to retrieve the record using the bib. ID: 1234567: it's broken")
      end
    end
  end

  describe '#bib_items' do
    context 'when call number is not handeled by lcsort' do
      let(:fixture_path) do
        # spec/controllers/bibliographic_controller_spec.rb
        File.join(File.dirname(__FILE__), '..', 'fixtures', 'alma_bib_items.json')
      end
      let(:fixture_content) do
        File.read(fixture_path)
      end
      let(:api_request_url) do
        "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/987479/holdings/ALL/items?direction=asc&expand=due_date_policy,due_date&limit=100&order_by=library"
      end
      let(:api_response) do
        fixture_content
      end
      let(:bib_items_json) do
        [{ "holding_id" => "224831320000121",
           "call_number" => "holding CN pre holding Cn suf",
           "items" =>
        [{ "pid" => "23344156380001021",
           "barcode" => "39031031697261",
           "creation_date" => "2012-06-10Z",
           "modification_date" => "2012-06-10Z",
           "base_status" => { "desc" => "string", "value" => "0" },
           "awaiting_reshelving" => "false",
           "reshelving_time" => "2020-06-23T14:00:00.000Z",
           "physical_material_type" => { "desc" => "string", "value" => "ROOM" },
           "policy" => { "desc" => "string", "value" => "09" },
           "provenance" => { "desc" => "string", "value" => "" },
           "po_line" => "08-000030003",
           "is_magnetic" => "false",
           "arrival_date" => "2014-08-01Z",
           "expected_arrival_date" => "2014-08-01Z",
           "year_of_issue" => "2015",
           "enumeration_a" => "",
           "enumeration_b" => "",
           "enumeration_c" => "",
           "enumeration_d" => "",
           "enumeration_e" => "",
           "enumeration_f" => "",
           "enumeration_g" => "",
           "enumeration_h" => "",
           "chronology_i" => "",
           "chronology_j" => "",
           "chronology_k" => "",
           "chronology_l" => "",
           "chronology_m" => "",
           "description" => "This item's description",
           "replacement_cost" => "50.0",
           "receiving_operator" => "",
           "process_type" => { "desc" => "string", "value" => "ACQ" },
           "work_order_at" => { "desc" => "string", "value" => "" },
           "work_order_type" => { "desc" => "string", "value" => "" },
           "inventory_number" => "10791310001021",
           "inventory_date" => "2013-12-11Z",
           "inventory_price" => "100",
           "receive_number" => "10791310001021",
           "weeding_number" => "10791310001021",
           "weeding_date" => "2013-12-11Z",
           "library" => { "desc" => "string", "value" => "GRAD" },
           "location" => { "desc" => "string", "value" => "STACK" },
           "alternative_call_number" => "121108431000",
           "alternative_call_number_type" => { "desc" => "string", "value" => "#" },
           "alt_number_source" => "105510551055",
           "storage_location_id" => "1021021021",
           "pages" => "100",
           "pieces" => "100",
           "public_note" => "Public note",
           "fulfillment_note" => "Fulfillment note",
           "due_date" => "2020-06-23T14:00:00.000Z",
           "due_date_policy" => "",
           "internal_note_1" => "",
           "internal_note_2" => "",
           "internal_note_3" => "",
           "statistics_note_1" => "",
           "statistics_note_2" => "",
           "statistics_note_3" => "",
           "requested" => "false",
           "edition" => "",
           "imprint" => "",
           "language" => "EN",
           "library_details" =>
        { "address" =>
         { "line1" => "address line 1",
           "line2" => "address line 2",
           "line3" => "address line 3",
           "line4" => "address line 4",
           "line5" => "address line 5",
           "city" => "Boston",
           "country" => { "desc" => "string", "value" => "VUT" },
           "email" => "example@example.com",
           "phone" => "1821-131353",
           "postal_code" => "391850011",
           "state" => "state" } },
           "alt_call_no" => [""],
           "call_no" => [""],
           "issue_level_description" => [""],
           "title_abcnph" => "abcnph title",
           "physical_condition" => { "desc" => "string", "value" => "#" } }] }]
      end

      before do
        stub_request(:get, api_request_url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: api_response)
      end

      it 'renders a 200 HTTP response and adds a normalized call number for locator' do
        get :bib_items, params: { bib_id: '987479' }, format: 'json'
        expect(response.status).to be 200
        response_body = response.body
        json_body = JSON.parse(response_body)
        expect(json_body.first["holding_id"]).to eq(bib_items_json.first["holding_id"])
        expect(json_body.first["call_number"]).to eq(bib_items_json.first["call_number"])
        expect(json_body.first["items"]).to eq(bib_items_json.first["items"])
        expect(json_body.first["sortable_call_number"]).to eq("value" => "holding CN pre holding Cn suf")
      end
    end

    context 'when call number is handeled by lcsort' do
      before do
        # allow(VoyagerHelpers::Liberator).to receive(:get_items_for_bib).and_return(
        #   "f" => [{ holding_id: 1412398, call_number: "UB357.E33.1973", items: [{ id: 1503428, on_reserve: "N", copy_number: 1, item_sequence_number: 1, temp_location: nil, perm_location: "f", enum: nil, chron: nil, barcode: "32101004147094", due_date: nil, status: ["Not Charged", "Missing"] }] }, { holding_id: 5434239, call_number: "UB357.E33.1973", items: [{ id: 4647744, on_reserve: "N", copy_number: 2, item_sequence_number: 1, temp_location: nil, perm_location: "f", enum: nil, chron: nil, barcode: "32101072966698", due_date: nil, patron_group_charged: "GRAD", status: ["Not Charged"] }] }]
        # )
      end

      it 'renders a 200 HTTP response and adds a normalized call number for locator' do
        pending "Replace with Alma"
        get :bib_items, params: { bib_id: '1234567' }, format: 'json'
        expect(response.status).to be 200
        expect(response.body).to eq("{\"f\":[{\"holding_id\":1412398,\"call_number\":\"UB357.E33.1973\",\"items\":[{\"id\":1503428,\"on_reserve\":\"N\",\"copy_number\":1,\"item_sequence_number\":1,\"temp_location\":null,\"perm_location\":\"f\",\"enum\":null,\"chron\":null,\"barcode\":\"32101004147094\",\"due_date\":null,\"status\":[\"Not Charged\",\"Missing\"]}],\"sortable_call_number\":\"UB.0357.E33.1973\"},{\"holding_id\":5434239,\"call_number\":\"UB357.E33.1973\",\"items\":[{\"id\":4647744,\"on_reserve\":\"N\",\"copy_number\":2,\"item_sequence_number\":1,\"temp_location\":null,\"perm_location\":\"f\",\"enum\":null,\"chron\":null,\"barcode\":\"32101072966698\",\"due_date\":null,\"patron_group_charged\":\"GRAD\",\"status\":[\"Not Charged\"]}],\"sortable_call_number\":\"UB.0357.E33.1973\"}]}")
      end
    end

    context 'when no items are found' do
      before do
        # allow(VoyagerHelpers::Liberator).to receive(:get_items_for_bib).and_return(nil)
      end

      it 'renders a 404 HTTP response' do
        pending "Replace with Alma"
        get :bib_items, params: { bib_id: '1234567' }, format: 'json'
        expect(response.status).to be 404
      end
    end
  end
end
