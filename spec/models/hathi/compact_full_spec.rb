require 'rails_helper'

RSpec.describe Hathi::CompactFull do
  describe '#compact_full' do
    
    let(:hathi_directory) { File.expand_path('../../../fixtures/', __FILE__)}
    let(:hathi_output) { File.expand_path('../../../../tmp', __FILE__)}
    let(:compact_file) {File.join(hathi_output, 'hathi_full_20200501_compacted.tsv')}
    
    it 'compacts the full hathi file' do
      original_outputdir = ENV['HATHI_OUTPUT_DIR']
      original_inputdir = ENV['HATHI_OUTPUT_DIR']
      ENV['HATHI_INPUT_DIR'] = hathi_directory
      ENV['HATHI_OUTPUT_DIR'] = hathi_output
      described_class.compact_full
      output_file = File.open(compact_file)
      expect(output_file.read).to eq("identifier\toclc\n"\
                                     "mdp.39015018415946\t2779601\n"\
                                     "mdp.39015066356547\t2779601\n"\
                                     "mdp.39015066356406\t2779601\n"\
                                     "mdp.39015066356695\t2779601\n"\
                                     "mdp.39015066356554\t2779601\n"\
                                     "uc1.$b759626\t2779601\n"\
                                     "uc1.$b759627\t2779601\n"\
                                     "uc1.$b759628\t2779601\n"\
                                     "mdp.39015033913115\t23536349\n"\
                                     "mdp.39015061455294\t60561774\n"\
                                     "mdp.39015069868340\t214394419\n"\
                                     "mdp.39015069868340\t28015\n")
      File.delete(output_file.path)
      ENV['HATHI_INPUT_DIR'] = original_inputdir
      ENV['HATHI_OUTPUT_DIR'] = original_outputdir
    end
  end
end
