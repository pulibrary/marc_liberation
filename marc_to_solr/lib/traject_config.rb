# encoding: UTF-8
# Traject config goes here
require 'traject/macros/marc21_semantics'
require 'traject/macros/marc_format_classifier'
require 'bundler/setup'
require_relative './format'
require_relative './princeton_marc'
require_relative './geo'
require_relative './location_extract'
require 'stringex'
require 'library_stdnums'
require 'time'
require 'iso-639'

extend Traject::Macros::Marc21Semantics
extend Traject::Macros::MarcFormats

settings do
  provide "solr.url", "http://localhost:8983/solr/blacklight-core-development" # default
  provide "solr.version", "4.10.0"
  provide "marc_source.type", "xml"
  provide "solr_writer.max_skipped", "50"
  provide "marc4j_reader.source_encoding", "UTF-8"
  provide "log.error_file", "./log/traject-error.log"
  provide "allow_duplicate_values",  false
  provide "figgy_cache_dir", ENV['FIGGY_ARK_CACHE_PATH'] || "tmp/figgy_ark_cache"
end

update_locations if ENV['UPDATE_LOCATIONS']

$LOAD_PATH.unshift(File.expand_path('../../', __FILE__)) # include marc_to_solr directory so local translation_maps can be loaded

to_field 'id', extract_marc('001', first: true)

# if the id contains only numbers we know it's a princeton item
to_field 'numeric_id_b', extract_marc('001', first: true) do |_record, accumulator|
  accumulator.map! { |v| /^[0-9]+$/.match(v) ? true : false }
end

# for scsb local system id
to_field 'other_id_s', extract_marc('009', first: true)
to_field 'cjk_all' do |record, accumulator|
  keep_fields = %w[880]
  result = []
  record.each do |field|
    next unless  keep_fields.include?(field.tag)
    subfield_values = field.subfields
                           .reject { |sf| sf.code == '6' }
                           .collect(&:value)

    next unless !subfield_values.empty?

    result << subfield_values.join(' ')
  end
  accumulator << result.join(' ')
end

# only include the 5xx alt script values for cjk field
to_field 'cjk_notes' do |record, accumulator|
  keep_fields = %w[880]
  result = []
  record.each do |field|
    next unless  keep_fields.include?(field.tag)
    linked_tag = field.subfields.select { |sf| sf.code == '6' }.collect(&:value)
    next unless linked_tag.first&.start_with?('5')
    subfield_values = field.subfields
                           .reject { |sf| sf.code == '6' }
                           .collect(&:value)

    next unless !subfield_values.empty?

    result << subfield_values.join(' ')
  end
  accumulator << result.join(' ')
end

# Author/Artist:
#    100 XX aqbcdek A aq
#    110 XX abcdefgkln A ab
#    111 XX abcdefgklnpq A ab

# previously set to not include alternate script and to have only first value
# to put back in add: alternate_script: false, first: true
to_field 'author_display', extract_marc('100aqbcdk:110abcdfgkln:111abcdfgklnpq', trim_punctuation: true)
to_field 'author_sort', extract_marc('100aqbcdk:110abcdfgkln:111abcdfgklnpq', trim_punctuation: true, first: true)
to_field 'author_citation_display', extract_marc('100a:110a:111a:700a:710a:711a', trim_punctuation: true, alternate_script: false)

to_field 'author_roles_1display' do |record, accumulator|
  authors = process_author_roles(record)
  accumulator[0] = authors.to_json.to_s
end

to_field 'cjk_author' do |record, accumulator|
  names = process_alt_script_names(record)
  accumulator.replace(names)
end

to_field 'author_s' do |record, accumulator|
  names = process_names(record)
  accumulator.replace(names)
end

# for now not separate
# to_field 'author_vern_display', extract_marc('100aqbcdek:110abcdefgkln:111abcdefgklnpq', :trim_punctuation => true, :alternate_script => :only, :first => true)

to_field 'marc_relator_display' do |record, accumulator|
  MarcExtractor.cached("100:110:111").collect_matching_lines(record) do |field, _spec, _extractor|
    relator = 'Author'
    field.subfields.each do |s_field|
      if s_field.code == 'e'
        relator = s_field.value.capitalize.gsub(/[[:punct:]]?$/,'')
        break
      end
      relator = Traject::TranslationMap.new("relators")[s_field.value] if s_field.code == '4'
    end
    accumulator << relator
    break
  end
end

# Uniform title:
#    130 XX apldfhkmnorst T ap
#    240 XX {a[%}pldfhkmnors"]" T ap
to_field 'uniform_title_s', extract_marc('130apldfhkmnorst:240apldfhkmnors', trim_punctuation: true) do |record, accumulator|
  accumulator << everything_after_t(record, '100:110:111')
  accumulator.flatten!
end

# Title:
#    245 XX abchknps
to_field 'title_display', extract_marc('245abcfghknps', alternate_script: false)

to_field 'title_a_index', extract_marc('245a', trim_punctuation: true)

to_field 'title_vern_display', extract_marc('245abcfghknps', alternate_script: :only, first: true)

# to_field 'title_sort', marc_sortable_title
to_field 'title_sort' do |record, accumulator|
  MarcExtractor.cached("245abcfghknps", alternate_script: false).collect_matching_lines(record) do |field, spec, extractor|
    str = extractor.collect_subfields(field, spec).first
    str = str.slice(field.indicator2.to_i, str.length) if str
    accumulator << str if accumulator[0].nil?
  end
end

to_field 'title_vern_sort' do |record, accumulator|
  MarcExtractor.cached("245abcfghknps", alternate_script: :only).collect_matching_lines(record) do |field, spec, extractor|
    str = extractor.collect_subfields(field, spec).first
    str = str.slice(field.indicator2.to_i, str.length) if str
    accumulator << str if accumulator[0].nil?
  end
end

# roman and alt-script title with and without non-filing characters, excluding $h
to_field 'title_no_h_index' do |record, accumulator|
  MarcExtractor.cached("245abcfgknps").collect_matching_lines(record) do |field, spec, extractor|
    str = extractor.collect_subfields(field, spec).first
    if str
      accumulator << str
      str = str.slice(field.indicator2.to_i, str.length)
      accumulator << str
    end
  end
  accumulator
end

to_field 'title_t', extract_marc('245abchknps', alternate_script: false, first: true)
to_field 'title_citation_display', extract_marc('245ab', trim_punctuation: true)

