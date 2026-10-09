# Weather Curve (DWD)

A 7-day weather forecast for [TRMNL](https://trmnl.com) e-paper displays: one temperature curve for daily highs and lows, a weather icon per day, and the chance of rain as an area along the bottom.

![Full layout](docs/full.png)

| Portrait | TRMNL X | Half (vertical) |
|---|---|---|
| ![Portrait](docs/portrait.png) | ![TRMNL X](docs/trmnl-x.png) | ![Half vertical](docs/half_vertical.png) |

| Half (horizontal) | Quadrant |
|---|---|
| ![Half horizontal](docs/half_horizontal.png) | ![Quadrant](docs/quadrant.png) |

## Features

- 7-day temperature curve with daily highs and lows, weather icons and chance of rain
- Current temperature, today's high/low/rain and an outlook for tomorrow
- German or English labels (or follow the TRMNL account language)
- Celsius or Fahrenheit (Fahrenheit also switches to a 12-hour clock)
- Flat gray on grayscale screens, a dot pattern on black-and-white screens
- All four TRMNL layouts (full, half horizontal, half vertical, quadrant), adapting to portrait and to TRMNL X

## Data

Forecasts come from the [Deutscher Wetterdienst (DWD)](https://www.dwd.de) MOSMIX model, served by the free [Bright Sky](https://brightsky.dev) API. MOSMIX covers thousands of stations worldwide, so the plugin works outside Germany too. No account or API key is needed.

Data: Deutscher Wetterdienst, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), via Bright Sky. This project is not affiliated with or endorsed by the DWD.

## How it works

1. TRMNL polls Bright Sky hourly for the next 8 days of hourly data at the chosen location ([`src/settings.yml`](src/settings.yml)).
2. A serverless transform condenses about 190 hourly rows into 7 daily rows ([`src/transform.py`](src/transform.py)).
3. The views draw everything as one SVG per layout, in TRMNL's own Inter font ([`src/shared.liquid`](src/shared.liquid)).

## Development

Uses [trmnlp](https://github.com/usetrmnl/trmnlp) through Docker, no Ruby needed:

```sh
bin/trmnlp serve   # live preview at http://localhost:4567
bin/trmnlp lint
bin/trmnlp test
```

The preview uses Berlin. With the `trmnl_preview` gem installed, `TRMNL_LAT_LON="lat,lon"` overrides it without touching tracked files.

`bin/trmnlp login` and `bin/trmnlp push` upload the plugin to your TRMNL account.

## License

[MIT](LICENSE)
