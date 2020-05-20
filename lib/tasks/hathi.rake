namespace :hathi do
  
  desc "compact hathi overlap report to only include files that overlap"
  task compact_overlap: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      Hathi::CompactOverlap.perform
      output_file = Hathi::CompactFull.get_hathi_file(ENV['HATHI_OUTPUT_DIR'],'overlap*compacted.tsv')
      sorted_file = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(output_file).gsub('.tsv','_sorted.tsv'))
      `sort -t$'\t' -k 1n #{output_file} > #{sorted_file}`
    else
      puts "Environment variable HATH_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end
  end

  desc 'Compact hathi_full file to only include the identifier and the oclc'
  task compact_full: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      Hathi::CompactFull.compact_full
      output_file = Hathi::CompactFull.get_hathi_file(ENV['HATHI_OUTPUT_DIR'],'hathi_full*compacted.tsv')
      sorted_file = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(output_file).gsub('.tsv','_sorted.tsv'))
      `sort -t$'\t' -k 2n #{output_file} > #{sorted_file}`
    else
      puts "Environment variable HATH_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end  
  end

  desc 'Combine Hathi_full and Hathi_overlap_compact files'
  task merge: :environment do
    if ENV['HATHI_INPUT_DIR'] && ENV['HATHI_OUTPUT_DIR'] 
      sorted_file1 = Hathi::CompactFull.get_hathi_file(ENV['HATHI_OUTPUT_DIR'],'overlap*sorted.tsv')
      sorted_file2 = Hathi::CompactFull.get_hathi_file(ENV['HATHI_OUTPUT_DIR'],'hathi_full*sorted.tsv')
      hathi_final = File.join(ENV['HATHI_OUTPUT_DIR'], File.basename(sorted_file1).gsub('.tsv','_final.tsv'))
      `join -t$'\t' -1 1 -2 2 #{sorted_file1} #{sorted_file2} > #{hathi_final}`
    else
      puts "Environment variable HATH_INPUT_DIR & HATHI_OUTPUT_DIR must be set!"
    end
  end  
end
