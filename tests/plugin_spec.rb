# frozen_string_literal: true

# This plugin's tests, run with `trmnlp test` (add `--report report` for a page of every screen it drew).
# Docs: https://github.com/usetrmnl/trmnlp#testing-plugins
RSpec.describe 'Weather Curve (DWD)' do
  # Real Bright Sky response for Berlin, 2026-10-09.
  let(:mocks) do
    { 'https://api.brightsky.dev/*' => { json: JSON.parse(File.read(File.join(__dir__, 'fixtures/brightsky.json'))) } }
  end

  let(:custom_fields) { { 'lat_lon' => '52.5200,13.4050' } }

  # Every view on TRMNL's devices, a failing API and every select option, checked for page errors and leaked values.
  it_behaves_like 'a publishable recipe'
end