## Series, Title, and Title starts with index-only fields ##
#################################################
to_field 'series_title_index', extract_marc('440anpvx') do |record, accumulator|
  accumulator << everything_after_t(record, '400:410:411')
  accumulator.flatten!
end

to_field 'series_statement_index', extract_marc('490avx')

to_field 'content_title_index', extract_marc('505t')

to_field 'contains_title_index' do |record, accumulator|
  accumulator.replace(everything_after_t(record, '700:710:711'))
end

to_field 'linked_title_index', extract_marc('765st:767st:770st:772st:773st:774st:775st:776st:777st:780st:785st:786st:787st')

to_field 'linked_series_title_index', extract_marc('765k:767k:770k:772k:773k:774k:775k:776k:777k:780k:785k:786k:787k')

to_field 'series_ae_index', extract_marc('830adfghklmnoprstv:840anpv') do |record, accumulator|
  accumulator << everything_after_t(record, '800:810:811')
  accumulator.flatten!
end

to_field 'linked_series_index', extract_marc('760acgst:762acgst')

to_field 'original_version_series_index', extract_marc('534f')

to_field 'cjk_title', extract_marc(%w(
  130apldfhkmnorst:210ab:211a:212a:214a:222ab:240apldfhkmnors:
  242abchnp:243adfklmnoprs:245abcfghknps:246abfnp:247abfhnp:
  440anpvx:490avx:
  505t:534f:730aplskfmnor:740ahnp:
  760acgst:762acgst:765kst:767kst:
  770kst:772kst:773kst:774kst:775kst:776kst:777kst:
  780kst:785kst:786kst:787kst:
  830adfghklmnoprstv:840anpv), alternate_script: :only) do |record, accumulator|
  accumulator << everything_after_t_alt_script(record, '100:110:111:400:410:411:700:710:711:800:810:811')
  accumulator.flatten!
end

to_field 'cjk_series_title', extract_marc(%w(
  440anpvx:490avx:534f:
  760acgst:762acgst:765k:767k:
  770k:772k:773k:774k:775k:776k:777k:
  780k:785k:786k:787k:
  830adfghklmnoprstv:840anpv), alternate_script: :only) do |record, accumulator|
  accumulator << everything_after_t_alt_script(record, '400:410:411:800:810:811')
  accumulator.flatten!
end
#################################################

# Compiled/Created:
#    245 XX fg
to_field 'compiled_created_display', extract_marc('245fg')
to_field 'compiled_created_t', extract_marc('245abchknps')

# Edition
#    250 XX ab
to_field 'edition_display', extract_marc('250ab')

# for browse lists Published/Created
#    880
to_field 'pub_created_vern_display', extract_marc('260abcefg:264abcefg3', alternate_script: :only)

# Published/Created:
#    260 XX abcefg
#    264 XX abc
to_field 'pub_created_display', extract_marc('260abcefg') do |record, accumulator|
  if record['008'] && record['008'].value[6,1] == 'd'
    end_date = record.end_date_from_008
    if end_date && end_date != '9999'
      accumulator.map! do |p|
        if p.last == '-'
          p + end_date
        else
          p
        end
      end
    end
  end
  if record['264']
    rec_264 = []
    MarcExtractor.cached("264abcefg3").collect_matching_lines(record) do |field, spec, extractor|
      rec_264 << [field, spec, extractor]
    end
    rec_264.sort_by! {|r| r[0].indicator2.to_i if r[0].indicator2}
    rec_264 = rec_264.map {|r| r[2].collect_subfields(r[0], r[1]).first }
    accumulator << rec_264
    accumulator.flatten!
  end
end

to_field 'pub_created_s', extract_marc('260abcefg:264abcefg3')

to_field 'pub_citation_display' do |record, accumulator|
  pub_info = set_pub_citation(record)
  accumulator.replace(pub_info)
end

to_field 'pub_date_display' do |record, accumulator|
    accumulator << record.date_from_008
end


to_field 'pub_date_start_sort' do |record, accumulator|
    accumulator << record.date_from_008
end

to_field 'pub_date_end_sort' do |record, accumulator|
    accumulator << record.end_date_from_008
end

to_field 'cataloged_tdt', extract_marc('959a') do |_record, accumulator|
  accumulator[0] = Time.parse(accumulator[0]).utc.strftime("%Y-%m-%dT%H:%M:%SZ") unless accumulator[0].nil?
end

# to_field 'cataloged_tdt' do |record, accumulator|
#   extractor_doc_id =  MarcExtractor.cached("001")
#   doc_id = extractor_doc_id.extract(record).first
#   unless /^SCSB-\d+/ =~ doc_id
#     #puts "#{record['001'].value}"
#     extractor_959a  = MarcExtractor.cached("959a")
#     cataloged_date = extractor_959a.extract(record).first
#     accumulator[0] = Time.parse(cataloged_date).utc.strftime("%Y-%m-%dT%H:%M:%SZ") unless cataloged_date.nil?
#   end
# end


# format - allow multiple - "first" one is used for thumbnail
to_field 'format' do |record, accumulator|
  formats = Format.new(record).bib_format
  formats.each {|fmt| accumulator << Traject::TranslationMap.new("format")[fmt]}
end

# Medium/Support:
#    340 XX 3abcdefhl
to_field 'medium_support_display', extract_marc('340')


# Electronic access:
#    3000 - really 856
#    most have first sub as 4, a few 0,1,7
#    treat the same
#    $u is for the link
#    $y and $3 for display text for link
#    $z additional display text
#    display host name if missing $y or $3
to_field 'electronic_access_1display' do |record, accumulator|
  links = electronic_access_links(record, settings['figgy_cache_dir'])
  accumulator[0] = JSON.generate(links) unless links == {}
end

to_field 'electronic_access_index', extract_marc('856')

# Description:
   # 254 XX a
   # 255 XX abcdefg
   # 342 XX 2abcdefghijklmnopqrstuv
   # 343 XX abcdefghi
   # 352 XX abcdegi
   # 355 XX abcdefghj
   # 507 XX ab
   # 256 XX a
   # 516 XX a
   # 753 XX abc
   # 755 XX axyz
   # 300 XX 3abcefg
   # 306 XX a
   # 515 XX a
   # 362 XX az
