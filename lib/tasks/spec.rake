task("spec").clear
desc "Run rspec with required env variables"
task :spec do
  if Rails.env.development? || Rails.env.staging?
    ENV['FIGGY_ARK_CACHE_PATH'] = 'marc_to_solr/spec/fixtures/figgy_ark_cache'
    ENV['TRAJECT_CONFIG'] = 'marc_to_solr/lib/traject_config.rb'
    ENV['BIBDATA_ADMIN_NETIDS'] = 'admin123'
    ENV['HATHI_OUTPUT_DIR'] = 'marc_to_solr/spec/fixtures/'
    sh "rspec spec marc_to_solr/spec"
  end
end
