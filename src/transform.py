"""
Condenses hourly forecast data (~190 rows) into 7 daily rows.

Input: the polled response of either source, told apart by its shape:
  Bright Sky (DWD)  {weather: [...], sources: [...]}
  Open-Meteo        {hourly: {time: [...], ...}, current: {...}, utc_offset_seconds: ...}
Output: the same for both. Language- and unit-neutral data (°C, unrounded; weekday as 0 = Monday);
the views translate labels and convert units. A day without any rain data has rain: None.
"""
from collections import Counter
from datetime import datetime, timezone

DAYS = 7
# Daytime hours used to pick a day's icon.
DAY_HOURS = range(7, 20)
# WMO weather code (Open-Meteo) -> Bright Sky icon name.
WMO_ICONS = {
    0: "clear", 1: "clear", 2: "partly-cloudy", 3: "cloudy",
    45: "fog", 48: "fog",
    51: "rain", 53: "rain", 55: "rain", 56: "sleet", 57: "sleet",
    61: "rain", 63: "rain", 65: "rain", 66: "sleet", 67: "sleet",
    71: "snow", 73: "snow", 75: "snow", 77: "snow",
    80: "rain", 81: "rain", 82: "rain", 85: "snow", 86: "snow",
    95: "thunderstorm", 96: "thunderstorm", 99: "thunderstorm",
}
# Icons that win over the most common one when they occur for 2+ daytime hours.
SEVERE = ["thunderstorm", "hail", "snow", "sleet"]


def day_icon(hours):
    icons = [(w.get("icon") or "").replace("-night", "-day") for w in hours]
    icons = [i for i in icons if i]
    if not icons:
        return "cloudy"
    counts = Counter(icons)
    for icon in SEVERE:
        if counts[icon] >= 2:
            return icon
    if counts["rain"] >= 4:
        return "rain"
    base = counts.most_common(1)[0][0]
    wet = sum(1 for w in hours if (w.get("precipitation") or 0) >= 0.1)
    if wet >= 2:
        return "partly-cloudy-rain" if base in ("partly-cloudy-day", "clear-day") else "rain"
    return base


def rnd1(value):
    return None if value is None else round(value, 1)


def wmo_icon(code, is_day):
    icon = WMO_ICONS.get(code, "cloudy")
    return icon + ("-day" if is_day else "-night") if icon in ("clear", "partly-cloudy") else icon


def rows_brightsky(input):
    rows = []
    for w in input.get("weather", []):
        if not w.get("timestamp"):
            continue
        rows.append({
            "_t": datetime.fromisoformat(w["timestamp"]),
            "timestamp": w["timestamp"],
            "temperature": w.get("temperature"),
            "icon": w.get("icon"),
            "precipitation": w.get("precipitation"),
            "probs": [w[k] for k in ("precipitation_probability", "precipitation_probability_6h") if w.get(k) is not None],
        })
    # The hourly record closest to now.
    now_utc = datetime.now(timezone.utc)
    current = min(rows, key=lambda r: abs(r["_t"] - now_utc)) if rows else None
    forecast = next((s for s in input.get("sources", []) if s.get("observation_type") == "forecast"), {})
    station = (forecast.get("station_name") or "").title()
    now = {"temp": rnd1(current["temperature"]), "icon": current["icon"] or "cloudy", "t": current["_t"],
           "updated": current["timestamp"]} if current else None
    return rows, now, station


def rows_open_meteo(input):
    h = input.get("hourly") or {}
    times = h.get("time") or []

    def col(name, i):
        values = h.get(name) or []
        return values[i] if i < len(values) else None

    rows = []
    for i, ts in enumerate(times):
        prob = col("precipitation_probability", i)
        rows.append({
            "_t": datetime.fromisoformat(ts),
            "timestamp": ts,
            "temperature": col("temperature_2m", i),
            "icon": wmo_icon(col("weather_code", i), col("is_day", i) != 0),
            "precipitation": col("precipitation", i),
            "probs": [] if prob is None else [prob],
        })

    # Local time without offset ("2026-10-19T11:15"); the offset comes from the response.
    cur = input.get("current") or {}
    offset = int(input.get("utc_offset_seconds") or 0)
    sign = "+" if offset >= 0 else "-"
    zone = "%s%02d:%02d" % (sign, abs(offset) // 3600, abs(offset) // 60 % 60)
    now = None
    if cur.get("time"):
        t = datetime.fromisoformat(cur["time"])
        icon = wmo_icon(cur.get("weather_code"), cur.get("is_day") != 0)
        # Same shape as Bright Sky's "updated": the current hour, local time with offset.
        now = {"temp": rnd1(cur.get("temperature_2m")), "icon": icon, "t": t,
               "updated": t.strftime("%Y-%m-%dT%H:00:00") + zone}
    elif rows:
        r = rows[0]
        now = {"temp": rnd1(r["temperature"]), "icon": r["icon"], "t": r["_t"], "updated": r["timestamp"] + ":00" + zone}
    return rows, now, ""


def run(input):
    if isinstance(input.get("hourly"), dict):
        source = "open-meteo"
        rows, now, station = rows_open_meteo(input)
    else:
        source = "dwd"
        rows, now, station = rows_brightsky(input)

    by_date = {}
    for w in rows:
        by_date.setdefault(w["_t"].date(), []).append(w)

    # Full days only (skips the trailing partial day). Start at local today when a week follows it;
    # otherwise (canned test data that has aged) start at the data's first day.
    full = sorted(d for d in by_date if len(by_date[d]) >= 12)
    today = now["t"].date() if now else None
    ahead = [d for d in full if today and d >= today]
    dates = ahead if len(ahead) >= DAYS else full

    days = []
    for d in dates:
        ws = by_date[d]
        temps = [w["temperature"] for w in ws if w.get("temperature") is not None]
        probs = [p for w in ws for p in w["probs"]]
        days.append({
            "date": d.isoformat(),
            "weekday": d.weekday(),
            "day": d.day,
            "month": d.month,
            "high": rnd1(max(temps)) if temps else None,
            "low": rnd1(min(temps)) if temps else None,
            # None: the source has no rain forecast for this day (the views then draw no rain).
            "rain": max(probs) if probs else None,
            "icon": day_icon([w for w in ws if w["_t"].hour in DAY_HOURS]),
        })
        if len(days) == DAYS:
            break

    return {
        "days": days,
        "now": {
            "temp": now["temp"] if now else None,
            "icon": now["icon"] if now else "cloudy",
        },
        "station": station,
        "source": source,
        # Local time of the current record, e.g. "2026-10-09T10:00:00+02:00".
        "updated": now["updated"] if now else "",
    }
