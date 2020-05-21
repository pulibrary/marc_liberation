require 'rails_helper'

RSpec.describe Hathi::CompactOverlap do
  it 'distributes an email message to staff when a request fails via the scsb_request queue' do
    input_dir = File.expand_path("../../../fixtures/", __FILE__)
    output_dir = File.expand_path("../../../../tmp/", __FILE__)
    overlap_file=File.expand_path("../../../fixtures/overlap.tsv", __FILE__)
    original_outputdir = ENV['HATHI_OUTPUT_DIR']
    original_inputdir = ENV['HATHI_OUTPUT_DIR']
    ENV['HATHI_INPUT_DIR'] = input_dir
    ENV['HATHI_OUTPUT_DIR'] = output_dir

    described_class.perform
    output_file = File.open(File.join(output_dir,'overlap_20200429_compacted.tsv')) 
    output_file.rewind
    expect(output_file.read).to eq("oclc\tlocal_id\titem_type\taccess\trights\n" \
                                   "32005963\t1000037\tmono\tdeny\tic\n" \
                                   "31088411\t1000038\tmono\tdeny\tic\n" \
                                   "685893\t1000040\tmono\tallow\tpdus\n" \
                                   "242778\t1000046\tmono\tdeny\tic\n")
    File.delete(output_file.path)
    ENV['HATHI_INPUT_DIR'] = original_inputdir
    ENV['HATHI_OUTPUT_DIR'] = original_outputdir
  end
end