to_field 'description_display', extract_marc('254a:255bcdefg:3422abcdefghijklmnopqrstuv:343abcdefghi:352abcdegi:355abcdefghj:507ab:256a:516a:753abc:755axyz:3003abcefg:362az')
to_field 'description_t', extract_marc('254a:255abcdefg:3422abcdefghijklmnopqrstuv:343abcdefghi:352abcdegi:355abcdefghj:507ab:256a:516a:753abc:755axyz:3003abcefg:515a:362az')

to_field 'number_of_pages_citation_display', extract_marc('300a', trim_punctuation: true)

to_field 'coverage_display' do |record, accumulator|
  coverage = decimal_coordinate(record)
  accumulator[0] = coverage unless coverage.nil?
end

to_field "geocode_display" do |record, acc|
  marc_geo_map = Traject::TranslationMap.new("marc_geographic")
  extractor_043a  = MarcExtractor.cached("043a", separator: nil)
  acc.concat(
    extractor_043a.extract(record).collect do |code|
      # remove any trailing hyphens, then map
      marc_geo_map[code.gsub(/\-+\Z/, '')]
    end.compact
  )
end

to_field 'scale_display', extract_marc('255a')

to_field 'projection_display', extract_marc('255b:342a')

# Arrangement:
# #    351 XX 3abc
to_field 'arrangement_display', extract_marc('351abc')

# Translation of:
#    765 XX at
to_field 'translation_of_display', extract_marc('765at', trim_punctuation: true)


# Translated as:
#    767 XX at
to_field 'translated_as_display', extract_marc('767at', trim_punctuation: true)

# Issued with:
#    777 XX at
to_field 'issued_with_display', extract_marc('777at', trim_punctuation: true)

# Continues:
#    780 00 at
#    780 02 at
to_field 'continues_display', extract_marc('780|00|at:780|02|at', trim_punctuation: true)

# Continues in part:
#    780 01 at
#    780 03 at
to_field 'continues_in_part_display', extract_marc('780|01|at:780|03|at', trim_punctuation: true)

# Formed from:
#    780 04 at
to_field 'formed_from_display', extract_marc('780|04|at', trim_punctuation: true)

# Absorbed:
#    780 05 at
to_field 'absorbed_display', extract_marc('780|05|at', trim_punctuation: true)

# Absorbed in part:
#    780 06 at
to_field 'absorbed_in_part_display', extract_marc('780|06|at', trim_punctuation: true)

# Separated from:
#    780 07 at
to_field 'separated_from_display', extract_marc('780|07|at', trim_punctuation: true)

# Continued by:
#    785 00 at
#    785 02 at
to_field 'continued_by_display', extract_marc('785|00|at:785|02|at', trim_punctuation: true)

# Continued in part by:
#    785 01 at
#    785 03 at
to_field 'continued_in_part_by_display', extract_marc('785|01|at:785|03|at', trim_punctuation: true)

# Absorbed by:
#    785 04 at
to_field 'absorbed_by_display', extract_marc('785|04|at', trim_punctuation: true)

# Absorbed in part by:
#    785 05 at
to_field 'absorbed_in_part_by_display', extract_marc('785|05|at', trim_punctuation: true)

# Split into:
#    785 06 at
to_field 'split_into_display', extract_marc('785|06|at', trim_punctuation: true)

# Merged to form:
#    785 07 at
to_field 'merged_to_form_display', extract_marc('785|07|at', trim_punctuation: true)

# Changed back to:
#    785 08 at
to_field 'changed_back_to_display', extract_marc('785|08|at', trim_punctuation: true)

# Frequency:
#    310 XX ab
to_field 'frequency_display', extract_marc('310ab')

# Former frequency:
#    321 XX a
to_field 'former_frequency_display', extract_marc('321ab')

# Has supplement:
#    770 XX at
to_field 'has_supplement_display', extract_marc('770at', trim_punctuation: true)

# Supplement to:
#    772 XX at
to_field 'supplement_to_display', extract_marc('772at', trim_punctuation: true)

# Linking notes:
#    580 XX a
to_field 'linking_notes_display', extract_marc('580a')

# Subseries of:
#    760 XX at
to_field 'subseries_of_display', extract_marc('760at', trim_punctuation: true)

# Has subseries:
#    762 XX at
to_field 'has_subseries_display', extract_marc('762at', trim_punctuation: true)

# Series:
#    400 XX abcdefgklnpqtuvx
#    410 XX abcdefgklnptuvx
#    411 XX acdefgklnpqtuv
#    440 XX anpvx
#    490 XX avx
#    800 XX abcdefghklmnopqrstuv
#    810 XX abcdefgklnt
#    811 XX abcdefghklnpqstuv
#    830 XX adfghklmnoprstv
#    840 XX anpv
# only includes 490 if the value is different from the other fields
to_field 'series_display', extract_marc('400abcdefgklnpqtuvx:410abcdefgklnptuvx:411acdefgklnpqtuv:440anpvx:800abcdefghklmnopqrstuv:810abcdefgklnt:811abcdefghklnpqstuv:830adfghklmnoprstv:840anpv') do |record, accumulator|
  without_punct = accumulator.map { |f| Traject::Macros::Marc21.trim_punctuation(f) }
  MarcExtractor.cached('490avx').collect_matching_lines(record) do |field, spec, extractor|
    series = extractor.collect_subfields(field, spec).first
    accumulator << series unless without_punct.include?(Traject::Macros::Marc21.trim_punctuation(series))
  end
end

# a subset of the series fields and subfields to link to "More in this series"
to_field 'more_in_this_series_t' do |record, accumulator|
  MarcExtractor.cached('440anp:830anp').collect_matching_lines(record) do |field, spec, extractor|
    str = extractor.collect_subfields(field, spec).first
    if str
      str = str.slice(field.indicator2.to_i, str.length)
      if str.nil? || str.empty?
        logger.error "#{record['001']} - Non-filing characters >= title length"
      else
        accumulator << str
      end
    else
      logger.error "#{record['001']} - Missing 440/830 $a"
    end
  end
  accumulator << everything_through_t(record, '800:810:811')
  accumulator.flatten!.map! { |f| Traject::Macros::Marc21.trim_punctuation(f) }
end


# Other version(s):
#    3500 020Z020A
#    3500 020A020Z
#    3500 024A022A
#    3500 022A024A
#    3500 BBID776W
#    3500 BBID787W
#    3500 776X022A
#    3500 022A776X
#    3500 020A776Z
#    3500 776Z020A
# to_field 'Other version(s)_display', extract_marc()
# # #    3500 020Z020A
# # #    3500 020A020Z
# # #    3500 024A022A
# # #    3500 022A024A
# # #    3500 BBID776W
# # #    3500 BBID787W
# # #    3500 776X022A
# # #    3500 022A776X
# # #    3500 020A776Z
# # #    3500 776Z020A

