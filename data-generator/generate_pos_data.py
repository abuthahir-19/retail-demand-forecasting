#!/usr/bin/env python3
"""Synthetic POS transaction generator for the retail analytics platform.

Produces newline-delimited JSON transaction files under
raw/dt=YYYY-MM-DD/store=<store_id>/transactions.json — the same layout the
ingestion API writes to and the Spark ETL job reads from.

Modes:
  backfill  Bulk-generate historical days directly to local disk or GCS.
  live      Generate a full day of transactions for YESTERDAY and POST
            each one to the ingestion API - not today, since this runs
            once as a scheduled batch rather than continuously through
            the business day, so "yesterday" is the most recent day that
            has actually finished (and is what the nightly ETL job will
            treat as "yesterday" a couple hours later).
"""
import argparse
import json
import math
import random
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CATEGORIES = [
    # name, base_price, seasonal_peak_day_of_year, seasonal_amplitude
    ("Beverages", 3.50, 200, 0.35),      # peaks mid-summer
    ("Snacks", 4.25, 350, 0.15),         # mild winter-holiday bump
    ("Dairy", 5.00, 15, 0.10),
    ("Produce", 4.75, 170, 0.20),
    ("Household", 8.50, 340, 0.25),      # holiday shopping bump
    ("Apparel", 22.00, 335, 0.45),       # strong winter peak
]

REGIONS = ["North", "South", "East", "West", "Central"]


def build_catalog(num_stores: int, num_skus: int, rng: random.Random):
    stores = []
    for i in range(num_stores):
        stores.append({
            "store_id": f"STORE_{i:04d}",
            "store_name": f"Store {i:04d}",
            "region": rng.choice(REGIONS),
            "city": f"City-{rng.randint(1, 40)}",
            "size_multiplier": rng.lognormvariate(0, 0.4),
        })

    skus = []
    for i in range(num_skus):
        category, base_price, peak_day, amplitude = rng.choice(CATEGORIES)
        skus.append({
            "sku": f"SKU_{i:04d}",
            "product_name": f"{category} Item {i:04d}",
            "category": category,
            "unit_cost": round(base_price * rng.uniform(0.5, 0.7), 2),
            "unit_price": round(base_price * rng.uniform(0.95, 1.15), 2),
            "peak_day": peak_day,
            "amplitude": amplitude,
            "base_rate": rng.uniform(0.5, 4.0),
        })

    # Each store only carries a subset of the catalog.
    assortments = {
        s["store_id"]: rng.sample(skus, k=max(1, int(num_skus * 0.7)))
        for s in stores
    }
    return stores, skus, assortments


def seasonal_factor(day: date, peak_day: int, amplitude: float) -> float:
    doy = day.timetuple().tm_yday
    return 1.0 + amplitude * math.cos(2 * math.pi * (doy - peak_day) / 365.0)


def day_of_week_factor(day: date) -> float:
    dow = day.weekday()  # Mon=0 .. Sun=6
    if dow in (5, 6):
        return 1.3
    if dow == 0:
        return 0.85
    return 1.0


def generate_day_transactions(day: date, stores, assortments, rng: random.Random):
    transactions_by_store = {}
    for store in stores:
        store_id = store["store_id"]
        dow_factor = day_of_week_factor(day)
        txns = []
        for sku in assortments[store_id]:
            lam = (
                sku["base_rate"]
                * store["size_multiplier"]
                * dow_factor
                * seasonal_factor(day, sku["peak_day"], sku["amplitude"])
            )
            total_units = rng.gauss(lam, math.sqrt(max(lam, 0.1)))
            total_units = max(0, round(total_units))
            if total_units == 0:
                continue

            num_txns = min(total_units, rng.randint(1, 3))
            remaining = total_units
            for t in range(num_txns):
                qty = remaining if t == num_txns - 1 else rng.randint(1, max(1, remaining - (num_txns - t - 1)))
                remaining -= qty
                ts = datetime.combine(day, datetime.min.time(), tzinfo=timezone.utc) + timedelta(
                    seconds=rng.randint(8 * 3600, 21 * 3600)
                )
                txns.append({
                    "transactionId": str(uuid.uuid4()),
                    "storeId": store_id,
                    "sku": sku["sku"],
                    "category": sku["category"],
                    "quantity": qty,
                    "unitPrice": round(sku["unit_price"] * rng.uniform(0.97, 1.03), 2),
                    "timestamp": ts.isoformat(),
                })
        if txns:
            transactions_by_store[store_id] = txns
    return transactions_by_store


