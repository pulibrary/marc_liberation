# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

set :job_template, "bash -l -c 'export PATH=\"/usr/local/bin/:$PATH\" && :job'"

# USING CAPISTRANO ROLES
# a job with no roles will deploy to all servers
# otherwise use roles to say which server it should go to
# e.g. every 1.day, at: '2:00am', roles: [:cron_staging] do

# OUTPUT
# add an `output` key to your args hash to write to a file (examples below)

# ENVIRONMENT VARIABLES
# I've created custom job types when we need to use env vars that aren't
#   written into whenever (like mailto)

# populate the figgy ark cache
every 1.day, at: '3:00am' do
  rake "liberate:arks:clear_and_seed_cache"
end

# check voyager for updates 3 times per day in prod; 1nce per week in staging
every 1.day, at: ["10:10am", "2:10pm", "10:35pm"], roles: [:cron_production] do
  rake "marc_liberation:get_changes", output: "/tmp/cron_log.log"
end

every :sunday, at: "2:30am", roles: [:cron_staging] do
  rake "marc_liberation:get_changes", output: "/tmp/cron_log.log"
end

# proxy the liberate:latest task so we can set env vars
job_type :liberate_latest_staging, "cd :path && :environment_variable=:environment BIBDATA_URL=:bibdata_url SET_URL=:set_url UPDATE_LOCATIONS=:update_locations :bundle_command rake :task --silent :output"
job_type :liberate_latest_production, "cd :path && :environment_variable=:environment SET_URL=:set_url UPDATE_LOCATIONS=:update_locations :bundle_command rake :task --silent :output"

# 1 incremental update to catalog-staging per week, from voyager test
every :sunday, at: "5:15am", roles: [:cron_staging] do
  liberate_latest_staging(
    "liberate:latest",
    bibdata_url: "https://bibdata-staging.princeton.edu",
    set_url: ENV["SOLR_URL"],
    update_locations: "true",
    output: "/tmp/cron_log.log"
  )
end

# 3 updates to catalog-production per day
every 1.day, at: ["12:40am", "10:55am", "2:55pm"], roles: [:cron_production] do
  liberate_latest_production(
    "liberate:latest",
    set_url: ENV["SOLR_URL"],
    update_locations: "true",
    output: "/tmp/daily_updates.log"
  )
end

# 3 updates to catalog-rebuild per day on Solr staging cluster
every 1.day, at: ["1:00am", "11:30am", "3:30pm"], roles: [:cron_production] do
  liberate_latest_production(
    "liberate:latest",
    set_url: ENV["SOLR_REINDEX_URL"],
    update_locations: "true",
    output: "/tmp/daily_updates.log"
  )
end

# Daily racap / partner jobs
# every 1.day, at: "3:00pm", roles: [:cron_production] do
#   rake "marc_liberation:recap_dump", output: "/tmp/cron_log.log"
# end

# Daily recap shared collection update to Solr
every 1.day, at: "6:30am", roles: [:cron_production] do
  liberate_latest_production(
    "scsb:latest",
    set_url: ENV["SOLR_URL"],
    update_locations: "true",
    output: "/tmp/daily_updates.log"
  )
end

# Daily recap shared collection update to Solr staging cluster
every 1.day, at: "7:00am", roles: [:cron_production] do
  liberate_latest_production(
    "scsb:latest",
    set_url: ENV["SOLR_REINDEX_URL"],
    update_locations: "true",
    output: "/tmp/daily_updates.log"
  )
end
every 1.day, at: "6:00am", roles: [:cron_production] do
  rake "marc_liberation:partner_update", output: "/tmp/cron_log.log"
end

# process the access file daily at 10:30am Eastern (the machine is in Z time, which is why this is 2pm)
every 1.day, at: "2:30pm", roles: [:hr_cron] do
  rake "campus_access:load", output: "/tmp/campus_access_log.log"
end

# delete old events, dumps, and files on disk
every 1.week, roles: [:cron_staging, :cron_production] do
  rake "marc_liberation:delete:events"
end
