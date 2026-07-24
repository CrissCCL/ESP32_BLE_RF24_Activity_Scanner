/*
  =====================================================================
  SCANNER BLE + MONITOR RF DE 2,4 GHz
  ESP32 + 2 nRF24L01 / nRF24L01+
  Versión 4
  =====================================================================

  Conexiones conservadas:

    RF24 radioVSPI(15, 5, SPI_SPEED);
    RF24 radioHSPI(22, 21, SPI_SPEED);

  VSPI:
    SCK  GPIO 18
    MISO GPIO 19
    MOSI GPIO 23
    CE   GPIO 15
    CSN  GPIO 5

  HSPI:
    SCK  GPIO 14
    MISO GPIO 12
    MOSI GPIO 13
    CE   GPIO 22
    CSN  GPIO 21

  Protocolo serial:
    RF1,frecuencia_MHz,ocupacion_filtrada_pct,ocupacion_cruda_pct
    RF2,frecuencia_MHz,ocupacion_filtrada_pct,ocupacion_cruda_pct
    BLE,MAC,RSSI_dBm,identificacion,canales_posibles,frecuencias_posibles
    FRAME,numero
    STATUS,mensaje

  Notas:
    - Los nRF24 entregan actividad/ocupación relativa, no RSSI continuo.
    - El RSSI BLE sí se expresa en dBm.
    - El scanner BLE de alto nivel no informa el canal exacto en que se
      recibió cada anuncio. Los canales posibles son:
          37 = 2402 MHz
          38 = 2426 MHz
          39 = 2480 MHz
*/

#include <Arduino.h>
#include <SPI.h>
#include <RF24.h>

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>

// =====================================================================
// CONFIGURACIÓN GENERAL
// =====================================================================

constexpr uint32_t SERIAL_BAUD = 115200;
constexpr uint32_t SPI_SPEED   = 4000000;

// VSPI
constexpr uint8_t VSPI_SCK  = 18;
constexpr uint8_t VSPI_MISO = 19;
constexpr uint8_t VSPI_MOSI = 23;
constexpr uint8_t VSPI_CE   = 15;
constexpr uint8_t VSPI_CSN  = 5;

// HSPI
constexpr uint8_t HSPI_SCK  = 14;
constexpr uint8_t HSPI_MISO = 12;
constexpr uint8_t HSPI_MOSI = 13;
constexpr uint8_t HSPI_CE   = 22;
constexpr uint8_t HSPI_CSN  = 21;

SPIClass spiVSPI(VSPI);
SPIClass spiHSPI(HSPI);

RF24 radioVSPI(VSPI_CE, VSPI_CSN, SPI_SPEED);
RF24 radioHSPI(HSPI_CE, HSPI_CSN, SPI_SPEED);

// =====================================================================
// DISTRIBUCIÓN DEL ESPECTRO
// =====================================================================

constexpr uint8_t CHANNEL_MIN = 2;
constexpr uint8_t CHANNEL_MAX = 80;

constexpr uint8_t VSPI_CHANNEL_MIN = 2;
constexpr uint8_t VSPI_CHANNEL_MAX = 41;

constexpr uint8_t HSPI_CHANNEL_MIN = 42;
constexpr uint8_t HSPI_CHANNEL_MAX = 80;

constexpr uint8_t CHANNEL_COUNT =
    CHANNEL_MAX - CHANNEL_MIN + 1;

constexpr uint8_t VSPI_CHANNEL_COUNT =
    VSPI_CHANNEL_MAX - VSPI_CHANNEL_MIN + 1;

constexpr uint8_t HSPI_CHANNEL_COUNT =
    HSPI_CHANNEL_MAX - HSPI_CHANNEL_MIN + 1;

// =====================================================================
// ADQUISICIÓN RF
// =====================================================================

// 24 observaciones: resolución cruda de aproximadamente 4,17 %.
constexpr uint8_t SAMPLES_PER_CHANNEL = 24;

// Ventana mayor a 128 us para dar tiempo al detector RPD/CD.
constexpr uint16_t SAMPLE_TIME_US = 256;
constexpr uint16_t SAMPLE_GAP_US  = 35;

// Ataque rápido y caída lenta.
constexpr float FILTER_ATTACK_ALPHA = 0.85f;
constexpr float FILTER_DECAY_ALPHA  = 0.16f;

float filteredOccupancy[CHANNEL_COUNT] = {0.0f};

