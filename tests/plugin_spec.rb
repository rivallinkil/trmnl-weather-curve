# frozen_string_literal: true

# This plugin's tests, run with `trmnlp test` (add `--report report` for a page of every screen it drew).
# Docs: https://github.com/usetrmnl/trmnlp#testing-plugins
RSpec.describe 'Weather Curve (DWD)' do
  def fixture(name) = JSON.parse(File.read(File.join(__dir__, 'fixtures', name)))

  # Real responses: Bright Sky for Berlin, 2026-10-09; Open-Meteo for New York, 2026-10-19.
  let(:brightsky) { fixture('brightsky.json') }
  let(:open_meteo) { fixture('open-meteo.json') }
  let(:mocks) do
    { 'https://api.brightsky.dev/*' => { json: brightsky }, 'https://api.open-meteo.com/*' => { json: open_meteo } }
  end

  let(:custom_fields) { { 'lat_lon' => '52.5200,13.4050' } }

  # Every view on TRMNL's devices, a failing API and every select option, checked for page errors and leaked values.
  it_behaves_like 'a publishable recipe'

  def requested_hosts(fields)
    trmnl.transform(mocks:, custom_fields: fields).requests.map { URI(it[:url]).host }.uniq
  end

  describe 'data source' do
    it 'asks the DWD in Europe when Auto (and when never set)' do
      expect(requested_hosts('lat_lon' => '48.1351,11.5820')).to eq(['api.brightsky.dev'])
      expect(requested_hosts('lat_lon' => '48.1351,11.5820', 'data_source' => 'auto')).to eq(['api.brightsky.dev'])
    end

    it 'asks Open-Meteo outside Europe when Auto' do
      expect(requested_hosts('lat_lon' => '40.7128,-74.0060')).to eq(['api.open-meteo.com'])
      expect(requested_hosts('lat_lon' => '64.1466,-21.9426')).to eq(['api.open-meteo.com']) # Reykjavik
    end

    it 'follows an explicit choice anywhere' do
      expect(requested_hosts('lat_lon' => '40.7128,-74.0060', 'data_source' => 'dwd')).to eq(['api.brightsky.dev'])
      expect(requested_hosts('lat_lon' => '48.1351,11.5820', 'data_source' => 'open-meteo')).to eq(['api.open-meteo.com'])
    end

    it "sends Open-Meteo the user's time zone and eight days" do
      url = trmnl.transform(mocks:, custom_fields: { 'lat_lon' => '40.7128,-74.0060' }).requests.first[:url]
      expect(url).to include('latitude=40.7128', 'longitude=-74.0060', 'forecast_days=8', 'timezone=Europe%2FBerlin')
    end

    it 'sends Bright Sky the same location and an 8-day window' do
      url = trmnl.transform(mocks:, custom_fields: { 'lat_lon' => '48.1351,11.5820' }).requests.first[:url]
      expect(url).to include('lat=48.1351', 'lon=11.5820', 'tz=Europe%2FBerlin', 'date=', 'last_date=')
    end
  end

  # New York on Open-Meteo: every view, both source labels, the 7-day curve.
  context 'with Open-Meteo (New York)' do
    let(:custom_fields) { { 'lat_lon' => '40.7128,-74.0060' } }

    it 'condenses to the same 7-day shape' do
      data = trmnl.transform(mocks:, custom_fields:).data
      expect(data['days'].size).to eq(7)
      expect(data['source']).to eq('open-meteo')
    end

    %w[full half_horizontal half_vertical quadrant].each do |view|
      it "draws the #{view} view with the Open-Meteo credit" do
        screen = trmnl.render(view:, device: 'og_plus', mocks:, custom_fields:)
        expect(screen).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
        expect(screen.text).to include('Open-Meteo')
      end
    end

    it 'draws the portrait list and column designs' do
      %w[og_plus v2].each do |device|
        screen = trmnl.render(view: 'half_vertical', device:, orientation: :portrait, mocks:, custom_fields:)
        expect(screen).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
      end
    end
  end

  # A DWD station outside Europe has no rain fields at all: no rain is drawn, and no "0 %".
  context 'with a forecast without rain data' do
    let(:brightsky) do
      fixture('brightsky.json').tap do |data|
        data['weather'].each { it.merge!('precipitation' => nil, 'precipitation_probability' => nil, 'precipitation_probability_6h' => nil) }
      end
    end
    let(:custom_fields) { { 'lat_lon' => '52.5200,13.4050', 'data_source' => 'dwd' } }

    it 'reports no chance of rain' do
      days = trmnl.transform(mocks:, custom_fields:).data['days']
      expect(days.map { it['rain'] }.uniq).to eq([nil])
    end

    %w[full half_horizontal half_vertical quadrant].each do |view|
      it "draws the #{view} view without rain" do
        screen = trmnl.render(view:, device: 'og_plus', mocks:, custom_fields:)
        expect(screen).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
        expect(screen.text).not_to match(/REGEN|RAIN|chance of rain|null/i)
      end
    end

    it 'draws the portrait list and column designs without rain' do
      %w[og_plus v2].each do |device|
        screen = trmnl.render(view: 'half_vertical', device:, orientation: :portrait, mocks:, custom_fields:)
        expect(screen).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
        expect(screen.text).not_to match(/null|NaN/)
      end
    end
  end
end
