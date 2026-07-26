<div align="center">

# ESP32 BLE and 2.4 GHz RF Activity Scanner

### Bluetooth Low Energy monitoring and relative RF-energy detection using an ESP32 with single and dual nRF24L01 configurations

[![Platform](https://img.shields.io/badge/Platform-ESP32-blue.svg)](https://www.espressif.com/en/products/socs/esp32)
[![Arduino](https://img.shields.io/badge/Framework-Arduino-00979D.svg)](https://www.arduino.cc/)
[![Processing](https://img.shields.io/badge/Interface-Processing%204-006699.svg)](https://processing.org/)
[![Python](https://img.shields.io/badge/Analysis-Python-3776AB.svg)](https://www.python.org/)
[![MATLAB](https://img.shields.io/badge/Analysis-MATLAB-orange.svg)](https://www.mathworks.com/products/matlab.html)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>


## 📌 Overview

This repository contains a compact 2.4 GHz monitoring platform based on anESP32 and external nRF24L01 transceivers. The project supports both single-radio and dual-radio RF scanning configurations.

The system combines two complementary measurements:

1. **Bluetooth Low Energy scanning**, performed by the ESP32 Bluetooth subsystem.
2. **Relative RF energy detection**, performed by the nRF24L01 while sequentially scanning frequencies from 2402 MHz to 2480 MHz.

A Processing 4 desktop application displays the measurements in real time and exports them to CSV files. MATLAB and Python scripts are included for offline visualization and analysis.

The project is intended for educational, experimental, and comparative analysis of wireless activity in the 2.4 GHz ISM band.


## 📂 Contents

- `/code_dual` → Code for ESP32 (Arduino environment) for the dual nRF24L01 RF scanner.
- `/code_single` → Code for ESP32 (Arduino environment) for the single nRF24L01 RF scanner.
- `/processing_dual` → Processing 4 interface for the dual-radio version.
- `/processing_single` → Processing 4 interface for the single-radio version.
- `/matlab` → MATLAB code for CSV data visualization and analysis.
- `/python` → Python code for CSV data visualization and analysis.
- `/binaries` → Precompiled firmware images for compatible ESP32 boards.

## ✨ Main Features

* Bluetooth Low Energy device discovery.
* BLE RSSI monitoring over time.
* Sequential RF scanning from 2402 MHz to 2480 MHz.
* Single-radio configuration using one nRF24L01 connected through VSPI.
* Dual-radio configuration using two nRF24L01 modules connected through
  independent VSPI and HSPI buses.
* BLE scanning through the integrated ESP32 Bluetooth receiver and antenna.
* Time-multiplexed BLE and RF acquisition.
* Relative energy-detection percentage for each RF channel.
* Raw and filtered RF measurements.
* Automatic RF graph scaling.
* RF activity history map.
* Adjustable BLE RSSI time window.
* Adjustable RSSI vertical limits.
* Protected BLE addresses in the public interface.
* CSV recording.
* MATLAB data-analysis script.
* Python data-analysis script.
* Compact Processing 4 graphical interface.
* Fixed interface size to prevent rendering problems during resizing.


## 🧩 System Architecture

The platform combines two independent 2.4 GHz receiver paths:

1. The integrated ESP32 Bluetooth Low Energy radio performs BLE device
   discovery, identification, and RSSI measurement through the ESP32 antenna.
2. The external nRF24L01 receiver or receivers perform relative RF-energy
   detection through their own antennas.

The ESP32 firmware coordinates both acquisition processes, filters the RF
measurements, formats the serial messages, and transfers the results to the
Processing 4 interface.

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/f49b2990-18d0-4137-9938-274129eff6bb"
    alt="System architecture of the ESP32 BLE and RF24 activity scanner"
    width="95%"
  >
</p>

<p align="center">
  <em>
    Architecture of the ESP32-based BLE and 2.4 GHz RF activity scanner,
    supporting single and dual nRF24L01 configurations.
  </em>
</p>

### Receiver and Acquisition Scheduling

The BLE receiver and the firmware controller are part of the same ESP32
development board. The BLE data path is therefore internal to the ESP32 and
does not use the nRF24L01 modules.

The antenna configuration is:

| Configuration | ESP32 BLE antenna | nRF24L01 antennas | Total |
|---|---:|---:|---:|
| Single | 1 | 1 | 2 |
| Dual | 1 | 2 | 3 |

The receivers do not perform all measurements continuously at the same time.
The firmware alternates between RF sweeps and BLE scanning:

- **Single version:** two complete RF sweeps followed by a one-second BLE scan.
- **Dual version:** four dual RF sweeps followed by a one-second BLE scan.

During each dual RF measurement window, both nRF24L01 receivers observe their
assigned frequency channels simultaneously. BLE scanning begins only after the
configured number of RF sweeps has been completed.

This scheduling reduces the possibility that transmissions produced during
the ESP32 active BLE scan are interpreted by the nRF24L01 receivers as
external RF activity.

> BLE RSSI is measured by the integrated ESP32 Bluetooth receiver. The
> nRF24L01 provides relative binary RF-energy detection and does not provide
> calibrated received power or RSSI in dBm.

## 🖥️ Interface in Operation

The Processing 4 application provides real-time visualization of the relative
RF-energy detection spectrum, RF activity history, nearby Bluetooth Low Energy
devices, and BLE RSSI measurements.

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/8c2501c5-b0fb-4424-8edf-837547878d8d"
    alt="Processing 4 interface for the ESP32 BLE and RF24 activity scanner during a measurement session"
    width="95%"
  >
</p>


<p align="center">
  <em>
    Processing 4 interface during a measurement session, showing the relative
    RF-energy spectrum, RF activity history, BLE device table, and RSSI
    measurements.
  </em>
</p>

The interface includes:

- Relative RF-energy detection from 2402 MHz to 2480 MHz.
- RF activity history visualization.
- Bluetooth Low Energy device detection.
- BLE RSSI monitoring over time.
- Protected BLE address display.
- Automatic RF graph scaling.
- Serial-port selection and connection controls.
- CSV data recording.

> The RF spectrum represents the percentage of observation windows in which
> the nRF24L01 detected energy above its internal RPD/CD threshold. It does
> not represent calibrated RF power or RSSI in dBm.

## 🔧 Hardware

### Required Components

| Component                       | Quantity | Description                     |
| ------------------------------- | -------: | ------------------------------- |
| ESP32 development board         |        1 | Main controller and BLE scanner |
| nRF24L01 or nRF24L01+ | 1–2 | Relative RF-energy detection receivers |
| 100 nF ceramic capacitor        | 1–2 | One capacitor per nRF24L01 module |
| 10–47 µF electrolytic capacitor | 1–2 | One capacitor per nRF24L01 module |
| USB cable                       |        1 | Power and serial communication  |
| Breadboard or PCB               |        1 | Hardware assembly               |

> The nRF24L01 must be powered from **3.3 V**. Do not connect its VCC pin directly to 5 V.


## 🔌 Hardware Connections

The project supports two hardware configurations:

- **Single nRF24L01+ PA/LNA version:** one module connected to the ESP32 VSPI bus.
- **Dual nRF24L01+ PA/LNA version:** two modules connected through independent VSPI and HSPI buses.

<p align="center">
  <img
    src="https://github.com/user-attachments/assets/a79ec446-4591-4a07-9d68-c9c12c32b288"
    alt="ESP32 connection diagram for single and dual nRF24L01+ PA/LNA configurations"
    width="60%"
  >
</p>

<p align="center">
  <em>
    ESP32 wiring for the single and dual nRF24L01+ PA/LNA implementations.
    The IRQ pins are optional and are not used by the current code for ESP32 (Arduino environment).
  </em>
</p>

### Connection Summary

| Configuration | Module | SPI bus | CE | CSN | SCK | MISO | MOSI |
|---|---|---|---:|---:|---:|---:|---:|
| Single | nRF24L01+ | VSPI | GPIO 15 | GPIO 5 | GPIO 18 | GPIO 19 | GPIO 23 |
| Dual | nRF24L01+ #1 | VSPI | GPIO 15 | GPIO 5 | GPIO 18 | GPIO 19 | GPIO 23 |
| Dual | nRF24L01+ #2 | HSPI | GPIO 22 | GPIO 21 | GPIO 14 | GPIO 12 | GPIO 13 |

> Both nRF24L01+ PA/LNA modules must be powered from **3.3 V**. Do not connect
> the VCC pin to 5 V.

> Place a decoupling capacitor close to each module. A **100 nF ceramic
> capacitor in parallel with a 10–47 µF electrolytic capacitor** is recommended
> between VCC and GND.

> PA/LNA modules may produce relatively high current peaks. Use a stable 3.3 V
> supply, keep the wiring short, and avoid placing the antennas close to metal
> objects or directly beside each other.


## 📡 RF Scanning Range

The nRF24L01 channel-to-frequency relationship is:

```text
Frequency [MHz] = 2400 + nRF24L01 channel
```

The code for ESP32 (Arduino environment) scans:

| nRF24L01 Channel | Frequency |
| ---------------: | --------: |
|                2 |  2402 MHz |
|                3 |  2403 MHz |
|              ... |       ... |
|               80 |  2480 MHz |

The single version uses one nRF24L01 to sequentially scan all 79 frequencies.

The dual version divides the scan between two nRF24L01 receivers:

| Receiver | SPI bus | Channels | Frequency range |
|---|---|---:|---:|
| nRF24L01 #1 | VSPI | 2–41 | 2402–2441 MHz |
| nRF24L01 #2 | HSPI | 42–80 | 2442–2480 MHz |

The two receivers in the dual version observe one channel from each assigned
range during the same RF measurement window.

## 📊 Relative RF Energy Detection

The nRF24L01 does not provide a continuous calibrated RSSI value for arbitrary RF signals.

Instead, its RPD or carrier-detect function produces a binary observation:

```text
0 = Energy was not detected above the internal threshold
1 = Energy was detected above the internal threshold
```

For each frequency, the code for ESP32 (Arduino environment) performs 24 observation windows.

The raw detection percentage is calculated as:

```text
Raw detection [%] =
    detected observation windows
    -------------------------------- × 100
    total observation windows
```

With 24 observations per channel, the raw resolution is:

```text
100 / 24 ≈ 4.17 %
```

Examples:

| Positive detections | Raw detection |
| ------------------: | ------------: |
|             0 of 24 |           0 % |
|             1 of 24 |        4.17 % |
|             3 of 24 |        12.5 % |
|             6 of 24 |          25 % |
|            12 of 24 |          50 % |
|            24 of 24 |         100 % |

This value must be interpreted as:

> The percentage of observation windows in which RF energy was detected above the internal nRF24L01 threshold.

It does **not** represent:

* Calibrated received power.
* RSSI in dBm.
* Exact channel-utilization time.
* Protocol identification.
* Packet-decoding success.
* A distinction between Wi-Fi, Bluetooth, nRF24L01, or other 2.4 GHz transmitters.

## 📈 RF Filtering

The code for ESP32 (Arduino environment) applies asymmetric filtering to improve the visual response:

```cpp
filteredDetection =
    alpha * rawDetection
    + (1.0 - alpha) * previousFilteredDetection;
```

The filter uses:

```text
Attack coefficient: 0.85
Decay coefficient:  0.16
```

The higher attack coefficient makes new RF activity appear quickly.

The lower decay coefficient makes the displayed activity decrease more gradually, reducing abrupt visual changes.

---

## 📏 Automatic RF Scale

The Processing interface automatically selects one of the following vertical ranges:

```text
0–5 %
0–10 %
0–20 %
0–50 %
0–100 %
```

The 5% value is only the minimum upper limit of the displayed graph.

It is not:

* An RF detection threshold.
* A minimum measured activity.
* A fixed channel-occupancy value.

The minimum nonzero raw measurement is approximately 4.17% because the code for ESP32 (Arduino environment) performs 24 observations per frequency.

## 📶 Bluetooth Low Energy Monitoring

Bluetooth Low Energy scanning is performed directly by the ESP32 BLE subsystem.

For each detected device, the code for ESP32 (Arduino environment) may report:

* Device name.
* BLE address.
* RSSI.
* Manufacturer information.
* Advertised service.
* Possible advertising channels.
* Possible advertising frequencies.

The BLE advertising channels are:

| BLE Channel | Center Frequency |
| ----------: | ---------------: |
|          37 |         2402 MHz |
|          38 |         2426 MHz |
|          39 |         2480 MHz |

The high-level ESP32 BLE scan does not directly report which advertising channel was used for each received packet. Therefore, the interface displays all three possible BLE advertising channels.

## 🔐 BLE Address Privacy

BLE addresses are masked in the graphical interface by default.

Example:

```text
Original address:
A4:C1:38:7B:21:9F

Displayed address:
XX:XX:XX:XX:21:9F
```

The Processing configuration includes two independent options:

```java
final boolean SHOW_FULL_BLE_ADDRESS = false;
final boolean EXPORT_FULL_BLE_ADDRESS = false;
```

Recommended settings for public videos and shared datasets:

```java
SHOW_FULL_BLE_ADDRESS = false
EXPORT_FULL_BLE_ADDRESS = false
```

The complete address may be retained locally for controlled laboratory analysis, but public files should normally use protected addresses.

---

## 🖥️ Processing 4 Interface

The graphical interface contains five main sections:

### RF Detection Spectrum

Displays the filtered relative energy-detection percentage for every frequency between 2402 MHz and 2480 MHz.

### RF Detection History

Displays successive RF scans as a time-frequency map.

The most recent sweep appears at the bottom.

### BLE RSSI Graph

Displays BLE RSSI measurements over an adjustable time interval.

Available time windows:

```text
15 s
30 s
60 s
120 s
300 s
```

The minimum and maximum RSSI graph limits can be adjusted in 5 dBm increments.

### BLE Device Table

Displays:

* Internal device number.
* Device identification.
* Protected BLE address.
* Filtered RSSI.
* Possible advertising channels.
* Possible advertising frequencies.
* Active or inactive status.
* Time since the last observation.
* Number of received BLE advertisements.

### Status and Keyboard Controls

| Key | Action                             |
| --- | ---------------------------------- |
| `G` | Start or stop CSV recording        |
| `R` | Reset RF peak values               |
| `C` | Clear BLE devices and RSSI history |
| `H` | Clear the RF history map           |


## 📨 Serial Protocol

The ESP32 communicates with the Processing interface using comma-separated serial messages.

### RF Measurement

```text
RF,frequency_MHz,filtered_detection_pct,raw_detection_pct
```

Example:

```text
RF,2426,7.84,8.33
```

### BLE Device

```text
BLE,address,rssi_dBm,identification,possible_channels,possible_frequencies
```

Example:

```text
BLE,A4:C1:38:7B:21:9F,-67,Environmental sensor,37|38|39,2402|2426|2480
```

### Completed RF Sweep

```text
FRAME,frame_number
```

Example:

```text
FRAME,125
```

### System Status

```text
STATUS,message
```

Example:

```text
STATUS,nRF24L01 connected; RPD detector
```

---

## 💾 CSV Format

The Processing interface exports the following columns:

```text
tiempo_ms
tipo
frame
radio
frecuencia_MHz
ocupacion_filtrada_pct
ocupacion_cruda_pct
direccion
rssi_dBm
identificacion
canales_BLE_posibles
frecuencias_BLE_posibles_MHz
```

The historical column names are retained for compatibility:

```text
ocupacion_filtrada_pct
ocupacion_cruda_pct
```

Their technically correct interpretation is:

```text
ocupacion_filtrada_pct
→ Filtered percentage of observation windows with RF energy detection

ocupacion_cruda_pct
→ Raw percentage of observation windows with RF energy detection
```

The `radio` column contains:

```text
nRF24L01
```

for RF measurements generated by the single-radio code for ESP32 (Arduino environment).

## 📦 Software Requirements

### Code for ESP32 (Arduino environment)

* Arduino IDE or PlatformIO.
* ESP32 board package.
* RF24 library by TMRh20.
* ESP32 BLE library.

### Desktop Interface

* Processing 4.
* Processing Serial library.

### Python Analysis

* Python 3.10 or later.
* pandas.
* matplotlib.
* tkinter.

Install the Python dependencies with:

```bash
pip install pandas matplotlib
```

### MATLAB Analysis

* MATLAB with support for:

  * `readtable`
  * `detectImportOptions`
  * `writetable`
  * standard plotting functions

---

## 🚀 Uploading the Code for ESP32 (Arduino environment)

1. Install the ESP32 board package in Arduino IDE.
2. Install the `RF24` library by TMRh20.
3. Connect the nRF24L01 according to the wiring table.
4. Open the code that corresponds to your hardware configuration:

   **Single nRF24L01 version**

   ```text
   code_single/code_single.ino
   ```

   **Dual nRF24L01 version**

   ```text
   code_dual/code_dual.ino
   ```

5. Select the correct ESP32 board.
6. Select the correct serial port.
7. Compile and upload the code to the ESP32.
8. Close the Arduino Serial Monitor before opening the Processing interface.

---

## ⚡ Installing a Precompiled Firmware Image

Compiling the project is not required if you use one of the complete firmware
images available in the `/binaries` directory. This option is useful when you
want a faster installation or when the Arduino IDE reports compilation or
library-related errors.

> Select the firmware image that matches your hardware configuration. The file
> used with this procedure must be a **complete merged image** and must be
> flashed at address `0x0`. A standard Arduino application `.bin` file is not a
> replacement for the merged image.

### 1. Install the Flashing Utility

1. Download and extract the
   [Espressif Flash Download Tools](https://www.espressif.com/en/support/download/other-tools).
2. Connect the ESP32 to the computer with a data-capable USB cable.
3. Verify that the board appears as a serial port in Windows.
4. If no COM port is detected, install the driver required by the USB-to-UART
   interface used on your board. Boards based on the CP2102 or CP2104 can use
   the [Silicon Labs CP210x VCP driver](https://www.silabs.com/software-and-tools/usb-to-uart-bridge-vcp-drivers).
5. Close the Arduino Serial Monitor, Processing, and any other program using the
   ESP32 serial port.

### 2. Select the Firmware Image

Download the appropriate merged `.bin` file from the `/binaries` directory:

- Use the **single-radio** image for the version with one nRF24L01 module.
- Use the **dual-radio** image for the version with two nRF24L01 modules.

### 3. Configure the ESP32 Flash Download Tool

1. Start the Flash Download Tool.
2. Select the following startup options:

   ```text
   ChipType: ESP32
   WorkMode: Develop
   LoadMode: UART
   ```

3. In **Download Path Config**, select the merged `.bin` file and enable its
   checkbox.
4. Set the download address to:

   ```text
   0x0
   ```

5. Select the COM port assigned to the ESP32.
6. Set the baud rate to `115200` for a reliable initial upload.
7. Leave the remaining SPI flash options at their default values unless your
   board requires a different configuration.
8. Click **START** to write the firmware.

### 4. Start the Firmware

Wait until the tool reports that the download has completed successfully. Then
press the ESP32 **EN/RESET** button or disconnect and reconnect the USB cable.

If the tool remains at `Connecting...`, hold the **BOOT** button while starting
the download and release it as soon as the writing process begins. Many ESP32
development boards enter download mode automatically and do not require this
manual step.

After restarting the board, open the Processing interface, select the same COM
port, and verify that RF and BLE measurements are received correctly.

---

## ▶️ Running the Processing Interface

1. Install Processing 4.
2. Open:

```text
processing/Scanner_BLE_RF24_Single_Processing4_v1.pde
```

3. Run the sketch.
4. Press `ACTUALIZAR`.
5. Select the ESP32 serial port.
6. Press `CONECTAR`.
7. Verify that RF measurements begin to appear.
8. Wait for the ESP32 BLE scan to report nearby devices.
9. Press `REGISTRAR CSV` to start recording.
10. Select the destination filename.
11. Press `GUARDAR CSV` to close the recording correctly.

---

## 🧪 Experimental Testing with Airwave Lab

This scanner can be used as a monitoring and visualization platform during
controlled Bluetooth, BLE, and 2.4 GHz RF experiments.

The experimental hardware, laboratory validation, spectrum-analyzer
measurements, and controlled test methodology are documented in the following
repository:

[Airwave Lab — Bluetooth, BLE and RF Research Toolkit](https://github.com/CrissCCL/Airwave_Lab)

Airwave Lab complements this project by providing a controlled experimental
environment for observing how RF activity is represented in the scanner
interface. The repositories can be used together to compare detected frequency
activity, the RF history map, and BLE RSSI variations under different test
conditions.

> Perform RF experiments only with equipment you own or are authorized to test.
> Active RF tests must be conducted in an isolated or shielded environment and
> in accordance with applicable telecommunications regulations.

---

## 🐍 Python Analysis

Run:

```bash
python analysis/python/leer_scanner_ble_rf24_single.py
```

The script opens a file-selection window and generates:

* The last available RF spectrum.
* Raw and filtered RF detection at a selected frequency.
* BLE RSSI curves.
* A BLE device statistical summary.
* A separate BLE summary CSV file.

The default temporal-analysis frequency is:

```python
FRECUENCIA_PREFERIDA_MHZ = 2426
```

When this frequency is unavailable, the script automatically selects the frequency with the highest mean filtered detection.

---

## 📐 MATLAB Analysis

Run:

```matlab
leer_scanner_ble_rf24_single
```

The MATLAB script generates:

* The last available RF spectrum.
* Raw and filtered RF detection at a selected frequency.
* BLE RSSI curves.
* A BLE device statistical summary.
* A separate BLE summary CSV file.

The default temporal-analysis frequency is:

```matlab
frecuenciaPreferidaMHz = 2426;
```

---

## 📊 Typical Result Interpretation

### Isolated RF Peaks

An isolated peak indicates that RF energy was detected repeatedly at a specific frequency during the observation windows.

It does not directly identify the transmitter.

### Wide RF Activity Region

A wider region containing several active frequencies may be associated with a broadband or frequency-spread signal, but additional instrumentation is required for protocol identification.

### BLE Device with Stable RSSI

A relatively stable BLE RSSI generally indicates that the transmitter and receiver remained at approximately the same distance and orientation.

### BLE Device with Variable RSSI

RSSI variations may be caused by:

* Movement.
* Antenna orientation.
* Multipath propagation.
* Obstacles.
* Human-body shadowing.
* Different BLE advertising events.
* Receiver scheduling.

### Raw and Filtered Detection

The raw signal changes in discrete increments of approximately 4.17%.

The filtered signal provides a smoother visualization but should not be interpreted as increased physical measurement resolution.

---

## ⚠️ Technical Limitations

* The nRF24L01 is not a calibrated spectrum analyzer.
* The RF graph does not display power in dBm.
* The nRF24L01 cannot identify the detected wireless protocol.
* The RPD/CD output is binary.
* The detector threshold is internal to the device.
* A single nRF24L01 scans the frequencies sequentially rather than simultaneously.
* Short RF events may occur between observation windows.
* BLE scanning temporarily interrupts or reduces the RF scan update rate.
* The ESP32 BLE subsystem and nRF24L01 use independent receivers.
* BLE RSSI values are not directly comparable with the nRF24L01 RF-detection percentage.
* The system does not replace a spectrum analyzer or software-defined radio.

---

## 🎓 Educational Applications

This platform can be used to demonstrate:

* The 2.4 GHz ISM band.
* Sequential frequency scanning.
* Binary energy detection.
* Measurement resolution.
* Exponential filtering.
* Attack and decay coefficients.
* Bluetooth Low Energy advertising.
* BLE RSSI variation.
* Time-frequency visualization.
* CSV-based experimental data acquisition.
* Comparison between online and offline data analysis.
* The difference between energy detection and calibrated power measurement.

---

## ⚠️ Disclaimer

This repository is intended for educational, research, and experimental use.

The system passively observes BLE advertisements and relative RF energy. It is not intended for unauthorized access, communication interception, device tracking, or interference with wireless systems.

Users are responsible for complying with applicable privacy, telecommunications, and data-protection regulations.



## 🤝 Support projects
 Support me on Patreon [https://www.patreon.com/c/CrissCCL](https://www.patreon.com/c/CrissCCL)

## 📜 License
MIT License