uint32_t frameNumber = 0;

// Direcciones usadas para abrir las seis tuberías receptoras.
const uint8_t noiseAddresses[6][2] = {
  {0x55, 0x55},
  {0xAA, 0xAA},
  {0xA0, 0xAA},
  {0xAB, 0xAA},
  {0xAC, 0xAA},
  {0xAD, 0xAA}
};

bool radioVSPIIsPlus = true;
bool radioHSPIIsPlus = true;

// =====================================================================
// BLE
// =====================================================================

BLEScan* bleScan = nullptr;

constexpr uint16_t BLE_SCAN_SECONDS = 1;
constexpr uint8_t RF_SWEEPS_PER_BLE_SCAN = 4;

uint8_t sweepsSinceBLE = 0;

// =====================================================================
// TEXTO
// =====================================================================

String sanitizeSerialField(String text)
{
  text.replace(",", " ");
  text.replace("\n", " ");
  text.replace("\r", " ");
  text.trim();

  if (text.length() == 0) {
    return "BLE anónimo";
  }

  if (text.length() > 48) {
    text = text.substring(0, 48);
  }

  return text;
}

String hexadecimal16(uint16_t value)
{
  char buffer[7];
  snprintf(buffer, sizeof(buffer), "0x%04X", value);
  return String(buffer);
}

String knownManufacturerName(uint16_t companyIdentifier)
{
  switch (companyIdentifier) {
    case 0x004C:
      return "Apple";

    case 0x0006:
      return "Microsoft";

    case 0x0075:
      return "Samsung";

    case 0x00E0:
      return "Google";

    case 0x0059:
      return "Nordic Semiconductor";

    default:
      return "";
  }
}

String serviceDescription(String uuid)
{
  uuid.toLowerCase();

  if (uuid.indexOf("0000180f") >= 0) {
    return "Servicio batería";
  }

  if (uuid.indexOf("0000180d") >= 0) {
    return "Sensor frecuencia cardíaca";
  }

  if (uuid.indexOf("0000180a") >= 0) {
    return "Información de dispositivo";
  }

  if (uuid.indexOf("00001812") >= 0) {
    return "Dispositivo HID";
  }

  if (uuid.indexOf("0000181a") >= 0) {
    return "Sensor ambiental";
  }

  if (uuid.indexOf("00001809") >= 0) {
    return "Termómetro BLE";
  }

  if (uuid.indexOf("0000feaa") >= 0) {
    return "Beacon Eddystone";
  }

  return "";
}

String buildBLEIdentification(BLEAdvertisedDevice& device)
{
  // 1. Nombre real
  if (device.haveName()) {
    String name = String(device.getName().c_str());
    name = sanitizeSerialField(name);

    if (name.length() > 0 && name != "BLE anónimo") {
      return name;
    }
  }

  // 2. Fabricante / iBeacon
  if (device.haveManufacturerData()) {
    String manufacturerData = device.getManufacturerData();

    if (manufacturerData.length() >= 2) {
      const uint8_t byte0 =
          static_cast<uint8_t>(manufacturerData[0]);

      const uint8_t byte1 =
          static_cast<uint8_t>(manufacturerData[1]);

      const uint16_t companyIdentifier =
          static_cast<uint16_t>(byte0) |
          (static_cast<uint16_t>(byte1) << 8);

      if (
          companyIdentifier == 0x004C &&
          manufacturerData.length() >= 4 &&
          static_cast<uint8_t>(manufacturerData[2]) == 0x02 &&
          static_cast<uint8_t>(manufacturerData[3]) == 0x15) {
        return "iBeacon Apple";
      }

      String manufacturerName =
          knownManufacturerName(companyIdentifier);

      if (manufacturerName.length() > 0) {
        return manufacturerName + " BLE";
      }

      return "Fabricante " + hexadecimal16(companyIdentifier);
    }
  }

  // 3. Servicio anunciado
  if (device.haveServiceUUID()) {
    String uuid =
        String(device.getServiceUUID().toString().c_str());

    String description =
        serviceDescription(uuid);

    if (description.length() > 0) {
      return description;
    }

    if (uuid.length() > 20) {
      uuid = uuid.substring(0, 20);
    }

    return "Servicio " + uuid;
  }

  return "BLE anónimo";
}

// =====================================================================
// CALLBACK BLE
// =====================================================================

