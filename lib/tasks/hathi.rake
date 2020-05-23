require 'faraday'
require 'rsolr'

default_bibdata_url = 'https://bibdata.princeton.edu'
bibdata_url = ENV['BIBDATA_URL'] || default_bibdata_url

conn = Faraday.new(url: bibdata_url) do |faraday|
  faraday.request  :url_encoded             # form-encode POST params
  faraday.response :logger                  # log requests to STDOUT
  faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
end

namespace :hathi do
  
  desc "compact hathi overlap report to only include files that overlap"
  task compact_overlap: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      Hathi::CompactOverlap.perform
      output_file = Hathi::CompactFull.get_hathi_file(directory: ENV['HATHI_OUTPUT_DIR'], pattern: 'overlap*compacted.tsv', date_pattern: 'overlap_%Y%m%d_compacted.tsv')
      sorted_file = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(output_file).gsub('.tsv','_sorted.tsv'))
      `sort -t$'\t' -k 1n #{output_file} > #{sorted_file}`
    else
      puts "Environment variable HATHI_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end
  end

  desc 'Compact hathi_full file to only include the identifier and the oclc'
  task compact_full: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      Hathi::CompactFull.compact_full
      output_file = Hathi::CompactFull.get_hathi_file(directory: ENV['HATHI_OUTPUT_DIR'], pattern: 'hathi_full*compacted.tsv', date_pattern:"hathi_full_%Y%m%d_compacted.tsv")
      sorted_file = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(output_file).gsub('.tsv','_sorted.tsv'))
      `sort -t$'\t' -k 2n #{output_file} > #{sorted_file}`
    else
      puts "Environment variable HATHI_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end  
  end

  desc 'Combine Hathi_full and Hathi_overlap_compact files'
  task merge: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      sorted_file1 = Hathi::CompactFull.get_hathi_file(directory: ENV['HATHI_OUTPUT_DIR'],pattern: 'overlap*sorted.tsv', date_pattern: 'overlap_%Y%m%d_compacted_sorted.tsv')
      sorted_file2 = Hathi::CompactFull.get_hathi_file(directory: ENV['HATHI_OUTPUT_DIR'],pattern: 'hathi_full*sorted.tsv', date_pattern:"hathi_full_%Y%m%d_compacted_sorted.tsv")
      hathi_final = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(sorted_file1).gsub('.tsv','_final.tsv'))
      `join -t$'\t' -1 1 -2 2 #{sorted_file1} #{sorted_file2} > #{hathi_final}`
    else
      puts "Environment variable HATHI_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end
  end
  
  desc 'Compact the Full Hathi Data the Overlap file and combine the files'
  task compact_and_merge: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR']
      Rake::Task["hathi:compact_overlap"].invoke 
      Rake::Task["hathi:compact_full"].invoke 
      Rake::Task["hathi:merge"].invoke 
    else
      puts "Environment variable HATHI_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end
  end

  desc 'Index Hathi records using the Hathi final file. (SET_URL: set the solr url)'
  task index_csv: :environment do
    solr_url = ENV['SET_URL']
    solr = IndexFunctions.rsolr_connection(solr_url)
    url_arg = ENV['SET_URL'] ? "-u #{ENV['SET_URL']}" : ''
    if ENV['HATHI_OUTPUT_DIR']
      hathi_file = Hathi::CompactFull.get_hathi_file(directory: ENV['HATHI_OUTPUT_DIR'], pattern: 'overlap*compacted_sorted_final.tsv', date_pattern: 'overlap_%Y%m%d_compacted_sorted_final.tsv')
      CSV.foreach(hathi_file, col_sep: "\t", headers: true) do |row|
        if row[1].present?
          ENV['BIB']=row[1]
          #`SET_ULR=#{solr_url} BIB=#{ENV['BIB']} bundle exec bin/rake #{Rake::Task["liberate:bib"].execute}`
          if ENV['BIB']
            resp = conn.get "/bibliographic/#{ENV['BIB']}"
            File.binwrite('./tmp/tmp.xml', resp.body)
            sh "traject -c marc_to_solr/lib/traject_config.rb ./tmp/tmp.xml #{url_arg}"
          else
            puts 'Please provide a BIB argument (BIB=####)'
          end
        else
          Rails.logger.error("#{row} is missing oclc")
        end
      end
    else
      puts "Environment variable HATHI_OUTPUT_DIR must be set!"
    end
    solr.commit
  end
end
