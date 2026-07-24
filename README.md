<div align="center">

# ESP32 BLE and 2.4 GHz RF Activity Scanner

### Bluetooth Low Energy monitoring and relative RF energy detection using an ESP32 and a single nRF24L01 module

[![Platform](https://img.shields.io/badge/Platform-ESP32-blue.svg)](https://www.espressif.com/en/products/socs/esp32)
[![Arduino](https://img.shields.io/badge/Framework-Arduino-00979D.svg)](https://www.arduino.cc/)
[![Processing](https://img.shields.io/badge/Interface-Processing%204-006699.svg)](https://processing.org/)
[![Python](https://img.shields.io/badge/Analysis-Python-3776AB.svg)](https://www.python.org/)
[![MATLAB](https://img.shields.io/badge/Analysis-MATLAB-orange.svg)](https://www.mathworks.com/products/matlab.html)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## 📌 Overview

This repository contains a compact 2.4 GHz monitoring platform based on an ESP32 and a single nRF24L01 transceiver.

The system combines two complementary measurements:

1. **Bluetooth Low Energy scanning**, performed by the ESP32 Bluetooth subsystem.
2. **Relative RF energy detection**, performed by the nRF24L01 while sequentially scanning frequencies from 2402 MHz to 2480 MHz.

A Processing 4 desktop application displays the measurements in real time and exports them to CSV files. MATLAB and Python scripts are included for offline visualization and analysis.

The project is intended for educational, experimental, and comparative analysis of wireless activity in the 2.4 GHz ISM band.

---

## ✨ Main Features

* Bluetooth Low Energy device discovery.
* BLE RSSI monitoring over time.
* Sequential RF scanning from 2402 MHz to 2480 MHz.
* One nRF24L01 module connected through the ESP32 VSPI bus.
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

---

## 🧩 System Architecture

```text
                         ┌──────────────────────────────┐
                         │            ESP32             │
                         │                              │
BLE devices ───────────► │  Integrated BLE receiver    │
                         │  - Device discovery          │
                         │  - Identification            │
                         │  - RSSI measurement           │
                         │                              │
2.4 GHz RF signals ────► │  Single nRF24L01 receiver   │
                         │  - Sequential channel scan   │
                         │  - RPD/CD energy detection   │
                         └──────────────┬───────────────┘
                                        │
                                        │ USB Serial
                                        ▼
                         ┌──────────────────────────────┐
                         │      Processing 4 GUI        │
                         │                              │
                         │  - RF detection spectrum     │
                         │  - RF history map            │
                         │  - BLE RSSI graph            │
                         │  - BLE device table          │
                         │  - CSV recording             │
                         └──────────────┬───────────────┘
                                        │
                                        │ CSV
                          ┌─────────────┴─────────────┐
                          ▼                           ▼
                 ┌────────────────┐          ┌────────────────┐
                 │     MATLAB     │          │     Python     │
                 │ Offline plots  │          │ Offline plots  │
                 │ and summaries  │          │ and summaries  │
                 └────────────────┘          └────────────────┘
```

---

## 🔧 Hardware

### Required Components

| Component                       | Quantity | Description                     |
| ------------------------------- | -------: | ------------------------------- |
| ESP32 development board         |        1 | Main controller and BLE scanner |
| nRF24L01 or nRF24L01+           |        1 | Relative RF energy detector     |
| 100 nF ceramic capacitor        |        1 | Local high-frequency decoupling |
| 10–47 µF electrolytic capacitor |        1 | nRF24L01 supply stabilization   |
| USB cable                       |        1 | Power and serial communication  |
| Breadboard or PCB               |        1 | Hardware assembly               |

> The nRF24L01 must be powered from **3.3 V**. Do not connect its VCC pin directly to 5 V.

---

## 🔌 nRF24L01 Connections

| nRF24L01 Pin |     ESP32 Pin |
| ------------ | ------------: |
| VCC          |         3.3 V |
| GND          |           GND |
| CE           |       GPIO 15 |
| CSN          |        GPIO 5 |
| SCK          |       GPIO 18 |
| MISO         |       GPIO 19 |
| MOSI         |       GPIO 23 |
| IRQ          | Not connected |

Place the 100 nF ceramic capacitor and the 10–47 µF electrolytic capacitor as close as possible to the nRF24L01 supply pins.

---

## 📡 RF Scanning Range

The nRF24L01 channel-to-frequency relationship is:

```text
Frequency [MHz] = 2400 + nRF24L01 channel
```

The firmware scans:

| nRF24L01 Channel | Frequency |
| ---------------: | --------: |
|                2 |  2402 MHz |
|                3 |  2403 MHz |
|              ... |       ... |
|               80 |  2480 MHz |

A single nRF24L01 sequentially scans all 79 frequencies.

Unlike the previous dual-radio implementation, this version does not divide the spectrum between VSPI and HSPI devices.

---

## 📊 Relative RF Energy Detection

The nRF24L01 does not provide a continuous calibrated RSSI value for arbitrary RF signals.

Instead, its RPD or carrier-detect function produces a binary observation:

```text
0 = Energy was not detected above the internal threshold
1 = Energy was detected above the internal threshold
```

For each frequency, the firmware performs 24 observation windows.

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

---

## 📈 RF Filtering

The firmware applies asymmetric filtering to improve the visual response:

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

The minimum nonzero raw measurement is approximately 4.17% because the firmware performs 24 observations per frequency.

---

## 📶 Bluetooth Low Energy Monitoring

Bluetooth Low Energy scanning is performed directly by the ESP32 BLE subsystem.

For each detected device, the firmware may report:

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

---

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

---

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

for RF measurements generated by the single-radio firmware.

---

## 📂 Repository Structure

```text
ESP32_BLE_RF24_Scanner/
│
├── firmware/
│   └── Scanner_BLE_RF24_Single_ESP32_v1.ino
│
├── processing/
│   └── Scanner_BLE_RF24_Single_Processing4_v1.pde
│
├── analysis/
│   ├── matlab/
│   │   └── leer_scanner_ble_rf24_single.m
│   │
│   └── python/
│       └── leer_scanner_ble_rf24_single.py
│
├── data/
│   └── example_measurement.csv
│
├── docs/
│   ├── connection_diagram.png
│   ├── interface_screenshot.png
│   └── system_architecture.png
│
├── LICENSE
└── README.md
```

---

## 📦 Software Requirements

### ESP32 Firmware

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

## 🚀 Firmware Installation

1. Install the ESP32 board package in Arduino IDE.
2. Install the `RF24` library by TMRh20.
3. Connect the nRF24L01 according to the wiring table.
4. Open:

```text
firmware/Scanner_BLE_RF24_Single_ESP32_v1.ino
```

5. Select the correct ESP32 board.
6. Select the correct serial port.
7. Compile and upload the firmware.
8. Close the Arduino Serial Monitor before opening the Processing interface.

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

## 🔬 Suggested Experiments

1. Compare the RF activity with and without a nearby Wi-Fi transmission.
2. Observe the BLE advertising frequencies at 2402, 2426, and 2480 MHz.
3. Move a BLE device away from the ESP32 and analyze its RSSI.
4. Rotate the BLE device and observe antenna-orientation effects.
5. Compare raw and filtered RF detection.
6. Modify the number of observations per channel.
7. Compare different attack and decay coefficients.
8. Compare scan performance using 1 Mbps and 2 Mbps RF24 data-rate settings.
9. Record a controlled transmission and analyze it in MATLAB or Python.
10. Compare the single-radio implementation with a dual-radio implementation.

---

## 🛠️ Suggested Future Improvements

* Add configurable RF observation-window parameters.
* Add automatic CSV filenames with timestamps.
* Add metadata describing the measurement configuration.
* Add a real-time raw-versus-filtered view.
* Add selectable RF frequency ranges.
* Add a configurable number of samples per channel.
* Add calibration experiments using a known RF source.
* Add SDR-based validation.
* Add Wi-Fi channel overlays.
* Add a frequency-selection tool for temporal analysis.
* Export figures automatically from Processing.
* Add a measurement-session configuration file.
* Add a portable PCB version.
* Add an enclosure for field measurements.

---

## 📖 Suggested Citation

```bibtex
@software{castro_esp32_ble_rf24_scanner_2026,
  author  = {Castro Lagos, Cristian Andrés},
  title   = {ESP32 BLE and 2.4 GHz RF Activity Scanner Using a Single nRF24L01},
  year    = {2026},
  url     = {https://github.com/CrissCCL/ESP32_BLE_RF24_Scanner},
  note    = {Firmware, Processing interface, and MATLAB/Python analysis tools}
}
```

---

## 👤 Author

**Cristian Andrés Castro Lagos — CrissCCL**

Electronics engineer working on embedded systems, instrumentation, digital signal processing, automation, and control systems.

* Portfolio: https://crissccl.github.io
* GitHub: https://github.com/CrissCCL
* LinkedIn: https://www.linkedin.com/in/cristianccl
* YouTube: https://www.youtube.com/@CrissCCL_eng

---

## 📄 License

This project is released under the MIT License.

See the [LICENSE](LICENSE) file for details.

---

## ⚠️ Disclaimer

This repository is intended for educational, research, and experimental use.

The system passively observes BLE advertisements and relative RF energy. It is not intended for unauthorized access, communication interception, device tracking, or interference with wireless systems.

Users are responsible for complying with applicable privacy, telecommunications, and data-protection regulations.

---

<div align="center">

### © CrissCCL 2026

Embedded systems, signal processing, instrumentation, and control.

</div>
