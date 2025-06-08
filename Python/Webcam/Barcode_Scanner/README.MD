# Barcode Scanner using Python and OpenCV
This repository contains a simple barcode scanner script that uses Python, OpenCV, pyzbar, and pyperclip to read UPC barcodes using your computer's camera.
## Requirements
* Python 3.x
* OpenCV
* pyzbar
* pyperclip
## Installation
1. Download and install Python from the official website: https://www.python.org/downloads/
2. During the installation process, make sure to check the "Add Python to PATH" option to update the system's PATH variable with the Python executable.
3. Open a Command Prompt or PowerShell terminal, and execute the following commands to install the necessary libraries:  
`pip install opencv-python-headless`  
`pip install opencv-python`  
`pip install pyzbar`  
`pip install pyperclip`  
## Usage
`python barcode_scanner.py`  
The script will open your camera and start scanning for barcodes. When a barcode is detected, it will display the barcode data and type in the terminal, copy the barcode data to the clipboard, and exit the script. Press 'q' to close the camera window.
## Customization
* To use the front-facing camera, change the camera index in the `barcode_scanner.py` script:  
`# Change the camera index to use the front-facing camera`  
`front_camera_index = 1`  
`cap = cv2.VideoCapture(front_camera_index)`  
* To adjust the focus settings, modify the `focus_value` and `last_focus_change_time` variables in the `barcode_scanner.py` script:  
`# Check if it's time to change the focus`  
`if time.time() - last_focus_change_time > 3:`  
`    focus_value = (focus_value + 0.5) % 1.0`  
`    set_focus(cap, focus_value)`  
`    last_focus_change_time = time.time()`  
Keep in mind that manual control of autofocus might not be possible for all devices, and the effectiveness will depend on the specific hardware and driver support.
