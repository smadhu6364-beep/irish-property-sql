"""Download the full Residential Property Price Register (PPR) CSV.

Source: Property Services Regulatory Authority, https://www.propertypriceregister.ie
The site serves one zip file holding every residential sale since 1 January 2010.
We save the zip, unpack the CSV into data/raw/ and leave the file as published
(Windows-1252 encoded). All cleaning happens later, in sql/01_load_and_clean.sql.
"""

import io
import urllib.request
import zipfile
from pathlib import Path

URL = (
    "https://www.propertypriceregister.ie/website/npsra/ppr/npsra-ppr.nsf/"
    "Downloads/PPR-ALL.zip/$FILE/PPR-ALL.zip"
)
RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {URL}")
    request = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read()
    print(f"Got {len(payload) / 1e6:.1f} MB, unzipping")

    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for name in archive.namelist():
            if name.lower().endswith(".csv"):
                target = RAW_DIR / "PPR-ALL.csv"
                target.write_bytes(archive.read(name))
                print(f"Saved {target}")


if __name__ == "__main__":
    main()
