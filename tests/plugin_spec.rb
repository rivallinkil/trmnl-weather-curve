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

  # French labels are the longest ("100 % de risque de pluie"): every view and orientation still fits.
  describe 'in French' do
    let(:custom_fields) { { 'lat_lon' => '52.5200,13.4050', 'language' => 'fr', 'show_uv' => 'true' } }

    %w[full half_horizontal half_vertical quadrant].each do |view|
      it "draws the #{view} view" do
        %w[og_plus v2].each do |device|
          [nil, :portrait].each do |orientation|
            args = { view:, device:, mocks:, custom_fields: }
            args[:orientation] = orientation if orientation
            screen = trmnl.render(**args)
            expect(screen).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
            expect(screen.text).to match(/MAX|Lun|Mar|Mer|Jeu|Ven|Sam|Dim/)
          end
        end
      end
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

  # Optional UV index (show_uv): Open-Meteo only, so in Europe it is a second, small request.
  describe 'UV index' do
    let(:open_meteo_uv) { fixture('open-meteo-with-uv.json') } # the New York forecast plus daily=uv_index_max
    let(:uv_only) { fixture('open-meteo-uv.json') }            # the answer to the DWD's second request
    # Open-Meteo answers by what is asked: the UV-only request (no hourly) or the forecast.
    let(:uv_mocks) do
      forecast = ->(request) { { json: request[:url].include?('hourly=') ? open_meteo_uv : uv_only } }
      { 'https://api.brightsky.dev/*' => { json: brightsky }, 'https://api.open-meteo.com/*' => forecast }
    end
    let(:berlin) { { 'lat_lon' => '52.5200,13.4050' } }
    let(:new_york) { { 'lat_lon' => '40.7128,-74.0060' } }
    let(:forecast_url) do
      'https://api.open-meteo.com/v1/forecast?latitude=40.7128&longitude=-74.0060&hourly=temperature_2m,' \
        'precipitation_probability,precipitation,weather_code,is_day&current=temperature_2m,weather_code,is_day' \
        '&timezone=Europe%2FBerlin&forecast_days=8'
    end

    it 'leaves both URLs exactly as before when off, or never set' do
      [{}, { 'show_uv' => 'false' }, { 'show_uv' => '' }].each do |extra|
        urls = trmnl.transform(mocks:, custom_fields: new_york.merge(extra)).requests.map { it[:url] }
        expect(urls).to eq([forecast_url])

        urls = trmnl.transform(mocks:, custom_fields: berlin.merge(extra)).requests.map { it[:url] }
        expect(urls.size).to eq(1)
        expect(urls.first).to match(
          %r{\Ahttps://api\.brightsky\.dev/weather\?lat=52\.5200&lon=13\.4050&tz=Europe%2FBerlin&date=[\d-]+&last_date=[\d-]+\z}
        )
      end
    end

    it 'adds daily=uv_index_max to the single Open-Meteo request' do
      urls = trmnl.transform(mocks: uv_mocks, custom_fields: new_york.merge('show_uv' => 'true')).requests.map { it[:url] }
      expect(urls).to eq(["#{forecast_url}&daily=uv_index_max"])
    end

    it 'asks Open-Meteo for the UV index only, after the DWD' do
      urls = trmnl.transform(mocks: uv_mocks, custom_fields: berlin.merge('show_uv' => 'true')).requests.map { it[:url] }
      expect(urls.size).to eq(2)
      expect(urls.first).to start_with('https://api.brightsky.dev/weather?')
      expect(urls.last).to eq('https://api.open-meteo.com/v1/forecast?latitude=52.5200&longitude=13.4050' \
                              '&daily=uv_index_max&timezone=Europe%2FBerlin&forecast_days=8')
    end

    it 'rounds the UV index per day with Open-Meteo' do
      data = trmnl.transform(mocks: uv_mocks, custom_fields: new_york.merge('show_uv' => 'true')).data
      expect(data['source']).to eq('open-meteo')
      expect(data['days'].first(3).map { [it['date'], it['uv']] }).to eq([['2026-10-19', 4], ['2026-10-20', 5], ['2026-10-21', 1]])
    end

    it 'matches the DWD days with the UV index of the same date' do
      data = trmnl.transform(mocks: uv_mocks, custom_fields: berlin.merge('show_uv' => 'true')).data
      expect(data['source']).to eq('dwd')
      expect(data['days'].size).to eq(7)
      expect(data['days'].first(3).map { [it['date'], it['uv']] }).to eq([['2026-10-09', 3], ['2026-10-10', 4], ['2026-10-11', 6]])
    end

    it 'has no UV index (and still a forecast) when the second request fails' do
      failing = uv_mocks.merge('https://api.open-meteo.com/*' => { status: 500, body: 'down' })
      data = trmnl.transform(mocks: failing, custom_fields: berlin.merge('show_uv' => 'true')).data
      expect(data['days'].size).to eq(7)
      expect(data['days'].map { it['uv'] }.uniq).to eq([nil])
    end

    it 'has no UV index without show_uv (the DWD has none)' do
      expect(trmnl.transform(mocks:, custom_fields: berlin).data['days'].map { it['uv'] }.uniq).to eq([nil])
    end

    %w[full half_horizontal half_vertical quadrant].each do |view|
      it "draws the #{view} view with UV from either source, only when it is on" do
        [new_york, berlin].each do |fields|
          on = trmnl.render(view:, device: 'og_plus', mocks: uv_mocks, custom_fields: fields.merge('show_uv' => 'true'))
          expect(on).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
          expect(on.text).not_to match(/null|NaN/)
          off = trmnl.render(view:, device: 'og_plus', mocks: uv_mocks, custom_fields: fields)
          expect(off.text).not_to match(/UV\d/)
        end
      end
    end

    it 'shows UV in the designs with a stats block, in every language' do
      %w[en de fr].each do |language|
        fields = berlin.merge('show_uv' => 'true', 'language' => language)
        %w[full half_vertical quadrant].each do |view|
          expect(trmnl.render(view:, device: 'og_plus', mocks: uv_mocks, custom_fields: fields).text).to match(/UV\d/)
        end
      end
    end

    it 'draws the TRMNL X and portrait designs with UV' do
      %w[og_plus v2].each do |device|
        [nil, :portrait].each do |orientation|
          %w[full half_vertical].each do |view|
            args = { view:, device:, mocks: uv_mocks, custom_fields: berlin.merge('show_uv' => 'true') }
            args[:orientation] = orientation if orientation
            expect(trmnl.render(**args)).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
          end
        end
      end
    end

    [0.0, 1.0, 2.0].each do |index|
      it "shows UV at index #{index.to_i}, below 3" do
        low = uv_only.merge('daily' => uv_only['daily'].merge('uv_index_max' => [index] * 18))
        mocks = uv_mocks.merge('https://api.open-meteo.com/*' => { json: low })
        screen = trmnl.render(view: 'full', device: 'og_plus', mocks:, custom_fields: berlin.merge('show_uv' => 'true'))
        expect(screen.text).to match(/UV#{index.to_i}/)
      end
    end

    it 'shows no UV when the UV request failed (uv is null)' do
      failing = uv_mocks.merge('https://api.open-meteo.com/*' => { status: 500, body: 'down' })
      screen = trmnl.render(view: 'full', device: 'og_plus', mocks: failing, custom_fields: berlin.merge('show_uv' => 'true'))
      expect(screen.text).not_to match(/UV\d/)
    end
  end

  # Optional wind (show_wind): Bright Sky always sends it, Open-Meteo only when asked.
  describe 'wind' do
    let(:berlin) { { 'lat_lon' => '52.5200,13.4050' } }
    let(:new_york) { { 'lat_lon' => '40.7128,-74.0060' } }

    it 'asks Open-Meteo for the wind speed only when on' do
      url = trmnl.transform(mocks:, custom_fields: new_york.merge('show_wind' => 'true')).requests.first[:url]
      expect(url).to include('is_day,wind_speed_10m&current=temperature_2m,weather_code,is_day,wind_speed_10m&')
      url = trmnl.transform(mocks:, custom_fields: new_york).requests.first[:url]
      expect(url).not_to include('wind')
    end

    it 'reads the current wind speed from the DWD' do
      expect(trmnl.transform(mocks:, custom_fields: berlin).data['now']['wind']).to be_a(Numeric)
    end

    it 'draws the wind in the full view only when on, in km/h or mph' do
      on = trmnl.render(view: 'full', device: 'og_plus', mocks:, custom_fields: berlin.merge('show_wind' => 'true'))
      expect(on).to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
      expect(on.text).to match(/\d+ km\/h/)
      fahrenheit = berlin.merge('show_wind' => 'true', 'units' => 'fahrenheit')
      expect(trmnl.render(view: 'full', device: 'og_plus', mocks:, custom_fields: fahrenheit).text).to match(/\d+ mph/)
      expect(trmnl.render(view: 'full', device: 'og_plus', mocks:, custom_fields: berlin).text).not_to match(/km\/h/)
    end

    it 'draws no wind when Open-Meteo sent none' do
      screen = trmnl.render(view: 'full', device: 'og_plus', mocks:, custom_fields: new_york.merge('show_wind' => 'true'))
      expect(screen).to have_no_problems
      expect(screen.text).not_to match(/km\/h|null|NaN/)
    end

    it 'draws the TRMNL X design with wind and UV' do
      fields = berlin.merge('show_wind' => 'true', 'show_uv' => 'true', 'language' => 'fr')
      expect(trmnl.render(view: 'full', device: 'v2', mocks:, custom_fields: fields))
        .to have_no_problems.and(have_no_leaked_text).and(have_no_overlapping_text)
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
        expect(screen.text).not_to match(/REGEN|RAIN|PLUIE|chance of rain|null/i)
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
