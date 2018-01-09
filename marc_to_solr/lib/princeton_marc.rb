# encoding: UTF-8
require 'library_stdnums'
require 'uri'

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
        d = self['008'].value[7,4]
        d = d.gsub 'u', '0' unless d == 'uuuu'
        d = d.gsub ' ', '0' unless d == '    '
        d if d =~ /^[0-9]{4}$/
      end
    end

    def end_date_from_008
      if self['008']
        d = self['008'].value[11,4]
        d = d.gsub 'u', '0' unless d == 'uuuu'
        d = d.gsub ' ', '0' unless d == '    '
        d if d =~ /^[0-9]{4}$/
      end
    end

    def date_display
      date = nil
      if self['260']
        if self['260']['c']
          date = self['260']['c']
        end
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
  key = subfield_value.capitalize.gsub(/[[:punct:]]?$/,'')
  key.empty? ? fallback : key
end

def standard_no_hash record
  standard_no = {}
  Traject::MarcExtractor.cached('024').collect_matching_lines(record) do |field, spec, extractor|
    standard_label = map_024_indicators_to_labels(field.indicator1)
    standard_number = nil
    field.subfields.each do |s_field|
      standard_number = s_field.value if s_field.code == 'a'
      standard_label = subfield_specified_hash_key(s_field.value, FALLBACK_STANDARD_NO) if s_field.code == '2' and standard_label == '$2'
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
  Traject::MarcExtractor.cached('020az:022alyz:035a:776wxz:787w').collect_matching_lines(record) do |field, spec, extractor|
    field.subfields.each do |s_field|
      linked_nums << StdNum::ISBN.normalize(s_field.value) if (field.tag == "020") or (field.tag == "776" and s_field.code == 'z')
      linked_nums << StdNum::ISSN.normalize(s_field.value) if (field.tag == "022") or (field.tag == "776" and s_field.code == 'x')
      linked_nums << oclc_normalize(s_field.value, prefix: true) if s_field.value.start_with?('(OCoLC)') and (field.tag == "035")
      if (field.tag == "776" and s_field.code == 'w') or (field.tag == "787" and s_field.code == 'w')
        linked_nums << oclc_normalize(s_field.value, prefix: true) if s_field.value.include?('(OCoLC)')
        linked_nums << "BIB" + strip_non_numeric(s_field.value) unless s_field.value.include?('(')
        if s_field.value.include?('(') and !s_field.value.start_with?('(')
          logger.error "#{record['001']} - linked field formatting: #{s_field.value}"
        end
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
        remove << " #{s_field.value}" if after_t and spec.includes_subfield_code?(s_field.code)
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
      if /1../.match(field.tag)
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
  Traject::MarcExtractor.cached('260:264').collect_matching_lines(record) do |field, spec, extractor|
    a_pub_info = nil
    b_pub_info = nil
    pub_info = ""
    field.subfields.each do |s_field|
      a_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'a'
      b_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'b'
    end

    # Build publication info string and add to citation array.
    pub_info += a_pub_info unless a_pub_info.nil?
    pub_info += ": " if !a_pub_info.nil? and !b_pub_info.nil?
    pub_info += b_pub_info unless b_pub_info.nil?
    pub_citation << pub_info if !pub_info.empty?
  end
  pub_citation
end

##
# Process publication information for creation information
# @param [MARC::Record]
# @return [Array<String>]
def set_pub_created(record)
  value = []

  Traject::MarcExtractor.cached('260:264').collect_matching_lines(record) do |field, spec, extractor|
    a_pub_info = nil
    b_pub_info = nil
    c_pub_info = nil

    pub_info = ""

    field.subfields.each do |s_field|
      a_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'a'
      b_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'b'
      c_pub_info = Traject::Macros::Marc21.trim_punctuation(s_field.value).strip if s_field.code == 'c'
    end

    # Build the string
    pub_info += a_pub_info unless a_pub_info.nil?

    pub_info += ": " unless a_pub_info.nil? && b_pub_info.nil?
    pub_info += b_pub_info unless b_pub_info.nil?

    pub_info += ', ' unless pub_info.nil? || c_pub_info.nil?
    pub_info += c_pub_info unless c_pub_info.nil?

    # Append the terminal publication date
    terminal_pub_date = record.end_date_from_008 if !c_pub_info.nil? && /\d{4}\-$/.match(c_pub_info) 
    pub_info += terminal_pub_date if terminal_pub_date

    value << pub_info unless pub_info.empty?
  end
  value
end

SEPARATOR = '—'

# for the hierarchical subject display and facet
# split with em dash along v,x,y,z
def process_subject_facet record, fields
  subjects = []
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, extractor|
    subject = extractor.collect_subfields(field, spec).first
    unless subject.nil?
      field.subfields.each do |s_field|
        if (s_field.code == 'v' || s_field.code == 'x' || s_field.code == 'y' || s_field.code == 'z')
          subject = subject.gsub(" #{s_field.value}", "#{SEPARATOR}#{s_field.value}")
        end
      end
      subject = subject.split(SEPARATOR)
      subject = subject.map{ |s| Traject::Macros::Marc21.trim_punctuation(s) }.join(SEPARATOR)
      subjects << subject
    end
  end
  subjects
end

# for the split subject facet
# split with em dash along x,z
def process_subject_topic_facet record
  subjects = []
  Traject::MarcExtractor.cached('600|*0|abcdfklmnopqrtxz:610|*0|abfklmnoprstxz:611|*0|abcdefgklnpqstxz:630|*0|adfgklmnoprstxz:650|*0|abcxz:651|*0|axz').collect_matching_lines(record) do |field, spec, extractor|
    subject = extractor.collect_subfields(field, spec).first
    unless subject.nil?
      field.subfields.each do |s_field|
        if (s_field.code == 'x' || s_field.code == 'z')
          subject = subject.gsub(" #{s_field.value}", "#{SEPARATOR}#{s_field.value}")
        end
      end
      subject = subject.split(SEPARATOR)
      subjects << subject.map { |s| Traject::Macros::Marc21.trim_punctuation(s) }
    end
  end
  subjects.flatten