to_field 'geo_related_record_display', extract_marc('772at:7733abdghikmnoprst:777at', trim_punctuation: true)

# Contained in:
#    3500 BBID773W
to_field 'contained_in_s', extract_marc('773w')

# Related record(s):
#    3500 BBID774W
to_field 'related_record_s', extract_marc('774w')

# Link to BIB of other edition
to_field 'other_editions_s', extract_marc('775w')

# Description for the related record
to_field 'related_record_info_display', extract_marc('776i')

# Notes index field 5XX
to_field "notes_index", extract_all_marc_values(from: '500', to: '599')

# Restrictions note:
#    506 XX 3abcde
to_field 'restrictions_note_display', extract_marc('5063abcde')

# Biographical/Historical note:
#    545 XX ab
to_field 'biographical_historical_note_display', extract_marc('545ab')

# Summary note:
#    520 XX 3ab
to_field 'summary_note_display', extract_marc('5203abc')

# Notes:
#    500 XX 3a
#    501 XX a
#    503 XX a
#    502 XX a
#    504 XX ab
#    508 XX a
#    513 XX ab
#    514 XX abcdefghijkm
#    515 XX a
#    518 XX 3a
#    521 XX 3ab
#    522 XX a
#    523 XX a
#    525 XX a
#    527 XX a
#    534 XX abcefklmnpt
#    535 XX 3abcdg
#    536 XX abcdefgh
#    537 XX a
#    538 XX a
#    544 XX 3abcden
#    547 XX a
#    550 XX a
#    556 XX a
#    562 XX 3abcde
#    565 XX 3abcde
#    567 XX a
#    570 XX a
to_field 'notes_display', extract_marc('5003a:590a')
to_field 'with_notes_display', extract_marc('501a')
to_field 'bibliographic_notes_display', extract_marc('503a') #obsolete
to_field 'dissertation_notes_display', extract_marc('502abcdgo')
to_field 'bib_ref_notes_display', extract_marc('504ab')
to_field 'scale_notes_display', extract_marc('507ab') #added
to_field 'credits_notes_display', extract_marc('508a')
to_field 'type_period_notes_display', extract_marc('513ab')
to_field 'data_quality_notes_display', extract_marc('514abcdefghijkm')
to_field 'numbering_pec_notes_display', extract_marc('515a')
to_field 'type_comp_data_notes_display', extract_marc('516a') #added
to_field 'date_place_event_notes_display', extract_marc('5183adop')
to_field 'target_aud_notes_display', extract_marc('5213ab')
to_field 'geo_cov_notes_display', extract_marc('522a')
to_field 'time_period_notes_display', extract_marc('523a') #obsolete
to_field 'supplement_notes_display', extract_marc('525a')
to_field 'study_prog_notes_display', extract_marc('526abcdixz') #added
to_field 'censorship_notes_display', extract_marc('527a') #obsolete
to_field 'reproduction_notes_display', extract_marc('5333abcdefmn')
to_field 'original_version_notes_display', extract_marc('534abcefklmnpt3')
to_field 'location_originals_notes_display', extract_marc('5353abcdg')
to_field 'funding_info_notes_display', extract_marc('536abcdefgh')
to_field 'source_data_notes_display', extract_marc('537a') #obsolete
to_field 'system_details_notes_display', extract_marc('5383ai')
to_field 'related_copyright_notes_display', extract_marc('542|1*|:542| *|') #is this in any record?
to_field 'location_other_arch_notes_display', extract_marc('5443abcden')
to_field 'former_title_complex_notes_display', extract_marc('547a')
to_field 'issuing_body_notes_display', extract_marc('550a')
to_field 'info_document_notes_display', extract_marc('556a')
to_field 'copy_version_notes_display', extract_marc('5623abcde')
to_field 'case_file_notes_display', extract_marc('5653abcde')
to_field 'methodology_notes_display', extract_marc('567a')
to_field 'editor_notes_display', extract_marc('570a') #added
to_field 'accumulation_notes_display', extract_marc('584ab3') #added
to_field 'awards_notes_display', extract_marc('586a3') #added
to_field 'source_desc_notes_display', extract_marc('588a') #added

# Binding note:
#    563 XX au3
to_field 'binding_note_display', extract_marc('563au3')

# Local notes:
#    590 XX a
#    591 XX a
#    592 XX a
to_field 'local_notes_display', extract_marc('591a:592a')

# Rights and reproductions note:
#    540 XX 3abcd
to_field 'rights_reproductions_note_display', extract_marc('5403abcd')

# Exhibitions note:
#    585 XX 3a
to_field 'exhibitions_note_display', extract_marc('5853a')

# Participant(s)/Performer(s):
#    511 XX a
to_field 'participant_performer_display', extract_marc('511a')

# Language(s):
#    546 XX 3a
to_field 'language_display', extract_marc('5463a')

to_field 'language_facet', marc_languages

to_field 'publication_place_facet', extract_marc('008[15-17]') do |_record, accumulator|
  places = accumulator.map { |c| Traject::TranslationMap.new('marc_countries')[c.strip] }
  accumulator.replace(places.compact)
end

# Script:
#    546 XX b
to_field 'script_display', extract_marc('546b')

to_field 'language_code_s', extract_marc('008[35-37]:041a:041d') do |_record, accumulator|
  codes = accumulator.compact.map { |c| c.length == 3 ? c : c.scan(/.{1,3}/) }
  accumulator.replace(codes.flatten)
end

to_field 'language_iana_s', extract_marc('008[35-37]:041a:041d') do |_record, accumulator|
  codes = accumulator.compact.map { |c| c.length == 3 ? c : c.scan(/.{1,3}/) }.flatten.uniq
  codes = codes.reject { |c| ISO_639.find(c).nil? }.map do |c|
    if ISO_639.find(c).alpha2.empty?
      c
    else
      ISO_639.find(c).alpha2
    end
  end
  accumulator.replace(codes)
end

# Contents:
#    505 0X agrt
#    505 8X agrt
to_field 'contents_display', extract_marc('505agrt')

# Provenance:
#    561 XX 3ab
#    796 XX abcqde
#    797 XX abcqde
to_field 'provenance_display', extract_marc('561|1*|3ab:561| *|3ab') #:796abcqde:797abcqde')