class BLECallbacks : public BLEAdvertisedDeviceCallbacks
{
  void onResult(BLEAdvertisedDevice device) override
  {
    String address =
        String(device.getAddress().toString().c_str());

    String identification =
        sanitizeSerialField(
            buildBLEIdentification(device)
        );

    Serial.print("BLE,");
    Serial.print(address);
    Serial.print(",");
    Serial.print(device.getRSSI());
    Serial.print(",");
    Serial.print(identification);
    Serial.print(",37|38|39,");
    Serial.println("2402|2426|2480");
  }
};

// =====================================================================
// CONFIGURACIÓN RF24
// =====================================================================

bool configureRadio(
    RF24& radio,
    SPIClass& spiBus,
    const char* radioName,
    bool& isPlusVariant)
{
  if (!radio.begin(&spiBus)) {
    Serial.print("STATUS,ERROR ");
    Serial.print(radioName);
    Serial.println(" no detectado");
    return false;
  }

  radio.stopListening();

  radio.setAutoAck(false);
  radio.disableCRC();
  radio.setAddressWidth(2);
  radio.setPayloadSize(32);

  // Mayor ancho de recepción para un detector general de actividad.
  radio.setDataRate(RF24_2MBPS);
  radio.setPALevel(RF24_PA_MIN);

  for (uint8_t pipe = 0; pipe < 6; pipe++) {
    radio.openReadingPipe(pipe, noiseAddresses[pipe]);
  }

  radio.flush_rx();
  radio.flush_tx();

  isPlusVariant = radio.isPVariant();

  // Primera transición RX para estabilizar el receptor.
  radio.startListening();
  delayMicroseconds(200);
  radio.stopListening();
  radio.flush_rx();

  Serial.print("STATUS,");
  Serial.print(radioName);
  Serial.print(" conectado; detector ");
  Serial.println(isPlusVariant ? "RPD" : "CD");

  return true;
}

bool initializeRadios()
{
  spiVSPI.begin(
      VSPI_SCK,
      VSPI_MISO,
      VSPI_MOSI,
      VSPI_CSN);

  spiHSPI.begin(
      HSPI_SCK,
      HSPI_MISO,
      HSPI_MOSI,
      HSPI_CSN);

  const bool vspiReady =
      configureRadio(
          radioVSPI,
          spiVSPI,
          "nRF24L01 VSPI",
          radioVSPIIsPlus);

  const bool hspiReady =
      configureRadio(
          radioHSPI,
          spiHSPI,
          "nRF24L01 HSPI",
          radioHSPIIsPlus);

  return vspiReady && hspiReady;
}

// =====================================================================
// CONFIGURACIÓN BLE
// =====================================================================

void initializeBLE()
{
  BLEDevice::init("");

  bleScan = BLEDevice::getScan();

  bleScan->setAdvertisedDeviceCallbacks(
      new BLECallbacks(),
      true);

  bleScan->setActiveScan(true);

  // Unidades de 0,625 ms.
  bleScan->setInterval(100);
  bleScan->setWindow(99);

  Serial.println("STATUS,BLE inicializado");
}

// =====================================================================
// DETECTOR RF
// =====================================================================

bool readEnergyDetector(
    RF24& radio,
    bool isPlusVariant)
{
  bool detected =
      isPlusVariant
      ? radio.testRPD()
      : radio.testCarrier();

  // available() aporta una segunda vía de detección si el receptor
  // llegó a colocar datos en FIFO.
  if (radio.available()) {
    detected = true;
  }

  return detected;
}

void measureChannelPair(
    uint8_t channelVSPI,
    bool useVSPI,
    uint8_t channelHSPI,
    bool useHSPI,
    float& occupancyVSPI,
    float& occupancyHSPI)
{
  uint16_t detectionsVSPI = 0;
  uint16_t detectionsHSPI = 0;

  if (useVSPI) {
    radioVSPI.setChannel(channelVSPI);
  }

  if (useHSPI) {
    radioHSPI.setChannel(channelHSPI);
  }

  for (
      uint8_t sample = 0;
      sample < SAMPLES_PER_CHANNEL;
      sample++) {
    if (useVSPI) {
      radioVSPI.flush_rx();
      radioVSPI.startListening();
    }

    if (useHSPI) {
      radioHSPI.flush_rx();
      radioHSPI.startListening();
    }

    // Ambos radios observan simultáneamente.
    delayMicroseconds(SAMPLE_TIME_US);

    if (
        useVSPI &&
        readEnergyDetector(
            radioVSPI,
            radioVSPIIsPlus)) {
      detectionsVSPI++;
    }

    if (
        useHSPI &&
        readEnergyDetector(
            radioHSPI,
            radioHSPIIsPlus)) {
      detectionsHSPI++;
    }

    if (useVSPI) {
      radioVSPI.stopListening();
      radioVSPI.flush_rx();
    }

    if (useHSPI) {
      radioHSPI.stopListening();
      radioHSPI.flush_rx();
    }

    delayMicroseconds(SAMPLE_GAP_US);
  }

  occupancyVSPI =
      useVSPI
      ? (
          100.0f *
          static_cast<float>(detectionsVSPI) /
          static_cast<float>(SAMPLES_PER_CHANNEL)
        )
      : 0.0f;

  occupancyHSPI =
      useHSPI
      ? (
          100.0f *
          static_cast<float>(detectionsHSPI) /
          static_cast<float>(SAMPLES_PER_CHANNEL)
        )
      : 0.0f;
}

