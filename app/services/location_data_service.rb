class LocationDataService
  # Delete existing locations data repopulate tables with data from Alma
  def self.delete_existing_and_repopulate
    new.delete_existing_and_repopulate
  end

  def delete_existing_and_repopulate
    Locations::HoldingLocation.delete_all
    Locations::Library.delete_all
    populate_libraries
    populate_holding_locations
  end

  def populate_libraries
    libraries.each do |library|
      Locations::Library.create(
        label: library.name,
        code: library.code
      )
    end
  end

  def populate_holding_locations
    libraries.each do |library|
      library_record = Locations::Library.find_by(code: library.code)
      holding_locations(library.code).each do |holding_location|
        Locations::HoldingLocation.new do |location_record|
          location_record.label = "#{library_record.label} - #{holding_location.name}"
          location_record.code = "#{library.code}$#{holding_location.code}"
          location_record.open = open_value(holding_location.type)
          location_record.library = library_record
          location_record.save
        end
      end
    end
  end

  private

    # Retrieves holding locations from Alma.
    # @param library_code [String] e.g. "main"
    # @return Alma::LocationSet
    def holding_locations(library_code)
      Alma::Location.all(library_code: library_code)
    end

    # Retrieves libraries from Alma.
    # @return Alma::LibrarySet
    def libraries
      @libraries ||= Alma::Library.all
    end

    # Generates 'open' value from holding location type
    # @param type [Hash]
    # @return Boolean
    def open_value(type)
      return true if type["value"] == "OPEN"
      false
    end
end