# Source of acquisition:
#    541 XX abcdefhno36
to_field 'source_acquisition_display', extract_marc('541|1*|abcdefhno36:541| *|abcdefhno36')

# Publications about:
#    581 XX az36
to_field 'publications_about_display', extract_marc('581az36')

# Indexed in:
#    510 0X 3abc
#    510 1X 3abc
#    510 2X 3abc
to_field 'indexed_in_display', extract_marc('510|0*|3abc:510|1*|3abc:510|2*|3abc')

# References:
#    510 3X 3abc
#    510 4X 3abc
to_field 'references_display', extract_marc('510|3*|3abc:510|4*|3abc')

to_field 'references_url_display', extract_marc('510|3*|3abcu:510|4*|3abcu')

# Cite as:
#    524 XX 23a
to_field 'cite_as_display', extract_marc('52423a')

# Other format(s):
#    530 XX 3abcd
#    533 XX 3abcdefmn
to_field 'other_format_display', extract_marc('5303abcd')

# Cumulative index/Finding aid:
#    555 XX 3abcd

# No indicator 1- cumulative index
to_field 'indexes_display', extract_marc('555| *|3abcd')

# Indicator 1 = 0 - finding aid
to_field 'finding_aid_display', extract_marc('555|0*|3abcd')

# Indicator 1 = 8 - not specified
to_field 'cumulative_index_finding_aid_display', extract_marc('555|8*|3abcd')

# Subject(s):
#    600 XX acdfklmnopqrst{v--%}{x--%}{y--%}{z--%} S abcdfklmnopqrtvxyz
#    610 XX abfklmnoprst{v--%}{x--%}{y--%}{z--%} S abfklmnoprstvxyz
#    611 XX abcdefgklnpqst{v--%}x--%}{y--%}{z--%} S abcdefgklnpqstvxyz
#    630 XX adfgklmnoprst{v--%}{x--%}{y--%}{z--%} S adfgklmnoprstvxyz
#    650 XX abc{v--%}{x--%}{z--%}{y--%} S abcvxyz
#    651 XX a{v--%}{x--%}{y--%}{z--%} S avxyz
to_field 'lc_subject_display' do |record, accumulator|
  subjects = process_hierarchy(record, '600|*0|abcdfklmnopqrtvxyz:610|*0|abfklmnoprstvxyz:611|*0|abcdefgklnpqstvxyz:630|*0|adfgklmnoprstvxyz:650|*0|abcvxyz:651|*0|avxyz')
  accumulator.replace(subjects)
end

to_field 'siku_subject_display' do |record, accumulator|
  genres = process_hierarchy(record, '650|*7|abcvxyz', ['sk'])
  accumulator.replace(genres)
end

# Adds lc and siku subject unstem_search fields
each_record do |_record, context|
  context.output_hash['subject_unstem_search'] = context.output_hash['lc_subject_display']
  context.output_hash['siku_subject_unstem_search'] = context.output_hash['siku_subject_display']
end


# used for the browse lists and hierarchical subject/genre facet
to_field 'subject_facet' do |record, accumulator|
  subjects = process_hierarchy(record, '600|*0|abcdfklmnopqrtvxyz:610|*0|abfklmnoprstvxyz:611|*0|abcdefgklnpqstvxyz:630|*0|adfgklmnoprstvxyz:650|*0|abcvxyz:651|*0|avxyz')
  sk_subjects = process_hierarchy(record, '650|*7|abcvxyz', ['sk'])
  genres = process_hierarchy(record, '655|*7|avxyz', ['lcgft', 'aat', 'rbbin', 'rbgenr', 'rbmscv', 'rbpap', 'rbpri', 'rbprov', 'rbpub', 'rbtyp'])
  accumulator.replace([subjects, sk_subjects, genres].flatten)
end

to_field 'lcgft_s' do |record, accumulator|
  genres = process_hierarchy(record, '655|*7|avxyz', ['lcgft'])
  accumulator.replace(genres)
end

to_field 'aat_s' do |record, accumulator|
  genres = process_hierarchy(record, '655|*7|avxyz', ['aat'])
  accumulator.replace(genres)
end

to_field 'rbgenr_s' do |record, accumulator|
  genres = process_hierarchy(record, '655|*7|avxyz', ['rbbin', 'rbgenr', 'rbmscv', 'rbpap', 'rbpri', 'rbprov', 'rbpub', 'rbtyp'])
  accumulator.replace(genres)
end

to_field 'cjk_subject', extract_marc('600|*0|abcdfklmnopqrtvxyz:610|*0|abfklmnoprstvxyz:611|*0|abcdefgklnpqstvxyz:630|*0|adfgklmnoprstvxyz:650|*0|abcvxyz:650|*7|abcvxyz:651|*0|avxyz', alternate_script: :only)

# used for split subject topic facet
to_field 'subject_topic_facet' do |record, accumulator|
  subjects = process_subject_topic_facet(record)
  accumulator.replace(subjects)
end

to_field 'lc_1letter_facet' do |record, accumulator|
  if record['050']
    if record['050']['a']
      first_letter = record['050']['a'].lstrip.slice(0, 1)
      letters = /([[:alpha:]])*/.match(record['050']['a'])[0]
      accumulator << Traject::TranslationMap.new("callnumber_map")[first_letter] if !Traject::TranslationMap.new("callnumber_map")[letters].nil?
    end
  end
end

to_field 'lc_rest_facet' do |record, accumulator|
  if record['050']
    if record['050']['a']
      letters = /([[:alpha:]])*/.match(record['050']['a'])[0]
      accumulator << Traject::TranslationMap.new("callnumber_map")[letters]
    end
  end
end

to_field 'sudoc_facet' do |record, accumulator|
  MarcExtractor.cached('086|0 |a').collect_matching_lines(record) do |field, spec, extractor|
    letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0] if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
    accumulator << Traject::TranslationMap.new("sudocs")[letters] if !Traject::TranslationMap.new("sudocs")[letters].nil?
  end
end

to_field 'call_number_scheme_facet' do |record, accumulator|
  if record['050']
    if record['050']['a']
      first_letter = record['050']['a'].lstrip.slice(0, 1)
      letters = /([[:alpha:]])*/.match(record['050']['a'])[0]
      accumulator << "Library of Congress" if !Traject::TranslationMap.new("callnumber_map")[letters].nil?
    end
  end
  MarcExtractor.cached('086|0 |a').collect_matching_lines(record) do |field, spec, extractor|
    letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0] if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
    accumulator << "Superintendent of Documents" if !Traject::TranslationMap.new("sudocs")[letters].nil?
  end
