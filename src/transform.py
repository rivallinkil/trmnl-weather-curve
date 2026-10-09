"""
Condenses Bright Sky's hourly DWD data (~190 rows) into 7 daily rows.

Input: the polled /weather response ({weather: [...], sources: [...]}).
Output: language- and unit-neutral data (°C, unrounded; weekday as 0 = Monday);
the views translate labels and convert units.
"""
from collections import Counter
from datetime import datetime, timezone

DAYS = 7
# Daytime hours used to pick a day's icon.
DAY_HOURS = range(7, 20)
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


def run(input):
    rows = [w for w in input.get("weather", []) if w.get("timestamp")]
    for w in rows:
        w["_t"] = datetime.fromisoformat(w["timestamp"])

    now_utc = datetime.now(timezone.utc)
    current = min(rows, key=lambda w: abs(w["_t"] - now_utc)) if rows else None

    by_date = {}
    for w in rows:
        by_date.setdefault(w["_t"].date(), []).append(w)

    # Start at local today; fall back to the first day in the data (e.g. canned test data).
    today = current["_t"].date() if current else None
    dates = sorted(d for d in by_date if today is None or d >= today) or sorted(by_date)

    days = []
    for d in dates:
        ws = by_date[d]
        if len(ws) < 12:  # skip the trailing partial day
            continue
        temps = [w["temperature"] for w in ws if w.get("temperature") is not None]
        probs = [w[k] for w in ws for k in ("precipitation_probability", "precipitation_probability_6h")
                 if w.get(k) is not None]
        days.append({
            "date": d.isoformat(),
            "weekday": d.weekday(),
            "day": d.day,
            "month": d.month,
            "high": rnd1(max(temps)) if temps else None,
            "low": rnd1(min(temps)) if temps else None,
            "rain": max(probs) if probs else 0,
            "icon": day_icon([w for w in ws if w["_t"].hour in DAY_HOURS]),
        })
        if len(days) == DAYS:
            break

    forecast = next((s for s in input.get("sources", []) if s.get("observation_type") == "forecast"), {})

    return {
        "days": days,
        "now": {
            "temp": rnd1(current.get("temperature")) if current else None,
            "icon": (current.get("icon") or "cloudy") if current else "cloudy",
        },
        "station": (forecast.get("station_name") or "").title(),
        # Local time of the current hourly record, e.g. "2026-10-09T10:00:00+02:00".
        "updated": current["timestamp"] if current else "",
    }
