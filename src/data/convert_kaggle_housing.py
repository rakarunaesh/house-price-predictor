"""
Converts the Kaggle "Housing Prices Dataset" (price, area, bedrooms, bathrooms,
stories, mainroad, guestroom, basement, hotwaterheating, airconditioning,
parking, prefarea, furnishingstatus) into this project's expected raw schema
(price, sqft, bedrooms, bathrooms, location, year_built, condition).

The Kaggle dataset has no real location, year_built, or condition fields, so
those are derived heuristically from the closest available proxy columns:
  - location:   prefarea + mainroad  (desirability / accessibility proxy)
  - condition:  furnishingstatus + amenities (upkeep/investment proxy)
  - year_built: stories + a seeded random offset (no real proxy exists)
These are reasonable stand-ins for a learning project, not ground truth.
"""
import argparse
import numpy as np
import pandas as pd

RANDOM_SEED = 42


def derive_location(row):
    if row["prefarea"] == "yes" and row["mainroad"] == "yes":
        return np.random.choice(["Downtown", "Urban"])
    if row["prefarea"] == "yes" and row["mainroad"] == "no":
        return np.random.choice(["Waterfront", "Mountain"])
    if row["prefarea"] == "no" and row["mainroad"] == "yes":
        return "Suburb"
    return "Rural"


def derive_condition(row):
    amenity_score = sum(
        row[c] == "yes" for c in ["hotwaterheating", "airconditioning", "basement"]
    )
    if row["furnishingstatus"] == "furnished" and amenity_score >= 2:
        return "Excellent"
    if row["furnishingstatus"] == "furnished":
        return "Good"
    if row["furnishingstatus"] == "semi-furnished":
        return "Fair"
    return "Poor"


def derive_year_built(stories: int, rng: np.random.Generator) -> int:
    # More stories loosely skewed toward newer construction; still randomized.
    base = 1960 + int(stories) * 10
    return int(np.clip(base + rng.integers(-15, 25), 1900, 2023))


def main(args):
    rng = np.random.default_rng(RANDOM_SEED)
    np.random.seed(RANDOM_SEED)

    df = pd.read_csv(args.input)

    out = pd.DataFrame()
    out["price"] = df["price"]
    out["sqft"] = df["area"]
    out["bedrooms"] = df["bedrooms"]
    out["bathrooms"] = df["bathrooms"]
    out["location"] = df.apply(derive_location, axis=1)
    out["year_built"] = df["stories"].apply(lambda s: derive_year_built(s, rng))
    out["condition"] = df.apply(derive_condition, axis=1)

    out.to_csv(args.output, index=False)
    print(f"Wrote {len(out)} rows to {args.output}")
    print(out.head())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Kaggle Housing.csv to project schema")
    parser.add_argument("--input", type=str, required=True, help="Path to Kaggle Housing.csv")
    parser.add_argument("--output", type=str, required=True, help="Path to write converted CSV")
    main(parser.parse_args())