void processAndSendMeasurement(
    const char* messageType,
    uint8_t channel,
    float rawOccupancy)
{
  const uint8_t index =
      channel - CHANNEL_MIN;

  const float alpha =
      rawOccupancy >
      filteredOccupancy[index]
      ? FILTER_ATTACK_ALPHA
      : FILTER_DECAY_ALPHA;

  filteredOccupancy[index] =
      alpha * rawOccupancy +
      (1.0f - alpha) *
      filteredOccupancy[index];

  const uint16_t frequencyMHz =
      2400 + channel;

  Serial.print(messageType);
  Serial.print(",");
  Serial.print(frequencyMHz);
  Serial.print(",");
  Serial.print(filteredOccupancy[index], 2);
  Serial.print(",");
  Serial.println(rawOccupancy, 2);
}

void performDualRFSweep()
{
  const uint8_t maximumPairs =
      VSPI_CHANNEL_COUNT >
      HSPI_CHANNEL_COUNT
      ? VSPI_CHANNEL_COUNT
      : HSPI_CHANNEL_COUNT;

  for (
      uint8_t pairIndex = 0;
      pairIndex < maximumPairs;
      pairIndex++) {
    const bool useVSPI =
        pairIndex < VSPI_CHANNEL_COUNT;

    const bool useHSPI =
        pairIndex < HSPI_CHANNEL_COUNT;

    const uint8_t channelVSPI =
        VSPI_CHANNEL_MIN + pairIndex;

    const uint8_t channelHSPI =
        HSPI_CHANNEL_MIN + pairIndex;

    float occupancyVSPI = 0.0f;
    float occupancyHSPI = 0.0f;

    measureChannelPair(
        channelVSPI,
        useVSPI,
        channelHSPI,
        useHSPI,
        occupancyVSPI,
        occupancyHSPI);

    if (useVSPI) {
      processAndSendMeasurement(
          "RF1",
          channelVSPI,
          occupancyVSPI);
    }

    if (useHSPI) {
      processAndSendMeasurement(
          "RF2",
          channelHSPI,
          occupancyHSPI);
    }
  }

  frameNumber++;

  Serial.print("FRAME,");
  Serial.println(frameNumber);
}

// =====================================================================
// ESCANEO BLE
// =====================================================================

void performBLEScan()
{
  if (bleScan == nullptr) {
    return;
  }

  Serial.println("STATUS,Escaneando BLE");

  bleScan->start(
      BLE_SCAN_SECONDS,
      false);

  bleScan->clearResults();

  Serial.println("STATUS,Escaneo BLE finalizado");
}

// =====================================================================
// SETUP / LOOP
// =====================================================================

void setup()
{
  Serial.begin(SERIAL_BAUD);
  delay(1200);

  Serial.println();
  Serial.println(
      "STATUS,Iniciando monitor RF dual y scanner BLE");

  const bool radiosReady =
      initializeRadios();

  initializeBLE();

  if (!radiosReady) {
    Serial.println(
        "STATUS,Revise alimentación cableado y capacitores nRF24");

    while (true) {
      delay(1000);
    }
  }

  Serial.println("STATUS,Sistema listo");
}

void loop()
{
  performDualRFSweep();

  sweepsSinceBLE++;

  if (
      sweepsSinceBLE >=
      RF_SWEEPS_PER_BLE_SCAN) {
    sweepsSinceBLE = 0;
    performBLEScan();
  }

  delay(5);
}
