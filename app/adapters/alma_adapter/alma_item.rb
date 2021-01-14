class AlmaAdapter
  class AlmaItem
    attr_reader :item
    # @param item [Alma::BibItem]
    def initialize(item)
      @item = item
    end

    def enrichment_876
      MARC::DataField.new(
        '876', '0', '0',
        *subfields_for_876
      )
    end

    def subfields_for_876
      [
        MARC::Subfield.new('0', holding_id),
        MARC::Subfield.new('a', item_id),
        MARC::Subfield.new('p', barcode),
        MARC::Subfield.new('t', copy_number)
      ] + recap_876_fields
    end

    def recap_876_fields
      return [] unless item.library == "recap"
      [
        MARC::Subfield.new('h', recap_use_restriction),
        MARC::Subfield.new('x', group_designation),
        MARC::Subfield.new('z', recap_customer_code)
      ]
    end

    def holding_id
      item.holding_data["holding_id"]
    end

    def item_id
      item.item_data["pid"]
    end

    def barcode
      item.item_data["barcode"]
    end

    def copy_number
      item.holding_data["copy_id"]
    end

    def recap_customer_code
      return unless item.library == "recap"
      return "PG" if item.location[0].downcase == "x"
      return item.location.upcase
    end

    def recap_use_restriction
      return unless item.library == "recap"
      case item.location
      when *in_library_recap_groups
        "In Library Use"
      when *supervised_recap_groups
        "Supervised Use"
      end
    end

    def group_designation
      return unless item.library == "recap"
      case item.location
      when 'pa', 'gp', 'qk', 'pf'
        "Shared"
      when *(in_library_recap_groups + supervised_recap_groups + no_access_recap_groups)
        "Private"
      end
    end

    def in_library_recap_groups
      ['pj', 'pk', 'pl', 'pm', 'pn', 'pt']
    end

    def supervised_recap_groups
      ["pb", "ph", "ps", "pw", "pz", "xc", "xg", "xm", "xn", "xp", "xr", "xw", "xx"]
    end

    def no_access_recap_groups
      ['jq', 'pe', 'pg', 'ph', 'pq', 'qb', 'ql', 'qv', 'qx']
    end
  end
end
