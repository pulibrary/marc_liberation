# encoding: UTF-8
require 'library_stdnums'
require 'lightly'
require 'uri'
require_relative 'cache_adapter'
require_relative 'cache_manager'
require_relative 'cache_map'
require_relative 'composite_cache_map'
require_relative 'electronic_access_link'
require_relative 'electronic_access_link_factory'
require_relative 'iiif_manifest_url_builder'
require_relative 'orangelight_url_builder'

module MARC
  class Record
    # Taken from pul-store marc.rb lib extension
    # Shamelessly lifted from SolrMARC, with a few changes; no doubt there will
    # be more.
    @@THREE_OR_FOUR_DIGITS = /^(20|19|18|17|16|15|14|13|12|11|10|9|8|7|6|5|4|3|2|1)(\d{2})\.?$/
    @@FOUR_DIGIT_PATTERN_BRACES = /^\[([12]\d{3})\??\]\.?$/
    @@FOUR_DIGIT_PATTERN_ONE_BRACE = /^\[(20|19|18|17|16|15|14|13|12|11|10)(\d{2})/
    @@FOUR_DIGIT_PATTERN_OTHER_1 = /^l(\d{3})/
    @@FOUR_DIGIT_PATTERN_OTHER_2 = /^\[(20|19|18|17|16|15|14|13|12|11|10)\](\d{2})/
    @@FOUR_DIGIT_PATTERN_OTHER_3 = /^\[?(20|19|18|17|16|15|14|13|12|11|10)(\d)[^\d]\]?/
    @@FOUR_DIGIT_PATTERN_OTHER_4 = /i\.e\.\,? (20|19|18|17|16|15|14|13|12|11|10)(\d{2})/
    @@FOUR_DIGIT_PATTERN_OTHER_5 = /^\[?(\d{2})\-\-\??\]?/
    @@BC_DATE_PATTERN = /[0-9]+ [Bb]\.?[Cc]\.?/
    def best_date
      date = nil
      if self['260']
        if self['260']['c']
          field_260c = self['260']['c']
          case field_260c
          when @@THREE_OR_FOUR_DIGITS
            date = "#{$1}#{$2}"
          when @@FOUR_DIGIT_PATTERN_BRACES
            date = $1
          when @@FOUR_DIGIT_PATTERN_ONE_BRACE
            date = $1
          when @@FOUR_DIGIT_PATTERN_OTHER_1
            date = "1#{$1}"
          when @@FOUR_DIGIT_PATTERN_OTHER_2
            date = "#{$1}#{$2}"
          when @@FOUR_DIGIT_PATTERN_OTHER_3
            date = "#{$1}#{$2}0"
          when @@FOUR_DIGIT_PATTERN_OTHER_4
            date = "#{$1}#{$2}"
          when @@FOUR_DIGIT_PATTERN_OTHER_5
            date = "#{$1}00"
          when @@BC_DATE_PATTERN
            date = nil
          end
        end
      end
      date ||= self.date_from_008
    end

    def date_from_008
      if self['008']
        d = self['008'].value[7, 4]
        d = d.gsub 'u', '0' unless d == 'uuuu'
        d = d.gsub ' ', '0' unless d == '    '
        d if d =~ /^[0-9]{4}$/
      end
    end

    def end_date_from_008
      if self['008']
        d = self['008'].value[11, 4]
        d = d.gsub 'u', '9' unless d == 'uuuu'
        d = d.gsub ' ', '9' unless d == '    '
        d if d =~ /^[0-9]{4}$/
      end
    end

    def date_display
      date = nil
      if self['260']
        date = self['260']['c'] if self['260']['c']
      end
      date ||= self.date_from_008
    end
  end
end

FALLBACK_STANDARD_NO = 'Other standard number'
def map_024_indicators_to_labels i
  case i
  when '0' then 'International Standard Recording Code'
  when '1' then 'Universal Product Code'
  when '2' then 'International Standard Music Number'
  when '3' then 'International Article Number'
  when '4' then 'Serial Item and Contribution Identifier'
  when '7' then '$2'
  else FALLBACK_STANDARD_NO
  end
end

def indicator_label_246 i
  case i
  when '0' then 'Portion of title'
  when '1' then 'Parallel title'
  when '2' then 'Distinctive title'
  when '3' then 'Other title'
  when '4' then 'Cover title'
  when '5' then 'Added title page title'
  when '6' then 'Caption title'
  when '7' then 'Running title'
  when '8' then 'Spine title'
  end
end

def subfield_specified_hash_key subfield_value, fallback
  key = subfield_value.capitalize.gsub(/[[:punct:]]?$/, '')
  key.empty? ? fallback : key
end

def standard_no_hash record
  standard_no = {}
  Traject::MarcExtractor.cached('024').collect_matching_lines(record) do |field, _spec, _extractor|
    standard_label = map_024_indicators_to_labels(field.indicator1)
    standard_number = nil
    field.subfields.each do |s_field|
      standard_number = s_field.value if s_field.code == 'a'
      standard_label = subfield_specified_hash_key(s_field.value, FALLBACK_STANDARD_NO) if (s_field.code == '2') && (standard_label == '$2')
    end
    standard_label = FALLBACK_STANDARD_NO if standard_label == '$2'
    standard_no[standard_label] ? standard_no[standard_label] << standard_number : standard_no[standard_label] = [standard_number] unless standard_number.nil?
  end
  standard_no
end

# Handles ISBNs, ISSNs, and OCLCs
# ISBN: 020a, 020z, 776z
# ISSN: 022a, 022l, 022y, 022z, 776x
# OCLC: 035a, 776w, 787w
# BIB: 776w, 787w (adds BIB prefix so Blacklight can detect whether to search id field)
def other_versions record
  linked_nums = []
  Traject::MarcExtractor.cached('020az:022alyz:035a:776wxz:787w').collect_matching_lines(record) do |field, _spec, _extractor|
    field.subfields.each do |s_field|
      linked_nums << StdNum::ISBN.normalize(s_field.value) if (field.tag == "020") || ((field.tag == "776") && (s_field.code == 'z'))
      linked_nums << StdNum::ISSN.normalize(s_field.value) if (field.tag == "022") || ((field.tag == "776") && (s_field.code == 'x'))
      linked_nums << oclc_normalize(s_field.value, prefix: true) if s_field.value.start_with?('(OCoLC)') && (field.tag == "035")
      if ((field.tag == "776") && (s_field.code == 'w')) || ((field.tag == "787") && (s_field.code == 'w'))
        linked_nums << oclc_normalize(s_field.value, prefix: true) if s_field.value.include?('(OCoLC)')
        linked_nums << "BIB" + strip_non_numeric(s_field.value) unless s_field.value.include?('(')
        logger.error "#{record['001']} - linked field formatting: #{s_field.value}" if s_field.value.include?('(') && !s_field.value.start_with?('(')
      end
    end
  end
  linked_nums.compact.uniq
end

# only includes values before $t
def process_names record
  names = []
  Traject::MarcExtractor.cached('100aqbcdk:110abcdfgkln:111abcdfgklnpq:700aqbcdk:710abcdfgkln:711abcdfgklnpq').collect_matching_lines(record) do |field, spec, extractor|
    name = extractor.collect_subfields(field, spec).first
    unless name.nil?
      remove = ''
      after_t = false
      field.subfields.each do |s_field|
        remove << " #{s_field.value}" if after_t && spec.includes_subfield_code?(s_field.code)
        after_t = true if s_field.code == 't'
      end
      name = name.chomp(remove)
      names << Traject::Macros::Marc21.trim_punctuation(name)
    end
  end
  names.uniq
end

# only includes values before $t
def process_alt_script_names record
  names = []
  Traject::MarcExtractor.cached('100aqbcdk:110abcdfgkln:111abcdfgklnpq:700aqbcdk:710abcdfgkln:711abcdfgklnpq').collect_matching_lines(record) do |field, spec, extractor|
    next unless field.tag == '880'
    name = extractor.collect_subfields(field, spec).first
    unless name.nil?
      remove = ''
      after_t = false
      field.subfields.each do |s_field|
        remove << " #{s_field.value}" if after_t && spec.includes_subfield_code?(s_field.code)
        after_t = true if s_field.code == 't'
      end
      name = name.chomp(remove)
      names << Traject::Macros::Marc21.trim_punctuation(name)
    end
  end
  names.uniq
end

##
# Get hash of authors grouped by role
# @param [MARC::Record]
# @return [Hash]
def process_author_roles record
  author_roles = {
    'TRL' => 'translators',
    'EDT' => 'editors',
    'COM' => 'compilers',
    'TRANSLATOR' => 'translators',
    'EDITOR' => 'editors',
    'COMPILER' => 'compilers'
  }

  names = {}
  names['secondary_authors'] = []
  names['translators'] = []
  names['editors'] = []
  names['compilers'] = []

  Traject::MarcExtractor.cached('100a:110a:111a:700a:710a:711a').collect_matching_lines(record) do |field, spec, extractor|
    name = extractor.collect_subfields(field, spec).first
    unless name.nil?
      name = Traject::Macros::Marc21.trim_punctuation(name)

      # If name is from 1xx field, it is the primary author.
      if /1../.match?(field.tag)
        names['primary_author'] = name
      else
        relator = ""
        field.subfields.each do |s_field|
          # relator code (subfield 4)
          if s_field.code == '4'
            relator = s_field.value.upcase.gsub(/[[:punct:]]?$/, '')
          # relator term (subfield e)
          elsif s_field.code == 'e'
            relator = s_field.value.upcase.gsub(/[[:punct:]]?$/, '')
          end
        end

        # Set role from relator value.
        role = author_roles[relator] || 'secondary_authors'
        names[role] << name
      end
    end
  end
  names
end

##
# Process publication information for citations.
# @param [MARC::Record]
# @return [Array] pub info strings from fields 260 and 264.
def set_pub_citation(record)
  pub_citation = []
  Traject::MarcExtractor.cached('260:264').collect_matching_lines(record) do |field, _spec, _extractor|
    a_pub_info = nil
    b_pub_info = nil
    pub_info = ""
    field.subfields.each do |s_field|
      a_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'a'
      b_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'b'
    end

    # Build publication info string and add to citation array.
    pub_info += a_pub_info unless a_pub_info.nil?
    pub_info += ": " if !a_pub_info.nil? && !b_pub_info.nil?
    pub_info += b_pub_info unless b_pub_info.nil?
    pub_citation << pub_info if !pub_info.empty?
  end
  pub_citation
end

SEPARATOR = '—'

# for the hierarchical subject/genre display
# split with em dash along t,v,x,y,z
# optional vocabulary argument for allowing certain subfield $2 vocabularies
def process_hierarchy(record, fields, vocabulary = [])
  headings = []
  split_on_subfield = ['t', 'v', 'x', 'y', 'z']
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, extractor|
    heading = extractor.collect_subfields(field, spec).first
    include_heading = vocabulary.empty? # always include the heading if a vocabulary is not specified
    unless heading.nil?
      field.subfields.each do |s_field|
        # when specified, only include heading if it is part of the vocabulary
        include_heading = vocabulary.include?(s_field.value) if s_field.code == '2' && !vocabulary.empty?
        heading = heading.gsub(" #{s_field.value}", "#{SEPARATOR}#{s_field.value}") if split_on_subfield.include?(s_field.code)
      end
      heading = heading.split(SEPARATOR)
      heading = heading.map { |s| Traject::Macros::Marc21.trim_punctuation(s) }.join(SEPARATOR)
      headings << heading if include_heading
    end
  end
  headings
end

# for the split subject facet
# split with em dash along x,z
def process_subject_topic_facet record
  subjects = []
  Traject::MarcExtractor.cached('600|*0|abcdfklmnopqrtxz:610|*0|abfklmnoprstxz:611|*0|abcdefgklnpqstxz:630|*0|adfgklmnoprstxz:650|*0|abcxz:651|*0|axz').collect_matching_lines(record) do |field, spec, extractor|
    subject = extractor.collect_subfields(field, spec).first
    unless subject.nil?
      field.subfields.each do |s_field|
        subject = subject.gsub(" #{s_field.value}", "#{SEPARATOR}#{s_field.value}") if (s_field.code == 'x' || s_field.code == 'z')
      end
      subject = subject.split(SEPARATOR)
      subjects << subject.map { |s| Traject::Macros::Marc21.trim_punctuation(s) }
    end
  end
  Traject::MarcExtractor.cached('650|*7|abcxz').collect_matching_lines(record) do |field, spec, extractor|
    subject = extractor.collect_subfields(field, spec).first
    should_include = false
    unless subject.nil?
      field.subfields.each do |s_field|
        should_include = s_field.value == 'sk' if s_field.code == '2'
        subject = subject.gsub(" #{s_field.value}", "#{SEPARATOR}#{s_field.value}") if (s_field.code == 'x' || s_field.code == 'z')
      end
      subject = subject.split(SEPARATOR)
      subjects << subject.map { |s| Traject::Macros::Marc21.trim_punctuation(s) } if should_include
    end
  end
  subjects.flatten
end

def strip_non_numeric num_str
  num_str.gsub(/\D/, '').to_i.to_s
end

def oclc_normalize oclc, opts = { prefix: false }
  oclc_num = strip_non_numeric(oclc)
  if opts[:prefix] == true
    case oclc_num.length
    when 1..8
      "ocm" + "%08d" % oclc_num
    when 9
      "ocn" + oclc_num
    else
      "on" + oclc_num
    end
  else
    oclc_num
  end
end

# Construct (or retrieve) the cache manager service
# @return [CacheManager] the cache manager service
def build_cache_manager(figgy_dir_path:)
  return @cache_manager unless @cache_manager.nil?

  figgy_lightly = Lightly.new(dir: figgy_dir_path, life: 0, hash: false)
  figgy_cache_adapter = CacheAdapter.new(service: figgy_lightly)

  CacheManager.initialize(figgy_cache: figgy_cache_adapter, logger: logger)

  @cache_manager = CacheManager.current
end

# returns hash of links ($u) (key),
# anchor text ($y, $3, hostname), and additional labels ($z) (array value)
# @param [MARC::Record] the MARC record being parsed
# @return [Hash] the values used to construct the links
def electronic_access_links(record, figgy_dir_path)
  solr_field_values = {}
  holding_856s = {}
  iiif_manifest_paths = {}

  output = []
  iiif_manifest_links = []
  fragment_index = 0

  Traject::MarcExtractor.cached('856').collect_matching_lines(record) do |field, _spec, _extractor|
    anchor_text = false
    z_label = false
    url_key = false
    holding_id = nil
    bib_id = record['001']

    electronic_access_link = ElectronicAccessLinkFactory.build bib_id: bib_id, marc_field: field

    # If the electronic access link is an ARK...
    if electronic_access_link.ark
      # ...and attempt to build an Orangelight URL from the (cached) mappings exposed by the repositories
      cache_manager = build_cache_manager(figgy_dir_path: figgy_dir_path)

      # Orangelight links
      catalog_url_builder = OrangelightUrlBuilder.new(ark_cache: cache_manager.ark_cache, fragment: fragment_value(fragment_index))
      orangelight_url = catalog_url_builder.build(url: electronic_access_link.ark)

      if orangelight_url
        # Index this by the domain for Orangelight
        anchor_text = electronic_access_link.anchor_text
        anchor_text = 'Digital content' if electronic_access_link.url&.host == electronic_access_link.anchor_text
        orangelight_link = electronic_access_link.clone url_key: orangelight_url.to_s, anchor_text: anchor_text
        # Only add the link to the current page if it resolves to a resource with a IIIF Manifest
        output << orangelight_link
      else
        # Otherwise, always add the link to the resource
        output << electronic_access_link
      end

      # Figgy URL's
      figgy_url_builder = IIIFManifestUrlBuilder.new(ark_cache: cache_manager.figgy_ark_cache, service_host: 'figgy.princeton.edu')
      figgy_iiif_manifest = figgy_url_builder.build(url: electronic_access_link.ark)
      if figgy_iiif_manifest
        figgy_iiif_manifest_link = electronic_access_link.clone url_key: figgy_iiif_manifest.to_s
        iiif_manifest_paths[electronic_access_link.url_key] = figgy_iiif_manifest_link.url.to_s
      end

    else
      # Always add links to the resource if it isn't an ARK
      output << electronic_access_link
    end

    output.each do |link|
      if link.holding_id
        holding_856s[link.holding_id] = { link.url_key => link.url_labels }
      elsif link.url_key && link.url_labels
        solr_field_values[link.url_key] = link.url_labels
      end
    end
    fragment_index += 1
  end

  solr_field_values['holding_record_856s'] = holding_856s unless holding_856s == {}
  solr_field_values['iiif_manifest_paths'] = iiif_manifest_paths unless iiif_manifest_paths.empty?
  solr_field_values
end

def fragment_value(fragment_index)
  if fragment_index == 0
    'view'
  else
    "view_#{fragment_index}"
  end
end

def remove_parens_035 standard_no
  standard_no.gsub(/^\(.*?\)/, '')
end

GENRES = [
  'Bibliography',
  'Biography',
  'Catalogs',
  'Catalogues raisonnes',
  'Commentaries',
  'Congresses',
  'Diaries',
  'Dictionaries',
  'Drama',
  'Encyclopedias',
  'Exhibitions',
  'Fiction',
  'Guidebooks',
  'In art',
  'Indexes',
  'Librettos',
  'Manuscripts',
  'Newspapers',
  'Periodicals',
  'Pictorial works',
  'Poetry',
  'Portraits',
  'Scores',
  'Songs and music',
  'Sources',
  'Statistics',
  'Texts',
  'Translations'
]

GENRE_STARTS_WITH = [
  'Census',
  'Maps',
  'Methods',
  'Parts',
  'Personal narratives',
  'Scores and parts',
  'Study and teaching',
  'Translations into '
]

SUBJECT_GENRE_VOCABULARIES = ['sk', 'aat', 'lcgft', 'rbbin', 'rbgenr', 'rbmscv',
                              'rbpap', 'rbpri', 'rbprov', 'rbpub', 'rbtyp']

# 600/610/650/651 $v, $x filtered
# 655 $a, $v, $x filtered
def process_genre_facet record
  genres = []
  Traject::MarcExtractor.cached('600|*0|x:610|*0|x:611|*0|x:630|*0|x:650|*0|x:651|*0|x:655|*0|x').collect_matching_lines(record) do |field, spec, extractor|
    genre = extractor.collect_subfields(field, spec).first
    unless genre.nil?
      genre = Traject::Macros::Marc21.trim_punctuation(genre)
      genres << genre if GENRES.include?(genre) || GENRE_STARTS_WITH.any? { |g| genre[g] }
    end
  end
  Traject::MarcExtractor.cached('650|*7|v:655|*7|a:655|*7|v').collect_matching_lines(record) do |field, spec, extractor|
    should_include = false
    field.subfields.each do |s_field|
      # only include heading if it is part of the vocabulary
      should_include = SUBJECT_GENRE_VOCABULARIES.include?(s_field.value) if s_field.code == '2'
    end
    genre = extractor.collect_subfields(field, spec).first
    unless genre.nil?
      genre = Traject::Macros::Marc21.trim_punctuation(genre)
      if genre.match?(/^\s+$/)
        logger.error "#{record['001']} - Blank genre field"
      elsif should_include
        genres << genre
      end
    end
  end
  Traject::MarcExtractor.cached('600|*0|v:610|*0|v:611|*0|v:630|*0|v:650|*0|v:651|*0|v:655|*0|a:655|*0|v').collect_matching_lines(record) do |field, spec, extractor|
    genre = extractor.collect_subfields(field, spec).first
    unless genre.nil?
      genre = Traject::Macros::Marc21.trim_punctuation(genre)
      if genre.match?(/^\s+$/)
        logger.error "#{record['001']} - Blank genre field"
      else
        genres << genre
      end
    end
  end
  genres.uniq
end

def everything_after_t record, fields
  values = []
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, _spec, _extractor|
    after_t = false
    title = []
    field.subfields.each do |s_field|
      title << s_field.value if after_t
      if s_field.code == 't'
        title << s_field.value
        after_t = true
      end
    end
    values << Traject::Macros::Marc21.trim_punctuation(title.join(' ')) unless title.empty?
  end
  values
end

def everything_after_t_alt_script record, fields
  values = []
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, _spec, _extractor|
    next unless field.tag == '880'
    after_t = false
    title = []
    field.subfields.each do |s_field|
      title << s_field.value if after_t
      if s_field.code == 't'
        title << s_field.value
        after_t = true
      end
    end
    values << Traject::Macros::Marc21.trim_punctuation(title.join(' ')) unless title.empty?
  end
  values
end

def everything_through_t record, fields
  values = []
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, _spec, _extractor|
    non_t = true
    title = []
    field.subfields.each do |s_field|
      title << s_field.value
      if s_field.code == 't'
        non_t = false
        break
      end
    end
    values << Traject::Macros::Marc21.trim_punctuation(title.join(' ')) unless (title.empty? || non_t)
  end
  values
end

##
# @param record [MARC::Record]
# @param fields [String] MARC fields of interest
# @return [Array] of name-titles each in an [Array], each element [String] split by hierarchy,
# both name ($a) and title ($t) are required
def prep_name_title record, fields
  values = []
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, _extractor|
    name_title = []
    author = []
    non_a = true
    non_t = true
    field.subfields.each do |s_field|
      next if (!spec.subfields.nil? && !spec.subfields.include?(s_field.code))
      non_a = false if s_field.code == 'a'
      non_t = false if s_field.code == 't'
      if non_t
        author << s_field.value
      else
        name_title << s_field.value
      end
    end
    unless (non_a || non_t)
      name_title.unshift(author.join(' '))
      values << name_title unless name_title.empty?
    end
  end
  values
end

# @param fields [Array] with portions of hierarchy from name-titles
# @return [Array] name-title portions of hierarchy including previous elements, author
def join_hierarchy_without_author fields
  fields.collect { |h| h.collect.with_index { |_v, i| Traject::Macros::Marc21.trim_punctuation(h[0..i].join(' ')) } }
end

# @param fields [Array] with portions of hierarchy from name-titles
# @return [Array] name-title portions of hierarchy including previous elements
def join_hierarchy fields
  join_hierarchy_without_author(fields).map { |a| a[1..-1] }
end

# holding block json hash keyed on mfhd id including location, library, call number, shelving title,
# location note, location has, location has (current), indexes, and supplements
# pulls from mfhd 852, 866, 867, and 868
# assumes exactly 1 852 is present per mfhd (it saves the last 852 it finds)
def process_holdings record # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  all_holdings = {}
  Traject::MarcExtractor.cached('852').collect_matching_lines(record) do |field, _spec, _extractor|
    holding = {}
    holding_id = nil
    field.subfields.each do |s_field|
      if s_field.code == '0'
        holding_id = s_field.value
      elsif s_field.code == 'b'
        holding['location'] ||= s_field.value
        holding['library'] ||= Traject::TranslationMap.new("location_display", default: "__passthrough__")[s_field.value]
        holding['location_code'] ||= s_field.value
      elsif /[ckhij]/.match?(s_field.code)
        holding['call_number'] ||= []
        holding['call_number'] << s_field.value
        if s_field.code == 'c'
          holding['location'] += s_field.value
        elsif s_field.code == 'c'
          holding['call_number_browse'] ||= []
          holding['call_number_browse'] << s_field.value
        end
      elsif s_field.code == 'l'
        holding['shelving_title'] ||= []
        holding['shelving_title'] << s_field.value
      elsif s_field.code == 't' && holding['copy_number'].nil?
        holding['copy_number'] = s_field.value
      elsif s_field.code == 'z'
        holding['location_note'] ||= []
        holding['location_note'] << s_field.value
      end
    end
    holding['call_number'] = holding['call_number'].join(' ') if holding['call_number']
    holding['call_number_browse'] = holding['call_number_browse'].join(' ') if holding['call_number_browse']
    all_holdings[holding_id] = holding unless holding_id.nil? || invalid_location?(holding['location_code'])
  end
  Traject::MarcExtractor.cached('866az').collect_matching_lines(record) do |field, _spec, _extractor|
    value = []
    holding_id = nil
    field.subfields.each do |s_field|
      if s_field.code == '0'
        holding_id = s_field.value
      elsif s_field.code == 'a'
        value << s_field.value
      elsif s_field.code == 'z'
        value << s_field.value
      end
    end
    if (all_holdings[holding_id] && !value.empty?)
      all_holdings[holding_id]['location_has'] ||= []
      all_holdings[holding_id]['location_has'] << value.join(' ')
    end
  end
  Traject::MarcExtractor.cached('8670az').collect_matching_lines(record) do |field, _spec, _extractor|
    value = []
    holding_id = nil
    field.subfields.each do |s_field|
      if s_field.code == '0'
        holding_id = s_field.value
      elsif s_field.code == 'a'
        value << s_field.value
      elsif s_field.code == 'z'
        value << s_field.value
      end
    end
    if (all_holdings[holding_id] && !value.empty?)
      all_holdings[holding_id]['supplements'] ||= []
      all_holdings[holding_id]['supplements'] << value.join(' ')
    end
  end
  Traject::MarcExtractor.cached('8680az').collect_matching_lines(record) do |field, _spec, _extractor|
    value = []
    holding_id = nil
    field.subfields.each do |s_field|
      if s_field.code == '0'
        holding_id = s_field.value
      elsif s_field.code == 'a'
        value << s_field.value
      elsif s_field.code == 'z'
        value << s_field.value
      end
    end
    if (all_holdings[holding_id] && !value.empty?)
      all_holdings[holding_id]['indexes'] ||= []
      all_holdings[holding_id]['indexes'] << value.join(' ')
    end
  end
  ### Added for ReCAP records
  Traject::MarcExtractor.cached('87603ahjptxz').collect_matching_lines(record) do |field, _spec, _extractor|
    item = {}
    field.subfields.each do |s_field|
      if s_field.code == '0'
        item[:holding_id] = s_field.value
      elsif s_field.code == '3'
        item[:enumeration] = s_field.value
      elsif s_field.code == 'a'
        item[:id] = s_field.value
      elsif s_field.code == 'h'
        item[:use_statement] = s_field.value
      elsif s_field.code == 'j'
        item[:status_at_load] = s_field.value
      elsif s_field.code == 'p'
        item[:barcode] = s_field.value
      elsif s_field.code == 't'
        item[:copy_number] = s_field.value
      elsif s_field.code == 'x'
        item[:cgc] = s_field.value
      elsif s_field.code == 'z'
        item[:collection_code] = s_field.value
      end
    end
    if all_holdings[item[:holding_id]]["items"].nil?
      all_holdings[item[:holding_id]]["items"] = [item]
    else
      all_holdings[item[:holding_id]]["items"] << item
    end
  end
  all_holdings
end

def invalid_location?(code)
  Traject::TranslationMap.new("locations")[code].nil?
end

def process_recap_notes record
  item_notes = []
  partner_lib = nil
  Traject::MarcExtractor.cached('852').collect_matching_lines(record) do |field, _spec, _extractor|
    field.subfields.each do |s_field|
      if s_field.code == 'b'
        partner_lib = s_field.value # ||= Traject::TranslationMap.new("locations", :default => "__passthrough__")[s_field.value]
      end
    end
  end
  Traject::MarcExtractor.cached('87603ahjptxz').collect_matching_lines(record) do |field, _spec, _extractor|
    col_group = ''
    field.subfields.each do |s_field|
      if s_field.code == 'x'
        if s_field.value == 'Shared'
          col_group = 'S'
        elsif s_field.value == 'Private'
          col_group = 'P'
        else
          col_group = 'O'
        end
      end
    end
    if partner_lib == 'scsbnypl'
      partner_display_string = 'N'
    elsif partner_lib == 'scsbcul'
      partner_display_string = 'C'
    end
    item_notes << "#{partner_display_string} - #{col_group}"
  end
  item_notes
end

def find_hathi_by_oclc(oclc)
  return if ENV["RUN_HATHI_COMPARE"].blank?
  output_dir = ENV['HATHI_OUTPUT_DIR']
  if output_dir.blank?
    puts "The output directory must be set for Hathi comparison to work!!! ENV['HATHI_OUTPUT_DIR']"
    return ""
  end
  overlap_file = Dir.glob("#{output_dir}/overlap*final.tsv").sort_by { |filename| filename.to_date.strftime }.last
  if overlap_file.blank?
    puts "The overlap file is missing from #{output_dir}!!"
    return ""
  end
  oclc_hathi = `grep "^#{oclc}\t" #{overlap_file}`
end

# "980\t1590302\tmono\tdeny\tic\tmdp.39015002162876\n980\t1590302\tmono\tdeny\tic\tmdp.39015010651894\n980\t1590302\tmono\tdeny\tic\tmdp.39015066013585\n"
def parse_locations_from_hathi_line(line)
  return [] if line.blank?
  access = line.split("\t")[3]
  locs = ["hathi"]
  locs << "hathi_temp" if access == "deny"
  locs
end

def parse_hathi_identifer_from_hathi_line(line)
  return "" if line.blank?
  [line.split("\n").first.split("\t")[5]]
end
