# encoding: utf-8
require 'voyager_helpers'
require 'zip'
require 'net/sftp'
require 'date'
require_relative './concerns/scsb_partner_updates'

class Dump < ActiveRecord::Base

  belongs_to :event
  belongs_to :dump_type
  has_many :dump_files
  # These only apply to change dumps (stored in db rather than text files)
  serialize :delete_ids
  serialize :create_ids
  serialize :update_ids
  serialize :recap_barcodes

  before_destroy do
    self.dump_files.each do |df|
      df.destroy
    end
  end

  def dump_updated_records
    ids = self.update_ids.map { |h| h[:id] }
    dump_file_type = DumpFileType.find_by(constant: 'UPDATED_RECORDS')
    dump_records(ids, dump_file_type)
  end

  def dump_created_records
    ids = self.create_ids.map { |h| h[:id] }
    dump_file_type = DumpFileType.find_by(constant: 'NEW_RECORDS')
    dump_records(ids, dump_file_type)
  end

  def dump_bib_records(bib_ids, priority = 'default')
    dump_file_type = DumpFileType.find_by(constant: 'BIB_RECORDS')
    dump_records(bib_ids, dump_file_type, priority)
  end

  def dump_updated_recap_records(updated_barcodes)
    dump_file_type = DumpFileType.find_by(constant: 'RECAP_RECORDS')
    dump_records(updated_barcodes, dump_file_type)
  end

  private

    # @param ids [Array<String>] the IDs for the records being exported
    # @param dump_file_type [DumpFileType] type of records being exported
    # @param priority [String] the priority of the export
    def dump_records(ids, dump_file_type, priority = 'default')
      slice_size = Rails.env.test? ? MARC_LIBERATION_CONFIG['test_records_per_file'] : MARC_LIBERATION_CONFIG['records_per_file']
      ids.each_slice(slice_size).each do |id_slice|
        df = DumpFile.create(dump_file_type: dump_file_type)
        self.dump_files << df
        self.save
        if dump_file_type.constant == 'RECAP_RECORDS'
          RecapDumpJob.perform_later(id_slice, df.id)
        else
          BibDumpJob.set(queue: priority).perform_later(id_slice, df.id)
        end
        sleep 1
      end
    end

  class << self
    def dump_bib_ids
      dump_ids('BIB_IDS')
    end

    def dump_holding_ids
      dump_ids('HOLDING_IDS')
    end

    def dump_recap_records
      dump_ids('PRINCETON_RECAP')
    end

    def diff_since_last
      dump = nil
      Event.record do |event|
        # Get the objects
        earlier_bib_dump, later_bib_dump = last_two_bib_id_dumps
        return if earlier_bib_dump.nil? && later_bib_dump.nil?

        earlier_holding_dump, later_holding_dump = last_two_holding_id_dumps
        return if earlier_holding_dump.nil? && later_holding_dump.nil?

        dump_files = [
          earlier_bib_dump,
          later_bib_dump,
          earlier_holding_dump,
          later_holding_dump
        ].map { |dump| dump.dump_files.first }.compact

        # Unzip them and get the paths
        dump_files.map(&:unzip)

        earlier_bib_dump_file = earlier_bib_dump.dump_files.first
        later_bib_dump_file = later_bib_dump.dump_files.first
        return if earlier_bib_dump_file.nil? && later_bib_dump_file.nil?

        bib_changes_report = VoyagerHelpers::SyncFu.compare_id_dumps(earlier_bib_dump_file.path, later_bib_dump_file.path)

        earlier_holding_dump_file = earlier_holding_dump.dump_files.first
        later_holding_dump_file = later_holding_dump.dump_files.first
        return if earlier_holding_dump_file.nil? && later_holding_dump_file.nil?

        holdings_changes_report = VoyagerHelpers::SyncFu.compare_id_dumps(earlier_holding_dump_file.path, later_holding_dump_file.path)

        bib_changes_report.merge_in_holding_report(holdings_changes_report)

        dump = Dump.create(dump_type: DumpType.find_by(constant: 'CHANGED_RECORDS'))
        dump.event = event
        dump.create_ids = bib_changes_report.created
        dump.update_ids = bib_changes_report.updated
        dump.delete_ids = bib_changes_report.deleted
        dump.save

        # Zip again
        dump_files.map(&:zip)
        dump.dump_updated_records
        dump.dump_created_records
      end
      dump
    end

    def full_bib_dump
      dump = nil
      Event.record do |event|
        dump = Dump.create(dump_type: DumpType.find_by(constant: 'ALL_RECORDS'))
        bibs = last_bib_id_dump
        bibs.dump_files.first.unzip
        bib_path = bibs.dump_files.first.path
        system "awk '{print $1}' #{bib_path} > #{bib_path}.ids"
        bib_id_strings = File.readlines("#{bib_path}.ids").map &:strip
        dump.dump_bib_records(bib_id_strings, 'super_low')
        bibs.dump_files.first.zip
        File.delete("#{bib_path}.ids")
        Event.delete_old_events if event.success == true
        dump.event = event
        dump.save
      end
      dump
    end

    def partner_update
      dump = nil
      Event.record do |event|
        dump = Dump.create(dump_type: DumpType.find_by(constant: 'PARTNER_RECAP'))
        ScsbImportJob.perform_later(dump.id)
        dump.event = event
        dump.save
      end
      dump
    end

    private

      def last_two_bib_id_dumps
        last_two_id_dumps('BIB_IDS')
      end

      def last_two_holding_id_dumps
        last_two_id_dumps('HOLDING_IDS')
      end

      def last_two_id_dumps(dump_type)
        dump_type = DumpType.where(constant: dump_type)
        dumps = Dump.where(dump_type: dump_type).joins(:event).where('events.success' => true).order('id desc').limit(2).reverse
      end

      def last_bib_id_dump
        dump_type = DumpType.where(constant: 'BIB_IDS')
        dump = Dump.where(dump_type: dump_type).joins(:event).where('events.success' => true).order('id desc').first
      end

      def last_recap_dump
        dump_type = DumpType.where(constant: 'PRINCETON_RECAP')
        dump = Dump.where(dump_type: dump_type).joins(:event).where('events.success' => true).order('id desc').first
      end

      def dump_ids(type)
        dump = nil
        Event.record do |event|

          dump = Dump.create(dump_type: DumpType.find_by(constant: type))
          dump.event = event
          dump_file = DumpFile.create(dump: dump, dump_file_type: DumpFileType.find_by(constant: type)) unless type == 'PRINCETON_RECAP'
          if type == 'BIB_IDS'
            VoyagerHelpers::SyncFu.bib_ids_to_file(dump_file.path)
          elsif type == 'HOLDING_IDS'
            VoyagerHelpers::SyncFu.holding_ids_to_file(dump_file.path)
          elsif type == 'PRINCETON_RECAP'
            if last_recap_dump.nil?
              last_dump_date = Time.now - 1.day
            else
              last_dump_date = last_recap_dump.updated_at
            end
            barcodes = VoyagerHelpers::SyncFu.recap_barcodes_since(last_dump_date)
            dump.update_ids = barcodes
            dump.save
            dump.dump_updated_recap_records(barcodes)
          else
            raise 'Unrecognized DumpType'
          end
          unless type == 'PRINCETON_RECAP'
            dump_file.save
            dump_file.zip
            dump.dump_files << dump_file
          end
          dump.save
        end
        dump
      end
  end # class << self
end
