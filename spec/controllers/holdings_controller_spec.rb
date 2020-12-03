require 'rails_helper'
require 'json'

RSpec.describe HoldingsController, type: :controller do
  let(:holdings_fixture_path) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'alma_holdings.json') }
  let(:holdings_fixture) { File.read(holdings_fixture_path) }
  before do
    stub_request(:get, "https://api-na.hosted.exlibrisgroup.com/almaws/v1/bibs/10/holdings/100/items").to_return(status: 200, body: holdings_fixture, headers: { "Content-Type" => "application/json; charset=utf-8" })
  end

  describe '#holding' do
    context 'when a bib. ID and a holding ID is provided' do
      let(:bib_id) { "10" }
      let(:holding_id) { "100" }
      context 'when requesting an XML serialization' do
        it 'returns an Item resource serialized as an XML Document' do
          get :holding, params: { bib_id: bib_id, holding_id: holding_id }, format: :xml
          expect(response.status).to eq(200)
          expect(response.body).not_to be_empty

          pending
        end
      end

      context 'when requesting an JSON serialization' do
        it 'returns an Item resource serialized as an JSON Object' do
          get :holding, params: { bib_id: bib_id, holding_id: holding_id }, format: :json
          expect(response.status).to eq(200)
          json_body = JSON.parse(response.body)
          expect(json_body).not_to be_empty

          pending
        end
      end
    end
  end

  describe '#holding_items' do
    context 'when a bib. ID is provided' do
      let(:bib_id) { "10" }
      let(:holding_id) { "100" }
      context 'when requesting an XML serialization' do
        it 'returns an Item resource serialized as an XML Document' do
          get :holding_items, params: { bib_id: bib_id, holding_id: holding_id }, format: :xml
          expect(response.status).to eq(200)
          expect(response.body).not_to be_empty

          pending
        end
      end

      context 'when requesting an JSON serialization' do
        it 'returns an Item resource serialized as an JSON Object' do
          get :holding_items, params: { bib_id: bib_id, holding_id: holding_id }, format: :json
          expect(response.status).to eq(200)
          json_body = JSON.parse(response.body)
          expect(json_body).not_to be_empty

          pending
        end
      end
    end
  end
end