end

def strip_non_numeric num_str
  num_str.gsub(/\D/, '').to_i.to_s
end

def oclc_normalize oclc, opts = {prefix: false}
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

# returns hash of links ($u) (key),
# anchor text ($y, $3, hostname), and additional labels ($z) (array value)
def electronic_access_links record
  links = {}
  holding_856s = {}
  Traject::MarcExtractor.cached('856').collect_matching_lines(record) do |field, spec, extractor|
    anchor_text = false
    z_label = false
    url = false
    holding_id = nil
    field.subfields.each do |s_field|
      holding_id = s_field.value if s_field.code == '0'
      url = s_field.value if s_field.code == 'u'
      z_label = s_field.value if s_field.code == 'z'
      if s_field.code == 'y' || s_field.code == '3' || s_field.code == 'x'
        if anchor_text
          anchor_text << ": #{s_field.value}"
        else
          anchor_text = s_field.value
        end
      end
    end
    if url and (URI.parse(url) rescue nil)
      anchor_text = URI.parse(url).host unless anchor_text
      url_labels = [anchor_text] # anchor text is first element
      url_labels << z_label if z_label # optional 2nd element if z
      holding_id.nil? ? links[url] = url_labels : holding_856s[holding_id] = {url => url_labels}
    else
      logger.error "#{record['001']} - no url in 856 field"
    end
  end
  links['holding_record_856s'] = holding_856s unless holding_856s == {}
  links
end

def remove_parens_035 standard_no
  standard_no.gsub(/^\(.*?\)/,'')
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
  Traject::MarcExtractor.cached('600|*0|v:610|*0|v:611|*0|v:630|*0|v:650|*0|v:651|*0|v:655|*0|a:655|*0|v').collect_matching_lines(record) do |field, spec, extractor|
    genre = extractor.collect_subfields(field, spec).first
    unless genre.nil?
      genre = Traject::Macros::Marc21.trim_punctuation(genre)
      if genre.match(/^\s+$/)
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
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, extractor|
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
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, extractor|
    non_t = true
    title = []
    field.subfields.each do |s_field|
      title << s_field.value
      if s_field.code == 't'
        non_t = false
        break
      end
    end
    values << Traject::Macros::Marc21.trim_punctuation(title.join(' ')) unless (title.empty? or non_t)
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
  Traject::MarcExtractor.cached(fields).collect_matching_lines(record) do |field, spec, extractor|
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
  fields.collect { |h| h.collect.with_index { |v, i| Traject::Macros::Marc21.trim_punctuation(h[0..i].join(' ')) } }
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
def process_holdings record
  all_holdings = {}
  Traject::MarcExtractor.cached('852').collect_matching_lines(record) do |field, spec, extractor|
    holding = {}
    holding_id = nil
    field.subfields.each do |s_field|
      if s_field.code == '0'
        holding_id = s_field.value
      elsif s_field.code == 'b'
        ## Location and Library aren't loading correctly with SCSB Records
        holding['location'] ||= Traject::TranslationMap.new("locations", :default => "__passthrough__")[s_field.value]
        holding['library'] ||= Traject::TranslationMap.new("location_display", :default => "__passthrough__")[s_field.value]
        holding['location_code'] ||= s_field.value
      elsif /[ckhij]/.match(s_field.code)
        holding['call_number'] ||= []
        holding['call_number'] << s_field.value
        unless s_field.code == 'c'
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
    all_holdings[holding_id] = holding unless holding_id.nil?
  end
  Traject::MarcExtractor.cached('866az').collect_matching_lines(record) do |field, spec, extractor|
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
    if (all_holdings[holding_id] and !value.empty?)
      all_holdings[holding_id]['location_has'] ||= []
      all_holdings[holding_id]['location_has'] << value.join(' ')
    end
  end
  Traject::MarcExtractor.cached('8670az').collect_matching_lines(record) do |field, spec, extractor|
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
    if (all_holdings[holding_id] and !value.empty?)
      all_holdings[holding_id]['supplements'] ||= []
      all_holdings[holding_id]['supplements'] << value.join(' ')
    end
  end
  Traject::MarcExtractor.cached('8680az').collect_matching_lines(record) do |field, spec, extractor|
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
    if (all_holdings[holding_id] and !value.empty?)
      all_holdings[holding_id]['indexes'] ||= []
      all_holdings[holding_id]['indexes'] << value.join(' ')
    end
  end
  ### Added for ReCAP records
  Traject::MarcExtractor.cached('87603ahjptxz').collect_matching_lines(record) do |field, spec, extractor|
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
      all_holdings[item[:holding_id]]["items"] = [ item ]
    else
      all_holdings[item[:holding_id]]["items"] << item
    end
  end
  all_holdings
end

def process_recap_notes record
  item_notes = []
  partner_lib = nil
  Traject::MarcExtractor.cached('852').collect_matching_lines(record) do |field, spec, extractor|
    field.subfields.each do |s_field|
      if s_field.code == 'b'
        partner_lib = s_field.value #||= Traject::TranslationMap.new("locations", :default => "__passthrough__")[s_field.value]
      end
    end
  end
  Traject::MarcExtractor.cached('87603ahjptxz').collect_matching_lines(record) do |field, spec, extractor|
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
