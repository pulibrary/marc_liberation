# encoding: UTF-8

settings do
  provide "solr.url", "http://localhost:8983/solr/blacklight-core-development" # default
  provide "marc_source.type", "xml"
  provide "solr_writer.max_skipped", "50"
  provide "marc4j_reader.source_encoding", "UTF-8"
  provide "log.error_file", "./log/traject-error.log"
  provide "allow_duplicate_values", false
end

to_field 'id', extract_marc('001', first: true)

# Title:
#    245 XX abchknps
to_field 'title_display', extract_marc('245abcfghknps', alternate_script: false)
