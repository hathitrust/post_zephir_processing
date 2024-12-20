module PostZephirProcessing
  shared_context "with hathifile database" do
    around(:each) do |example|
      Services[:database][:hf].truncate
      Services[:database][:hf_log].truncate
      example.run
      Services[:database][:hf].truncate
      Services[:database][:hf_log].truncate
    end

    # Temporarily add `hathifile` to `hf_log` with the current timestamp.
    def with_fake_hf_log_entry(hathifile:)
      Services[:database][:hf_log].insert(hathifile: hathifile)
      yield
    end

    # Temporarily add `htid` to `hf` with reasonable (and irrelevant) defaults.
    def with_fake_hf_entries(htids:)
      htids.each { |htid| Services[:database][:hf].insert(htid: htid) }
      yield
    end
  end
end
