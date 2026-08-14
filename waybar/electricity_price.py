#!/usr/bin/env python3
"""Waybar custom module: current Finnish spot electricity price (c/kWh).

Source: api.spot-hinta.fi (same API used by ~/source/yaha2's electricity.js).
Output: JSON {text, tooltip, class} per waybar's custom module return-type.
"""
import json
import sys
from datetime import datetime, timedelta

import requests

JUST_NOW_URL = "https://api.spot-hinta.fi/JustNow"
TODAY_URL = "https://api.spot-hinta.fi/Today"
TIMEOUT_SECONDS = 10

# c/kWh thresholds for the "class" field, used by style.css to color the module.
CHEAP_MAX = 5.0
NORMAL_MAX = 15.0


def price_class(price):
    if price < CHEAP_MAX:
        return "cheap"
    if price < NORMAL_MAX:
        return "normal"
    return "expensive"


def fetch_price():
    now = requests.get(JUST_NOW_URL, timeout=TIMEOUT_SECONDS).json()
    now_price = float(now.get("PriceWithTax", 0)) * 100.0

    today = requests.get(TODAY_URL, timeout=TIMEOUT_SECONDS).json()
    hourly = [
        (row.get("DateTime", ""), float(row.get("PriceWithTax", 0)) * 100.0)
        for row in today
    ]

    return now_price, hourly


def main():
    try:
        now_price, hourly = fetch_price()
    except (requests.RequestException, ValueError, KeyError) as exc:
        print(json.dumps({
            "text": "N/A",
            "tooltip": f"Electricity price fetch failed: {exc}",
            "class": "error",
        }))
        return

    now = datetime.now().astimezone()
    upcoming = [
        (dt, price) for dt, price in hourly
        if datetime.fromisoformat(dt) + timedelta(minutes=15) > now
    ]
    tooltip_lines = [f"{dt[11:16]}  {price:.2f} c/kWh" for dt, price in upcoming]

    print(json.dumps({
        "text": f"{now_price:.1f} c/kWh",
        "tooltip": "\n".join(tooltip_lines),
        "class": price_class(now_price),
    }))


if __name__ == "__main__":
    sys.exit(main())
