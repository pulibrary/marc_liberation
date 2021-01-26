require "rails_helper"

RSpec.describe "deprecated endpoint routes", type: :routing do
  describe "barcode/:barcode" do
    it "routes to 410 gone" do
      expect(get: "/barcode/32101044947941").to route_to("deprecated_endpoints#gone", barcode: "32101044947941")
    end
  end

  describe "codes/:location" do
    it "routes to 410 gone" do
      expect(get: "/codes/architecture").to route_to("deprecated_endpoints#gone", location: "architecture")
    end
  end

  describe "patron/:patron_id/codes" do
    it "routes to 410 gone" do
      expect(get: "/patron/bbird/codes").to route_to("deprecated_endpoints#gone", patron_id: "bbird")
    end

    it "still accepts routes with dots in them" do
      expect(get: "/patron/ma.dee.e/codes").to route_to("deprecated_endpoints#gone", patron_id: "ma.dee.e")
    end
  end
end
