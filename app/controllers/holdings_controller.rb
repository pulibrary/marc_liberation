class HoldingsController < ApplicationController
  include FormattingConcern

  def index
    if params[:items_only] == '1'
      redirect_to action: :holding_items, holding_id: params[:holding_id], status: :moved_permanently
    elsif params[:items_only] == '0'
      redirect_to action: :holding, holding_id: params[:holding_id], status: :moved_permanently
    else
      render plain: "Record please supply a holding id.", status: 404
    end
  end

  module MarcLiberation
    module XmlSerializer
      class Resource
        def initialize(model)
          @model = model
        end

        def self.build_document(model)
          obj = self.new(model)
          obj.document
        end
      end

      class BibItem < Resource
        def self.new_document
          Nokogiri::XML("item")
        end

        def root_element
          @root_element = begin
                            @document = self.class.new_document
                            @document.root
                          end
        end

        def build_attribute_value(key:, value:)
          if value.is_a?(Hash)
            node_set = Nokogiri::XML::NodeSet.new(root_element.document)
            if value.key?(:value)
              child_key = :xml_value
              child_value = value[:value]
              new_element = build_attribute_element(key: child_key, value: child_value)
            else
              value.each_pair do |child_key, child_value|
                new_element = build_attribute_element(key: child_key, value: child_value)
                node_set.push(new_element)
              end
            end
            node_set
          elsif value.is_a?(Array)
            node_set = Nokogiri::XML::NodeSet.new(root_element.document)
            value.each do |child_value|
              child_key = key.singularize
              new_element = build_attribute_element(key: child_key, value: child_value)
              node_set.push(new_element)
            end
            node_set
          else
            value
          end
        end

        def build_attribute_element(key:, value:)
          new_element = root_element.create_element(key.to_s)
          if value.is_a?(Hash)
            if value.key?(:link)
              new_element['link'] = value['link'] || 'string'
              value.delete(:link)
            elsif value.key?(:desc)
              new_element['desc'] = value['desc'] || 'string'
              value.delete(:desc)
            end
          end
          new_element.content = build_attribute_value(key: key, value: value)
          new_element
        end

        def build_document
          @document = self.new_document
          @model.attributes.each_pair do |key, value|
            attribute_element = build_attribute_element(key: key, value: value)
            @document.add_child(attribute_element.to_xml)
          end
          @document
        end
      end

      class BibItemSet < Resource
        def self.new_document
          Nokogiri::XML("items")
        end

        def build_document
          @document = self.new_document
          @model.items.each do |child|
            child_document = child.xml_document
            @document.root.add_child(child_document.root.to_xml)
          end

          @document
        end

        def document
          build_document
        end
      end
    end

    class Items
      def self.xml_serializer
        XmlSerializer::BibItemSet
      end

      def initialize(model)
        @model = model
      end

      def to_json
        @to_json ||= @model.items.map(&:to_json)
      end

      def attributes
        @attributes ||= to_json.deep_symbolize_keys
      end

      def xml_document
        self.class.xml_serializer.build_document(@model)
      end

      def to_xml
        xml_document.to_xml
      end
    end

    class Holding < Items
      def to_json
        @to_json ||= @model.holding_data
      end
    end
  end

  def bib_id
    @bib_id ||= begin
                  value = params[:bib_id]
                  sanitize(value)
                end
  end

  def holding_id
    @holding_id ||= begin
                      value = params[:holding_id]
                      sanitize(value)
                    end
  end

  def holding_model
    @holding_model ||= Alma::BibItem.find(bib_id, holding_id: holding_id)
  end

  def current_holding
    @holding ||= MarcLiberation::Holding.new(holding_model)
  end

  def item_model
    @item_model ||= Alma::BibItem.find(bib_id, holding_id: holding_id)
  end

  def current_items
    @items ||= MarcLiberation::Items.new(item_model)
  end

  def holding
    if holding_model.nil?
      render plain: "Record #{holding_id_param} not found or suppressed.", status: 404
      binding.pry
    else
      respond_to do |wants|
        wants.json  { render json: MultiJson.dump(holding.to_json) }
        wants.xml { render xml: holding.to_xml }
      end
    end
  end

  def holding_items
    if item_model.nil?
      render plain: "Holding #{holding_id_param} not found or suppressed.", status: 404
    else
      respond_to do |wants|
        wants.html
        wants.json  { render json: MultiJson.dump(items.to_json) }
        wants.xml { render xml: items.to_xml }
      end
    end
  end
end
