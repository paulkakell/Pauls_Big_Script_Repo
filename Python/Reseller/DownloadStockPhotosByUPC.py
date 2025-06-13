import os
import sys
import time
import requests
from bs4 import BeautifulSoup
from PIL import Image
from io import BytesIO

# === Configuration Variables ===
# Your UPCItemDB API key (replace with a valid key)
UPCITEMDB_API_KEY = 'your_api_key_here'
# URL template for looking up products by UPC
SEARCH_URL = 'https://api.upcitemdb.com/prod/trial/lookup?upc={upc}'
# HTTP headers to mimic a real browser request
HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:97.0) '
        'Gecko/20100101 Firefox/97.0'
    )
}
# Default local filesystem path where images will be saved
DEFAULT_FOLDER = "D:\Storage"
# Maximum number of images to download per product
MAX_IMAGES = 10
# Minimum acceptable image dimensions (pixels)
MIN_WIDTH = 500
MIN_HEIGHT = 500
# Delay between image downloads (seconds) to avoid overwhelming servers
DOWNLOAD_DELAY = 7  


def get_upcitemdb_product(upc):
    """
    Query UPCItemDB for product data matching the given UPC.
    
    Args:
        upc (str): The UPC code to look up.
    
    Returns:
        dict or None: The first matching product item, or None if not found.
    """
    # Format the lookup URL with the UPC
    url = SEARCH_URL.format(upc=upc)
    # Include API key header if required by UPCItemDB (not used in trial endpoint)
    headers = HEADERS.copy()
    headers['Key'] = UPCITEMDB_API_KEY
    
    # Perform the HTTP GET request
    response = requests.get(url, headers=headers)
    # Parse JSON response into a Python dict
    data = response.json()
    
    # Check response code and return the first product item if successful
    if data.get('code') == 'OK' and data.get('items'):
        return data['items'][0]
    # Return None when lookup fails or no items found
    return None


def download_images(
    image_urls,
    folder,
    max_images=MAX_IMAGES,
    min_width=MIN_WIDTH,
    min_height=MIN_HEIGHT,
    delay=DOWNLOAD_DELAY
):
    """
    Download images from a list of URLs into the specified folder,
    applying size filters and rate limiting.
    
    Args:
        image_urls (list of str): URLs of images to download.
        folder (str): Local directory path to save downloaded images.
        max_images (int): Cap on how many images to download.
        min_width (int): Minimum width in pixels for saved images.
        min_height (int): Minimum height in pixels for saved images.
        delay (int): Seconds to wait between download attempts.
    """
    # Ensure the destination directory exists
    os.makedirs(folder, exist_ok=True)
    
    downloaded = 0
    # Iterate over URLs with index for filename uniqueness
    for idx, url in enumerate(image_urls):
        # Stop if we've reached the download limit
        if downloaded >= max_images:
            break
        
        try:
            # Fetch the image data
            resp = requests.get(url)
            # Open the image in memory
            img = Image.open(BytesIO(resp.content))
            
            # Check image dimensions before saving
            if img.width >= min_width and img.height >= min_height:
                # Construct full path for saving
                save_path = os.path.join(folder, f'image_{idx}.jpg')
                # Write binary content to file
                with open(save_path, 'wb') as f:
                    f.write(resp.content)
                downloaded += 1
        except Exception as e:
            # Print errors but continue with next URL
            print(f"Error downloading {url}: {e}")
            continue
        
        # Pause to avoid rapid-fire requests
        time.sleep(delay)


def main():
    """
    Main function to prompt for UPC, fetch product data,
    and download associated images.
    """
    # Prompt the user for a UPC code
    upc = input("Enter the UPC: ").strip()
    
    # Prompt for base folder, use default if left blank
    base = input(f"Enter base folder (default: {DEFAULT_FOLDER}): ").strip()
    if not base:
        base = DEFAULT_FOLDER
    
    # Append the UPC as a subfolder for organization
    target_folder = os.path.join(base, upc)
    
    # Look up the product via UPCItemDB
    product = get_upcitemdb_product(upc)
    
    # If product found, download images; otherwise inform the user
    if product:
        download_images(product.get('images', []), target_folder)
        print(f"Downloaded images to: {target_folder}")
    else:
        print("No product found for the given UPC.")


if __name__ == "__main__":
    main()
