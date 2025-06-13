# UPC Image Downloader

A tool to fetch product details via UPCItemDB and download qualifying images.

## Overview

This script queries UPCItemDB for product data using a UPC code. It then downloads up to 10 images that meet configurable size thresholds. A delay between downloads helps avoid rate limiting.

## Configuration

At the top of `download_images.py`, set your values:

```python
UPCITEMDB_API_KEY = 'your_api_key_here'
SEARCH_URL = 'https://api.upcitemdb.com/prod/trial/lookup?upc={upc}'
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:97.0) '
                  'Gecko/20100101 Firefox/97.0'
}
DEFAULT_FOLDER = r'C:\Users\paul\OneDrive\Kell Sales\Images\New - Unlisted'
MAX_IMAGES = 10
MIN_WIDTH = 500
MIN_HEIGHT = 500
DOWNLOAD_DELAY = 7
