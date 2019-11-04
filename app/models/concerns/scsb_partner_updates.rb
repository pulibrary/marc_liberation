require 'json'

module Scsb
  class PartnerUpdates
    extend ActiveSupport::Concern

    def initialize(dump:, timestamp:)
      @dump = dump
      @update_directory = (ENV['SCSB_PARTNER_UPDATE_DIRECTORY'] || '/tmp/updates') + "/#{Time.now.strftime('%Y%m%d%H%M')}"
      @scsb_file_dir = ENV['SCSB_FILE_DIR'] || 'data'
      @last_dump = timestamp.to_time
      @inv_xml = []
      @tab_newline = []
      @leader = []
      @composed_chars = []
      @bad_utf8 = []
    end

    def process_partner_files
      get_partner_updates
      process_partner_updates
      log_record_fixes
      get_partner_deletes
      process_partner_deletes
    end

    private

      def get_partner_updates
        prepare_directory
        Net::SSH.start(ENV['RECAP_SERVER'], ENV['RECAP_UPDATE_USER'], port: 2222, keys: [ENV['RECAP_TRANSFER_KEY']]) do |ssh|
          files = ssh.sftp.dir.glob(ENV['RECAP_PARTNER_UPDATE_DIR'], '*.zip').map { |entry| { name: "#{ENV['RECAP_PARTNER_UPDATE_DIR']}/#{entry.name}", mod_time: Time.at(entry.attributes.mtime) } }
          files += get_full_partner_filenames(ssh) if ENV['FULL_SCSB_DUMP'] == 'true'
          files.each do |file|
            next unless file[:mod_time] > @last_dump
            filename = file[:mod_time].strftime('%Y%m%d%H%M')
            ssh.sftp.download!(file[:name], "#{@update_directory}/#{filename}.zip")
          end
        end
      end

      def get_full_partner_filenames(ssh)
        files = ssh.sftp.dir.glob(ENV['RECAP_PARTNER_FULL_DIR'], '*.zip').map { |entry| { name: "#{ENV['RECAP_PARTNER_FULL_DIR']}/#{entry.name}", mod_time: Time.at(entry.attributes.mtime) } }
        files.delete_if { |file| File.basename(file[:name]) =~ /PUL/ }
      end

      def get_partner_deletes
        prepare_directory
        Net::SSH.start(ENV['RECAP_SERVER'], ENV['RECAP_UPDATE_USER'], port: 2222, keys: [ENV['RECAP_TRANSFER_KEY']]) do |ssh|
          files = ssh.sftp.dir.glob(ENV['RECAP_PARTNER_DELETE_DIR'], '*.zip').map { |entry| { name: "#{ENV['RECAP_PARTNER_DELETE_DIR']}/#{entry.name}", mod_time: Time.at(entry.attributes.mtime) } }
          files.each do |file|
            next unless file[:mod_time] > @last_dump
            filename = File.basename(file[:name])
            ssh.sftp.download!(file[:name], "#{@update_directory}/#{filename}")
          end
        end
      end

      def process_partner_deletes
        files = Dir.glob("#{@update_directory}/*.zip")
        files.each do |file|
          filename = File.basename(file, '.zip')
          file_increment = 1
          Zip::File.open(file) do |zip_file|
            zip_file.each do |entry|
              target = "#{@update_directory}/scsbdelete#{filename}_#{file_increment}.json"
              entry.extract(target)
              file_increment += 1
            end
          end
          File.unlink(file)
        end
        files = Dir.glob("#{@update_directory}/*.json")
        ids = []
        files.each do |file|
          filename = File.basename(file, '.json')
          scsb_ids(file, ids)
          File.unlink(file)
        end
        @dump.delete_ids = ids
        @dump.save
      end

      def scsb_ids(filename, ids)
        file = File.read(filename)
        data = JSON.parse(file)
        data.each do |record|
          ids << "SCSB-#{record['bib']['bibId']}"
        end
        ids
      end

      def process_partner_updates
        files = Dir.glob("#{@update_directory}/*.zip")
        files.each do |file|
          filename = File.basename(file, '.zip')
          file_increment = 1
          Zip::File.open(file) do |zip_file|
            zip_file.each do |entry|
              target = "#{@update_directory}/#{filename}_#{file_increment}.xml"
              entry.extract(target)
              file_increment += 1
            end
          end
          File.unlink(file)
        end
        filepaths = []
        Dir.glob("#{@update_directory}/*.xml").each do |file|
          filename = File.basename(file)
          reader = MARC::XMLReader.new(file.to_s, external_encoding: 'UTF-8')
          filepath = "#{@scsb_file_dir}/scsbupdate#{filename}"
          writer = MARC::XMLWriter.new(filepath)
          reader.each { |record| writer.write(process_record(record)) }
          writer.close
          filepaths << filepath
          File.unlink(file)
        end
        filepaths.sort.each { |f| attach_dump_file(f) }
      end

      def process_record(record)
        record = field_delete(['856', '959'], record)
        if bad_utf8?(record)
          @bad_utf8 << record['001']
          record = bad_utf8_fix(record)
        end
        if invalid_xml_chars?(record)
          @inv_xml << record['001']
          record = invalid_xml_fix(record)
        end
        if tab_newline_char?(record)
          @tab_newline << record['001']
          record = tab_newline_fix(record)
        end
        if leader_errors?(record)
          @leader << record['001']
          record = leaderfix(record)
        end
        if composed_chars_errors?(record)
          @composed_chars << record['001']
          record = composed_chars_normalize(record)
        end
        record = extra_space_fix(record)
        empty_subfield_fix(record)
      end

      def attach_dump_file(filepath, constant = 'RECAP_RECORDS')
        dump_file_type = DumpFileType.find_by(constant: constant)
        df = DumpFile.create(dump_file_type: dump_file_type, path: filepath)
        df.zip
        df.save
        @dump.dump_files << df
        @dump.save
      end

      def log_record_fixes
        log_file = {
          inv_xml: @inv_xml,
          tab_newline: @tab_newline,
          leader: @leader,
          composed_chars: @composed_chars,
          bad_utf8: @bad_utf8
        }
        filepath = log_file_name
        File.write(filepath, log_file.to_json.to_s)
        attach_dump_file(filepath, 'LOG_FILE')
      end

      def log_file_name
        "#{@scsb_file_dir}/fixes_#{@last_dump.strftime('%Y_%m_%d')}.json"
      end

      def prepare_directory
        if File.exist?(@update_directory)
          Dir.glob("#{@update_directory}/*").each { |file| File.delete(file) }
        else
          Dir.mkdir(@update_directory)
        end
      end
  end
end