end

to_field 'call_number_group_facet' do |record, accumulator|
  MarcExtractor.cached('050a').collect_matching_lines(record) do |field, spec, extractor|
    if record['050'] && record['050']['a']
      if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
        letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0]
        first_letter = record['050']['a'].lstrip.slice(0, 1)
        accumulator << Traject::TranslationMap.new("callnumber_map")[first_letter] if !Traject::TranslationMap.new("callnumber_map")[letters].nil?
      end
    end
  end
  MarcExtractor.cached('086|0 |a').collect_matching_lines(record) do |field, spec, extractor|
    letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0] if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
    accumulator << Traject::TranslationMap.new("sudocs_split")[letters] if !Traject::TranslationMap.new("sudocs_split")[letters].nil?
  end
end

to_field 'call_number_full_facet' do |record, accumulator|
  MarcExtractor.cached('050a').collect_matching_lines(record) do |field, spec, extractor|
    if record['050'] && record['050']['a']
      if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
        letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0]
        accumulator << Traject::TranslationMap.new("callnumber_map")[letters]
      end
    end
  end
  MarcExtractor.cached('086|0 |a').collect_matching_lines(record) do |field, spec, extractor|
    letters = /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)[0] if /([[:alpha:]])*/.match(extractor.collect_subfields(field, spec).first)
    accumulator << Traject::TranslationMap.new("sudocs")[letters] if !Traject::TranslationMap.new("sudocs")[letters].nil?
  end
end

# 600/610/650/651 $v, $x filtered
# 655 $a, $v, $x filtered
to_field 'genre_facet' do |record, accumulator|
  genres = process_genre_facet(record)
  accumulator.replace(genres)
end

# Related name(s):
#    700 XX aqbcdefghklmnoprstx A aq
#    710 XX abcdefghklnoprstx A ab
#    711 XX abcdefgklnpq A ab

# Json string mapping relator terms and names for display
to_field 'related_name_json_1display' do |record, accumulator|
  rel_name_hash = {}
  MarcExtractor.cached("700aqbcdk:710abcdfgkln:711abcdfgklnpq").collect_matching_lines(record) do |field, spec, extractor|
    rel_name = Traject::Macros::Marc21.trim_punctuation(extractor.collect_subfields(field, spec).first)
    relators = []
    non_t = true
    field.subfields.each do |s_field|
      relators << s_field.value.capitalize.gsub(/[[:punct:]]?$/,'') if s_field.code == 'e'
      if s_field.code == 't'
        non_t = false
        break

      end
      relators << Traject::TranslationMap.new("relators")[s_field.value] || s_field.value if s_field.code == '4'
    end
    relators << 'Related name' if relators.empty?
    relators.each do |relator|
      rel_name_hash[relator] ? rel_name_hash[relator] << rel_name : rel_name_hash[relator] = [rel_name] if (non_t && !rel_name.nil?)
    end
  end
  accumulator[0] = rel_name_hash.to_json.to_s unless rel_name_hash == {}
end

to_field 'related_works_1display' do |record, accumulator|
  fields = '700|* |aqbcdfghklmnoprstx:710|* |abcdfghklnoprstx:711|* |abcdefgklnpqt'
  related_works = prep_name_title(record, fields)
  accumulator[0] = related_works.to_json.to_s unless related_works.empty?
end

to_field 'contains_1display' do |record, accumulator|
  fields = '700|*2|aqbcdfghklmnoprstx:710|*2|abcdfghklnoprstx:711|*2|abcdefgklnpqt'
  analytical_entries = prep_name_title(record, fields)
  accumulator[0] = analytical_entries.to_json.to_s unless analytical_entries.empty?
end

to_field 'instrumentation_facet', marc_instrumentation_humanized

# Place name(s):
#    752 XX abcd
to_field 'place_name_display', extract_marc('752abcd')

# Other title(s):
#    246 XX abfnp
#    210 XX ab
#    211 XX a
#    212 XX a
#    214 XX a
#    222 XX ab
#    242 XX abchnp
#    243 XX adfklmnoprs
#    247 XX abfhnp
#    730 XX aplskfmnor
#    740 XX ahnp
to_field 'other_title_index', extract_marc('246abfnp:210ab:211a:212a:214a:222ab:242abchnp:243adfklmnoprs:247abfhnp:730aplskfmnor:740ahnp')

# only include 246 as 'other title' when 2nd indicator missing or 3 and missing $i
to_field 'other_title_display' do |record, accumulator|
  MarcExtractor.cached(%w(246abfnp:210ab:211a:212a:214a:222ab:
                          242abchnp:243adfklmnoprs:247abfhnp:730aplskfmnor:740ahnp
                      )).collect_matching_lines(record) do |field, spec, extractor|
    if field.tag == '246'
      label = field.subfields.select{|s_field| s_field.code == 'i'}.first
      accumulator << extractor.collect_subfields(field, spec).first if label.nil?
    else
      accumulator << extractor.collect_subfields(field, spec).first
    end
  end
  accumulator
end

to_field 'alt_title_246_display', extract_marc('246abfnp')

# 246 hash, 2nd indicator is used for label (hash key), prefer $i if present
to_field 'other_title_1display' do |record, accumulator|
  other_title_hash = {}
  MarcExtractor.cached('246abfnp').collect_matching_lines(record) do |field, spec, extractor|
    label = field.subfields.select{|s_field| s_field.code == 'i'}.first
    unless label.nil?
      label = label.value
      label = Traject::Macros::Marc21.trim_punctuation(label)
      title = extractor.collect_subfields(field, spec).first
      other_title_hash[label] ? other_title_hash[label] << title : other_title_hash[label] = [title] unless title.nil?
    end
  end
  accumulator[0] = other_title_hash.to_json.to_s unless other_title_hash == {}
  accumulator
end

# In:
#    773 XX 3abdghikmnoprst
to_field 'in_display', extract_marc('7733abdghikmnoprst', trim_punctuation: true)

# Constituent part(s):
#    774 XX abcdghikmnrstu
to_field 'constituent_part_display', extract_marc('774abcdghikmnrstu', trim_punctuation: true)

to_field 'other_editions_display', extract_marc('775adhit', trim_punctuation: true)

to_field 'data_source_display', extract_marc('786at', trim_punctuation: true)