def write_local(base_dir: Path, day: date, store_id: str, txns: list):
    out_dir = base_dir / "raw" / f"dt={day.isoformat()}" / f"store={store_id}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "transactions.json"
    with out_file.open("w", encoding="utf-8") as f:
        for txn in txns:
            f.write(json.dumps(txn) + "\n")


def write_gcs(bucket_name: str, prefix: str, day: date, store_id: str, txns: list):
    from google.cloud import storage

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob_path = f"{prefix}/dt={day.isoformat()}/store={store_id}/transactions.json"
    body = "\n".join(json.dumps(t) for t in txns)
    bucket.blob(blob_path).upload_from_string(body, content_type="application/json")


def post_to_api(api_url: str, txns: list):
    import requests

    for txn in txns:
        resp = requests.post(f"{api_url}/transactions", json=txn, timeout=10)
        resp.raise_for_status()


def write_dimension_seeds(out_dir: Path, stores, skus):
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "dim_store.csv").open("w", encoding="utf-8") as f:
        f.write("store_id,store_name,region,city\n")
        for s in stores:
            f.write(f'{s["store_id"]},{s["store_name"]},{s["region"]},{s["city"]}\n')

    with (out_dir / "dim_sku.csv").open("w", encoding="utf-8") as f:
        f.write("sku,product_name,category,unit_cost\n")
        for sk in skus:
            f.write(f'{sk["sku"]},{sk["product_name"]},{sk["category"]},{sk["unit_cost"]}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["backfill", "live"], default="backfill")
    parser.add_argument("--num-stores", type=int, default=200)
    parser.add_argument("--num-skus", type=int, default=60)
    parser.add_argument("--days", type=int, default=90, help="Backfill window length, ending yesterday")
    parser.add_argument("--end-date", type=str, default=None, help="ISO date, default: yesterday (UTC)")
    parser.add_argument("--output", choices=["local", "gcs"], default="local")
    parser.add_argument("--local-dir", type=str, default="./generated-data")
    parser.add_argument("--gcs-bucket", type=str, default=None)
    parser.add_argument("--gcs-prefix", type=str, default="raw")
    parser.add_argument("--api-url", type=str, default="http://localhost:8080")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    stores, skus, assortments = build_catalog(args.num_stores, args.num_skus, rng)

    if args.mode == "backfill":
        end_day = (
            date.fromisoformat(args.end_date) if args.end_date else date.today() - timedelta(days=1)
        )
        start_day = end_day - timedelta(days=args.days - 1)

        write_dimension_seeds(Path("./generated-data") / "dimensions", stores, skus)

        day = start_day
        total_txns = 0
        while day <= end_day:
            by_store = generate_day_transactions(day, stores, assortments, rng)
            for store_id, txns in by_store.items():
                total_txns += len(txns)
                if args.output == "local":
                    write_local(Path(args.local_dir), day, store_id, txns)
                else:
                    write_gcs(args.gcs_bucket, args.gcs_prefix, day, store_id, txns)
            print(f"{day.isoformat()}: {sum(len(t) for t in by_store.values())} transactions across {len(by_store)} stores")
            day += timedelta(days=1)
        print(f"Done. {total_txns} transactions generated for {args.days} day(s), output={args.output}")

    else:
        # Yesterday, not today: this runs once as a batch (not continuously
        # through the actual business day), so "today" would mean posting
        # a full day of sales before the store has even opened. Yesterday
        # is a day that's actually finished - the same day the nightly ETL
        # job will treat as "yesterday" when it runs a couple hours later.
        process_day = date.today() - timedelta(days=1)
        by_store = generate_day_transactions(process_day, stores, assortments, rng)
        total = 0
        for store_id, txns in by_store.items():
            post_to_api(args.api_url, txns)
            total += len(txns)
        print(f"Posted {total} live transactions for {process_day.isoformat()} to {args.api_url}")


if __name__ == "__main__":
    main()
