# Aanchal ESP32 Panic Button - Setup Guide

## Hardware Required
- ESP32 development board (any variant: ESP32-WROOM,
  NodeMCU-32S, DOIT ESP32, etc.)
- Tactile push button
- USB cable + power bank (for demo)
- Optional: small enclosure / brooch frame

## Wiring
ESP32 GPIO 0  ----------- Button leg 1
ESP32 GND     ----------- Button leg 2
ESP32 GPIO 2  ----------- Built-in LED (no wire needed)
ESP32 USB     ----------- Power bank

GPIO 0 is the BOOT button on most ESP32 dev boards.
You can use it directly - no extra button needed for demo.

## PlatformIO Setup in VS Code

### Step 1 - Install PlatformIO
1. Open VS Code
2. Extensions (Ctrl+Shift+X)
3. Search "PlatformIO IDE"
4. Install -> wait for install to complete
5. Restart VS Code

### Step 2 - Open the project
1. PlatformIO icon in left sidebar (alien head icon)
2. Click "Open Project"
3. Navigate to:
   D:\My projects\Aanchal\hardware\esp32_panic_button
4. Click Open

### Step 3 - Install the library
PlatformIO installs NimBLE-Arduino automatically from
the lib_deps in platformio.ini. No manual install needed.

If you want to install manually:
1. PlatformIO sidebar -> Libraries
2. Search "NimBLE-Arduino"
3. Find by h2zero -> Install

### Step 4 - Flash the firmware
1. Connect ESP32 via USB
2. PlatformIO toolbar at bottom of VS Code:
   Click -> (Upload) button
   OR: Ctrl+Alt+U
3. Watch terminal - should end with:
   "Leaving... Hard resetting via RTS pin..."
4. Open Serial Monitor (plug icon in toolbar)
   Set baud to 115200
5. You should see:
   [ESP32] Aanchal button ready
   [ESP32] Waiting for phone...

### Step 5 - Pair with the app
1. Open Aanchal app on your phone
2. Log in
3. Watch app logs - should show:
   [BLE] Scanning for Aanchal...
   [BLE] Found <device_id>
   [BLE] Connected to Aanchal button
4. ESP32 LED goes solid ON = connected

## Testing
1. ESP32 connected (LED solid)
2. Press the button on ESP32
3. ESP32 Serial Monitor shows:
   [ESP32] Button pressed
   [ESP32] SOS sent via BLE
   LED blinks 3 times fast
4. App shows:
   [BLE] Received: SOS
   [BLE] Hardware SOS trigger!
   [SOSService] SOS triggered by...
5. Full SOS chain fires - SMS + TTS alert

## Demo Troubleshooting

| Symptom | Fix |
|---|---|
| LED stays blinking (not solid) | App not open or BLE scanning |
| App shows "not found" | Check ESP32 is powered on |
| Button press - no response | Check GPIO 0 wiring or use BOOT btn |
| SOS fires twice | Increase DEBOUNCE_MS in firmware |
| BLE permission denied | Android Settings -> Apps -> Aanchal -> Permissions |

## For the Demo Day
- Power ESP32 from a power bank hidden in your bag
- GPIO 0 (BOOT button) works as the panic button
  without any extra wiring
- LED solid = ready, LED blinking = waiting for phone
- Press BOOT button = SOS fires

## Arduino Libraries folder
If you have libraries in D:\My projects\Arduino Projects\libraries
that you want PlatformIO to use, add this to platformio.ini:

  lib_extra_dirs =
      D:/My projects/Arduino Projects/libraries

Then PlatformIO will find any manually installed libraries there.