# ISBN:
#    020 XX a
to_field 'isbn_display' do |record, accumulator|
  MarcExtractor.cached("020aq").collect_matching_lines(record) do |field, _spec, _extractor|
    a_array = []
    q_array = []
    field.subfields.each do |m|
      if m.code == 'a'
        a_array << m.value
      elsif m.code == 'q'
        q_array << m.value
      end
    end
    a_string = a_array.compact.join if a_array
    q_string = q_array.compact.join("\s:\s") if q_array
    accumulator << if a_string && q_string && !q_string.empty?
                     a_string + ' ' + '(' + q_string + ')'
                   else
                     a_string
                   end
  end
end

# ISSN:
#    022 XX a
to_field 'issn_display', extract_marc('022a')

# SuDoc no.:
#    086 XX a
to_field 'sudoc_no_display', extract_marc('086a')

# Tech. report no.:
#    027 XX a
#    088 XX a
to_field 'tech_report_no_display', extract_marc('027a:088a')

# Publisher. no.:
#    028 XX a
to_field 'publisher_no_display', extract_marc('028a')

# Standard no.:
#    010 XX a
#    030 XX a
to_field 'lccn_display', extract_marc('010a')
to_field 'coden_display', extract_marc('030a')

to_field 'standard_no_024_index', extract_marc('024a')

to_field 'standard_no_1display' do |record, accumulator|
  standard_no = standard_no_hash(record)
  accumulator[0] = standard_no.to_json.to_s unless standard_no == {}
end

to_field 'lccn_s', extract_marc('010a') do |_record, accumulator|
  accumulator.each_with_index do |value, i|
    accumulator[i] = StdNum::LCCN.normalize(value)
  end
end

to_field 'issn_s', extract_marc('022a') do |_record, accumulator|
  accumulator.each_with_index do |value, i|
    accumulator[i] = StdNum::ISSN.normalize(value)
  end
end

to_field 'isbn_s', extract_marc('020a') do |_record, accumulator|
  accumulator.each_with_index do |value, i|
    accumulator[i] = StdNum::ISBN.normalize(value)
  end
  accumulator
end

to_field 'oclc_s', extract_marc('035a') do |_record, accumulator|
  oclcs = []
  accumulator.each_with_index do |value, _i|
    oclcs << oclc_normalize(value) if value.start_with?('(OCoLC)')
  end
  accumulator.replace(oclcs)
end

to_field 'standard_no_index', extract_marc('035a') do |_record, accumulator|
  accumulator.each_with_index do |value, i|
    accumulator[i] = remove_parens_035(value)
  end
end

# Other version(s):
#    3500 BBID776W
#    3500 BBID787W
#    3500 776X022A
#    3500 022A776X
#    3500 020A776Z
#    3500 776Z020A
to_field 'other_version_s' do |record, accumulator|
  linked_nums = other_versions(record)
  accumulator.replace(linked_nums)
end



# Original language:
#    880 XX abc
to_field 'original_language_display', extract_marc('880abc')

to_field 'subject_era_facet', marc_era_facet

# # From displayh.cfg

to_field 'holdings_1display' do |record, accumulator|
  all_holdings = process_holdings(record)
  if all_holdings == {}
    logger.error "#{record['001']} - Missing holdings"
  else
    accumulator[0] = all_holdings.to_json.to_s
  end
end

## for recap notes
to_field 'recap_notes_display' do |record, accumulator|
  recap_notes = process_recap_notes(record)
  unless recap_notes.empty?
    recap_notes.each_with_index do |value, i|
      accumulator[i] = value
    end
  end
end

each_record do |_record, context|
  dissertation_note = context.output_hash['dissertation_notes_display']
  if dissertation_note && dissertation_note.first.downcase.gsub(/[^a-z]/, '').include?("seniorprincetonuniversity")
    context.output_hash['format'] ||= []
    context.output_hash['format'] << Traject::TranslationMap.new("format")['ST']
  end
end

# Process location code once
each_record do |record, context|
  location_codes = []
  MarcExtractor.cached("852b").collect_matching_lines(record) do |field, _spec, _extractor|
    holding_b = nil
    field.subfields.each do |s_field|
      if s_field.code == 'b'
        logger.error "#{record['001']} - Multiple $b in single 852 holding" unless holding_b.nil?
        holding_b ||= s_field.value
      end
    end
    location_codes << holding_b
  end
  # Don't check for hathi if the oclc is missing.
  hathi_locations = []
  if context.output_hash['oclc_s'].present?
    hathi_line = find_hathi_by_oclc(context.output_hash['oclc_s'].first)
    hathi_locations = parse_locations_from_hathi_line(hathi_line)
    hathi_id = parse_hathi_identifer_from_hathi_line(hathi_line)
    context.output_hash['hathi_identifier_s'] = hathi_id if hathi_id.present?
  end  
  unless location_codes.empty?
    location_codes.uniq!
    ## need to through any location code that isn't from voyager, thesis, or graphic arts
    ## issue with the ReCAP project records
    context.output_hash['location_code_s'] = location_codes
    context.output_hash['location'] = Traject::TranslationMap.new("location_display").translate_array(location_codes)
    mapped_codes = Traject::TranslationMap.new("locations")
    holding_library = Traject::TranslationMap.new("holding_library")
    location_codes.each do |l|
      if mapped_codes[l]
        context.output_hash['location_display'] ||= []
        context.output_hash['location_display'] << mapped_codes[l]
        context.output_hash['location'] << holding_library[l] if /^ReCAP/ =~ mapped_codes[l] && ['Special Collections', 'Marquand Library'].include?(holding_library[l])
      else
        logger.error "#{record['001']} - Invalid Location Code: #{l}"
      end
    end

    context.output_hash['access_facet'] = Traject::TranslationMap.new("access", default: "In the Library").translate_array(location_codes | hathi_locations)
    context.output_hash['access_facet'].uniq!

    context.output_hash['location'].uniq!

    # Add library and location for advanced multi-select facet
    context.output_hash['advanced_location_s'] = Array.new(location_codes)
    context.output_hash['advanced_location_s'] << context.output_hash['location']
    context.output_hash['advanced_location_s'].flatten!


    # do not index location field if empty (when location code invalid or online)
    context.output_hash['location'].delete('Online')
    context.output_hash.delete('location') if context.output_hash['location'].empty?
  end
end

