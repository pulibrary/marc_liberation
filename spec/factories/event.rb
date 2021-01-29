FactoryBot.define do
  factory :event do
    start Time.now
    finish Time.now + 3600
    error nil
    success true
    created_at { finish }
    updated_at { finish }
  end

  factory :full_dump_type, class: "DumpType" do
    constant "ALL_RECORDS"
    label "All Records"
  end

  factory :incremental_dump_type, class: "DumpType" do
    constant "CHANGED_RECORDS"
    label "Changed Records"
  end

  factory :full_dump_file_type, class: "DumpFileType" do
    constant "BIB_RECORDS"
    label "All Bib Records"
  end

  factory :incremental_dump_file_type, class: "DumpFileType" do
    constant 'UPDATED_RECORDS'
    label 'Updated Records'
  end

  factory :dump_file do
    association :dump_file_type, factory: :full_dump_file_type
  end

  factory :incremental_dump_file, class: "DumpFile" do
    association :dump_file_type, factory: :incremental_dump_file_type
  end

  factory :empty_dump, class: "Dump" do
    association :dump_type, factory: :full_dump_type
  end

  factory :full_dump, class: "Dump" do
    association :dump_type, factory: :full_dump_type
    delete_ids []
    update_ids []
    dump_files do
      [
        association(:dump_file, path: 'spec/fixtures/files/alma/full_dump/1.xml.tar.gz'),
        association(:dump_file, path: 'spec/fixtures/files/alma/full_dump/2.xml.tar.gz')
      ]
    end
  end

  factory :incremental_dump, class: "Dump" do
    association :dump_type, factory: :incremental_dump_type
    delete_ids []
    update_ids []
    dump_files do
      [
        association(:incremental_dump_file, path: 'spec/fixtures/files/alma/full_dump/1.xml.tar.gz'),
        association(:incremental_dump_file, path: 'spec/fixtures/files/alma/full_dump/2.xml.tar.gz')
      ]
    end
  end

  factory :full_dump_event, class: "Event" do
    start Time.now - 3600
    finish Time.now - 100
    error nil
    success true
    created_at { finish }
    updated_at { finish }
    association :dump, factory: :full_dump
  end

  factory :incremental_dump_event, class: "Event" do
    start Time.now - 3600
    finish Time.now - 100
    error nil
    success true
    created_at { finish }
    updated_at { finish }
    association :dump, factory: :incremental_dump
  end
end
