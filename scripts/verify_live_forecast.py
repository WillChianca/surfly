"""Read-only Open-Meteo integration probe. Never supplies data to the production app.

Uses beach coordinates and requested variables from the Swift sources, verifies real
responses, and stores the exact public payloads in ignored tmp/forecast-verification/.
Run: python scripts/verify_live_forecast.py
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import re
from urllib.parse import urlencode
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tmp" / "forecast-verification"


def probe(beach):
    beach_id, latitude, longitude = beach
    fields = {
        "marine": "wave_height,wave_period,wave_direction,swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature",
        "weather": "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,is_day",
    }
    payloads = {}
    for kind in fields:
        marine = kind == "marine"
        base = "https://marine-api.open-meteo.com/v1/marine" if marine else "https://api.open-meteo.com/v1/forecast"
        query = dict(latitude=latitude, longitude=longitude, forecast_days=7,
                     timezone="auto", timeformat="unixtime", hourly=fields[kind])
        query.update(dict(cell_selection="sea") if marine else dict(wind_speed_unit="kmh", daily="sunset"))
        url = base + "?" + urlencode(query)
        with urlopen(url, timeout=35) as response:
            raw = response.read()
        data = json.loads(raw)
        (OUT / f"{beach_id}-{kind}.json").write_bytes(raw)
        times = data["hourly"]["time"]
        assert len(times) >= 7 * 24, (beach_id, kind, "short forecast", len(times))
        assert times == sorted(set(times)), (beach_id, kind, "unordered/duplicate timestamps")
        assert data.get("timezone") and data["timezone"] != "auto", "Provider must resolve the timezone"
        for field in fields[kind].split(","):
            assert len(data["hourly"][field]) == len(times), (beach_id, field, "misaligned array")
        units = data["hourly_units"]
        expected = {"wave_height": "m", "wave_period": "s", "sea_surface_temperature": "°C"} if marine else {
            "wind_speed_10m": "km/h", "wind_direction_10m": "°", "wind_gusts_10m": "km/h", "temperature_2m": "°C"}
        assert all(units.get(key) == value for key, value in expected.items()), (beach_id, units)
        payloads[kind] = data
    m, w = payloads["marine"], payloads["weather"]
    assert m["timezone"] == w["timezone"], (beach_id, "timezone mismatch")
    matching = set(m["hourly"]["time"]) & set(w["hourly"]["time"])
    assert len(matching) >= 168, (beach_id, "not enough matching hours")
    assert len(w["daily"]["sunset"]) == 7
    return {
        "beach": beach_id, "matching_hours": len(matching),
        "timezone": w["timezone"],
        "first_utc": datetime.fromtimestamp(min(matching), timezone.utc).isoformat(),
        "last_utc": datetime.fromtimestamp(max(matching), timezone.utc).isoformat(),
        "water_temperature_available_hours": sum(v is not None for v in m["hourly"]["sea_surface_temperature"]),
        "marine_grid": [m["latitude"], m["longitude"]], "status": "PASS",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--global-probes", action="store_true", help="Also test coastal coordinates east and west of UTC; these are test inputs, not app catalogue entries")
    args = parser.parse_args()
    source = (ROOT / "surfly" / "Models" / "Forecast.swift").read_text(encoding="utf-8")
    beaches = re.findall(r'\.init\(id: "([^"]+)"[^\n]*latitude: ([\d.-]+), longitude: ([\d.-]+)', source)
    assert len(beaches) == 5, "Expected the five documented catalogue beaches"
    if args.global_probes:
        beaches += [("sydney-coastal-probe", "-33.891", "151.277"), ("honolulu-coastal-probe", "21.27", "-157.84")]
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(probe, beaches))
    report = {"retrieved_at_utc": datetime.now(timezone.utc).isoformat(), "results": results}
    (OUT / "verification.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