# For name-title browse - fields get deleted at end
to_field 'name_title_100', extract_marc('100aqbcdk:110abcdfgkln:111abcdfgklnpq', alternate_script: false, first: true, trim_punctuation: true)
to_field 'name_title_100_vern', extract_marc('100aqbcdk:110abcdfgkln:111abcdfgklnpq', alternate_script: :only, first: true, trim_punctuation: true)
to_field 'name_title_245a', extract_marc('245a', alternate_script: false, first: true, trim_punctuation: true)
to_field 'name_title_245a_vern', extract_marc('245a', alternate_script: :only, first: true, trim_punctuation: true)
to_field 'uniform_240' do |record, accumulator|
  MarcExtractor.cached('240apldfhkmnors', alternate_script: false).collect_matching_lines(record) do |field, spec, _extractor|
    field.subfields.each do |s_field|
      next if (!spec.subfields.nil? && !spec.subfields.include?(s_field.code))
      accumulator << s_field.value
    end
    break
  end
end
to_field 'uniform_240_vern' do |record, accumulator|
  MarcExtractor.cached('240apldfhkmnors', alternate_script: :only).collect_matching_lines(record) do |field, spec, _extractor|
    field.subfields.each do |s_field|
      next if (!spec.subfields.nil? && !spec.subfields.include?(s_field.code))
      accumulator << s_field.value
    end
    break
  end
end

to_field 'name_title_ae_s' do |record, accumulator|
  fields = '800aqbcdfghklmnoprstx:810abcdfghklnoprstx:811abcdefgklnpqt'
  ae = prep_name_title(record, fields)
  accumulator.replace(join_hierarchy_without_author(ae))
end

to_field 'linked_title_s' do |record, accumulator|
  MarcExtractor.cached(%w(760at:762at:765at:767at:770at:772at:773at:774at:
                          775at:776at:777at:780at:785at:786at:787at
                      )).collect_matching_lines(record) do |field, spec, extractor|
    ae = Traject::Macros::Marc21.trim_punctuation(extractor.collect_subfields(field, spec).first)
    non_t = true
    non_a = true
    field.subfields.each do |s_field|
      non_a = false if s_field.code == 'a'
      non_t = false if s_field.code == 't'
      break if (non_a && non_t)
    end
    accumulator << ae unless (non_a || non_t)
  end
end

  ########################################################
  # Author-Title Browse field includes                   #
  # combo 100+240/245a, 700/10/11, 76/77/78x, 800/10/11  #
  ########################################################
each_record do |_record, context|
  doc = context.output_hash
  related_works = join_hierarchy(JSON.parse(doc['related_works_1display'][0])) if doc['related_works_1display']
  contains = join_hierarchy(JSON.parse(doc['contains_1display'][0])) if doc['contains_1display']
  browse_field = [doc['name_title_ae_s'], doc['linked_title_s'], related_works, contains]
  name_uniform_t = []
  if doc['name_title_100']
    author = doc['name_title_100'][0] + '.'
    if doc['uniform_240']
      name_title_100_240 = doc['uniform_240'].unshift(author)
      name_uniform_t << name_title_100_240
      browse_field << join_hierarchy([name_title_100_240])
    elsif doc['name_title_245a']
      browse_field << %(#{author} #{doc['name_title_245a'][0]})
    end
  end
  if doc['name_title_100_vern']
    author = doc['name_title_100_vern'][0] + '.'
    if doc['uniform_240_vern']
      name_title_100_240 = doc['uniform_240_vern'].unshift(author)
      name_uniform_t << name_title_100_240
      browse_field << join_hierarchy([name_title_100_240])
    elsif doc['name_title_245a_vern']
      browse_field << %(#{author} #{doc['name_title_245a_vern'][0]})
    end
  end
  context.output_hash['name_uniform_title_1display'] = [name_uniform_t.to_json.to_s] unless name_uniform_t.empty?

  # combine name-title browse values into a single array
  browse_field = browse_field.compact.flatten.uniq
  context.output_hash['name_title_browse_s'] = browse_field unless browse_field.empty?

  # these fields are no longer necessary
  context.output_hash.delete('name_title_100')
  context.output_hash.delete('name_title_100_vern')
  context.output_hash.delete('uniform_240')
  context.output_hash.delete('uniform_240_vern')
  context.output_hash.delete('name_title_245a')
  context.output_hash.delete('name_title_245a_vern')
  context.output_hash.delete('name_title_ae_s')
end

# Call number: +No call number available
#    852 XX ckhij
to_field 'call_number_display', extract_marc('852ckhij')


to_field 'call_number_browse_s', extract_marc('852khij')


# Location has:
#    1040
#    866 |0 az
#    866 |1 az
#    866 |2 az
#    866 30 az
#    866 31 az
#    866 32 az
#    866 40 az
#    866 41 az
#    866 42 az
#    866 50 az
#    866 51 az
#    866 52 az
#    899 XX a
#to_field 'location_has_display', extract_marc('866| 0|az:866| 1|az:866| 2|az:866|30|az:866|31|az:866|32|az:866|40|az:866|41|az:866|42|az:866|50|az:866|51|az:866|52|az:899a')

# Location has (current):
#    866 || az
#    1020
#to_field 'location_has_current_display', extract_marc('866|  |az')


# Supplements:
#    1042
#    867 XX az
#    1022
#to_field 'supplements_display', extract_marc('867az')


# Indexes:
#    1044
#    868 XX az
#    1024
#to_field 'indexes_display', extract_marc('868az')

########################################################
# Processing already-extracted fields                  #
# Remove holding 856s from electronic_access_1display  #
# and put into holdings_1display                       #
########################################################
each_record do |_record, context|
  if context.output_hash['electronic_access_1display']
    bib_856s = JSON.parse(context.output_hash['electronic_access_1display'].first)
    holding_856s = bib_856s.delete('holding_record_856s')
    unless holding_856s.nil?
      holdings_hash = JSON.parse(context.output_hash['holdings_1display'].first)
      holding_856s.each do |h_id, links|
        holdings_hash[h_id]['electronic_access'] = links
      end
      context.output_hash['holdings_1display'][0] = holdings_hash.to_json.to_s
      context.output_hash['electronic_access_1display'][0] = bib_856s.to_json.to_s
    end
  end
  if context.output_hash['title_display']
    if context.output_hash['title_display'].length > 1
      logger.error "#{context.output_hash['id'].first} - Multiple titles"
      context.output_hash['title_display'] = context.output_hash['title_display'].slice(0,1)
    end
  end
end
