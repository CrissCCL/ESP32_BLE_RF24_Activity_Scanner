/*
  =====================================================================
  SCANNER BLE + DETECTOR RELATIVO DE ENERGÍA RF
  ESP32 + 1 nRF24L01 / nRF24L01+
  Versión 1.0
  © CrissCCL 2026
  =====================================================================

  CONEXIONES DEL nRF24L01

    SCK   GPIO 18
    MISO  GPIO 19
    MOSI  GPIO 23
    CE    GPIO 15
    CSN   GPIO 5
    VCC   3,3 V
    GND   GND

  PROTOCOLO SERIAL

    RF,frecuencia_MHz,deteccion_filtrada_pct,deteccion_cruda_pct
    BLE,MAC,RSSI_dBm,identificacion,canales_posibles,frecuencias_posibles
    FRAME,numero
    STATUS,mensaje

  INTERPRETACIÓN RF

  El nRF24L01 no entrega RSSI continuo.

  Para cada canal se realizan 24 observaciones binarias:

    0: no se detectó energía sobre el umbral RPD/CD.
    1: se detectó energía sobre el umbral RPD/CD.

  El porcentaje crudo corresponde a:

    detecciones / 24 * 100 %

  La resolución cruda es aproximadamente 4,17 %.

  El barrido con un único radio es secuencial:

    canal 2  -> 2402 MHz
    ...
    canal 80 -> 2480 MHz
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


// =====================================================================
// CONEXIÓN DEL ÚNICO nRF24L01
// =====================================================================

constexpr uint8_t RF_SCK  = 18;
constexpr uint8_t RF_MISO = 19;
constexpr uint8_t RF_MOSI = 23;

constexpr uint8_t RF_CE  = 15;
constexpr uint8_t RF_CSN = 5;

SPIClass spiRF(VSPI);

RF24 radio(
    RF_CE,
    RF_CSN,
    SPI_SPEED);


// =====================================================================
// DISTRIBUCIÓN DEL ESPECTRO
// =====================================================================

constexpr uint8_t CHANNEL_MIN = 2;
constexpr uint8_t CHANNEL_MAX = 80;

constexpr uint8_t CHANNEL_COUNT =
    CHANNEL_MAX -
    CHANNEL_MIN +
    1;


// =====================================================================
// ADQUISICIÓN RF
// =====================================================================

// 24 observaciones por canal.
// Resolución cruda aproximada: 100 / 24 = 4,17 %.
constexpr uint8_t SAMPLES_PER_CHANNEL = 24;

// Tiempo de escucha suficiente para el detector RPD/CD.
constexpr uint16_t SAMPLE_TIME_US = 256;
constexpr uint16_t SAMPLE_GAP_US  = 35;

// Filtro con ataque rápido y caída más lenta.
constexpr float FILTER_ATTACK_ALPHA = 0.85f;
constexpr float FILTER_DECAY_ALPHA  = 0.16f;

float filteredDetection[CHANNEL_COUNT] = {0.0f};

uint32_t frameNumber = 0;

bool radioIsPlusVariant = true;


// =====================================================================
// DIRECCIONES DE RECEPCIÓN
// =====================================================================

const uint8_t noiseAddresses[6][2] = {
  {0x55, 0x55},
  {0xAA, 0xAA},
  {0xA0, 0xAA},
  {0xAB, 0xAA},
  {0xAC, 0xAA},
  {0xAD, 0xAA}
};


// =====================================================================
// BLE
// =====================================================================

BLEScan* bleScan = nullptr;

// Duración de cada exploración BLE.
constexpr uint16_t BLE_SCAN_SECONDS = 1;

/*
  Con un solo nRF24L01, un barrido RF demora aproximadamente
  el doble que con dos radios trabajando simultáneamente.

  Dos barridos por escaneo BLE mantienen un equilibrio parecido
  a la versión dual que utilizaba cuatro barridos.
*/
constexpr uint8_t RF_SWEEPS_PER_BLE_SCAN = 2;

uint8_t sweepsSinceBLE = 0;


// =====================================================================
// FUNCIONES DE TEXTO
// =====================================================================

String sanitizeSerialField(
    String text)
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


String hexadecimal16(
    uint16_t value)
{
  char buffer[7];

  snprintf(
      buffer,
      sizeof(buffer),
      "0x%04X",
      value);

  return String(buffer);
}


// =====================================================================
// IDENTIFICACIÓN DE FABRICANTES BLE
// =====================================================================

String knownManufacturerName(
    uint16_t companyIdentifier)
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


// =====================================================================
// IDENTIFICACIÓN DE SERVICIOS BLE
// =====================================================================

String serviceDescription(
    String uuid)
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


// =====================================================================
// CONSTRUCCIÓN DE IDENTIFICACIÓN BLE
// =====================================================================

String buildBLEIdentification(
    BLEAdvertisedDevice& device)
{
  // 1. Nombre real del dispositivo.

  if (device.haveName()) {
    String name =
        String(
            device
                .getName()
                .c_str());

    name =
        sanitizeSerialField(
            name);

    if (
        name.length() > 0 &&
        name != "BLE anónimo") {
      return name;
    }
  }

  // 2. Datos del fabricante o iBeacon.

  if (device.haveManufacturerData()) {
    String manufacturerData =
        device.getManufacturerData();

    if (manufacturerData.length() >= 2) {
      const uint8_t byte0 =
          static_cast<uint8_t>(
              manufacturerData[0]);

      const uint8_t byte1 =
          static_cast<uint8_t>(
              manufacturerData[1]);

      const uint16_t companyIdentifier =
          static_cast<uint16_t>(byte0) |
          (
              static_cast<uint16_t>(byte1)
              << 8);

      if (
          companyIdentifier == 0x004C &&
          manufacturerData.length() >= 4 &&
          static_cast<uint8_t>(
              manufacturerData[2]) == 0x02 &&
          static_cast<uint8_t>(
              manufacturerData[3]) == 0x15) {
        return "iBeacon Apple";
      }

      String manufacturerName =
          knownManufacturerName(
              companyIdentifier);

      if (manufacturerName.length() > 0) {
        return
            manufacturerName +
            " BLE";
      }

      return
          "Fabricante " +
          hexadecimal16(
              companyIdentifier);
    }
  }

  // 3. Servicio anunciado.

  if (device.haveServiceUUID()) {
    String uuid =
        String(
            device
                .getServiceUUID()
                .toString()
                .c_str());

    String description =
        serviceDescription(
            uuid);

    if (description.length() > 0) {
      return description;
    }

    if (uuid.length() > 20) {
      uuid =
          uuid.substring(
              0,
              20);
    }

    return
        "Servicio " +
        uuid;
  }

  return "BLE anónimo";
}


// =====================================================================
// CALLBACK BLE
// =====================================================================

class BLECallbacks :
    public BLEAdvertisedDeviceCallbacks
{
  void onResult(
      BLEAdvertisedDevice device) override
  {
    String address =
        String(
            device
                .getAddress()
                .toString()
                .c_str());

    String identification =
        sanitizeSerialField(
            buildBLEIdentification(
                device));

    Serial.print("BLE,");
    Serial.print(address);
    Serial.print(",");

    Serial.print(
        device.getRSSI());

    Serial.print(",");
    Serial.print(identification);

    /*
      El escáner BLE de alto nivel no informa el canal exacto
      donde se recibió el anuncio.
    */
    Serial.print(",37|38|39,");
    Serial.println("2402|2426|2480");
  }
};


// =====================================================================
// CONFIGURACIÓN DEL nRF24L01
// =====================================================================

bool configureRadio()
{
  spiRF.begin(
      RF_SCK,
      RF_MISO,
      RF_MOSI,
      RF_CSN);

  if (!radio.begin(&spiRF)) {
    Serial.println(
        "STATUS,ERROR nRF24L01 no detectado");

    return false;
  }

  radio.stopListening();

  radio.setAutoAck(false);
  radio.disableCRC();

  radio.setAddressWidth(2);
  radio.setPayloadSize(32);

  /*
    Se usa 2 Mbps para obtener una recepción más amplia
    como detector general de actividad.
  */
  radio.setDataRate(
      RF24_2MBPS);

  radio.setPALevel(
      RF24_PA_MIN);

  for (
      uint8_t pipe = 0;
      pipe < 6;
      pipe++) {
    radio.openReadingPipe(
        pipe,
        noiseAddresses[pipe]);
  }

  radio.flush_rx();
  radio.flush_tx();

  radioIsPlusVariant =
      radio.isPVariant();

  // Primera transición RX para estabilizar el receptor.

  radio.startListening();

  delayMicroseconds(200);

  radio.stopListening();
  radio.flush_rx();

  Serial.print(
      "STATUS,nRF24L01 conectado; detector ");

  Serial.println(
      radioIsPlusVariant
      ? "RPD"
      : "CD");

  return true;
}


// =====================================================================
// CONFIGURACIÓN BLE
// =====================================================================

void initializeBLE()
{
  BLEDevice::init("");

  bleScan =
      BLEDevice::getScan();

  bleScan->setAdvertisedDeviceCallbacks(
      new BLECallbacks(),
      true);

  bleScan->setActiveScan(true);

  /*
    Unidades de 0,625 ms.

    Intervalo:
      100 × 0,625 ms = 62,5 ms

    Ventana:
       99 × 0,625 ms = 61,875 ms
  */
  bleScan->setInterval(100);
  bleScan->setWindow(99);

  Serial.println(
      "STATUS,BLE inicializado");
}


// =====================================================================
// DETECTOR RF
// =====================================================================

bool readEnergyDetector()
{
  bool detected =
      radioIsPlusVariant
      ? radio.testRPD()
      : radio.testCarrier();

  /*
    available() aporta una segunda vía de detección
    cuando el receptor llega a colocar datos en la FIFO.
  */
  if (radio.available()) {
    detected = true;
  }

  return detected;
}


// =====================================================================
// MEDICIÓN DE UN CANAL
// =====================================================================

float measureChannel(
    uint8_t channel)
{
  uint16_t detections = 0;

  radio.setChannel(channel);

  for (
      uint8_t sample = 0;
      sample < SAMPLES_PER_CHANNEL;
      sample++) {
    radio.flush_rx();

    radio.startListening();

    delayMicroseconds(
        SAMPLE_TIME_US);

    if (readEnergyDetector()) {
      detections++;
    }

    radio.stopListening();
    radio.flush_rx();

    delayMicroseconds(
        SAMPLE_GAP_US);
  }

  return
      100.0f *
      static_cast<float>(detections) /
      static_cast<float>(
          SAMPLES_PER_CHANNEL);
}


// =====================================================================
// FILTRADO Y ENVÍO DE LA MEDICIÓN
// =====================================================================

void processAndSendMeasurement(
    uint8_t channel,
    float rawDetection)
{
  const uint8_t index =
      channel -
      CHANNEL_MIN;

  const float alpha =
      rawDetection >
      filteredDetection[index]
      ? FILTER_ATTACK_ALPHA
      : FILTER_DECAY_ALPHA;

  filteredDetection[index] =
      alpha *
      rawDetection +
      (
          1.0f -
          alpha
      ) *
      filteredDetection[index];

  const uint16_t frequencyMHz =
      2400 +
      channel;

  Serial.print("RF,");
  Serial.print(frequencyMHz);
  Serial.print(",");

  Serial.print(
      filteredDetection[index],
      2);

  Serial.print(",");

  Serial.println(
      rawDetection,
      2);
}


// =====================================================================
// BARRIDO RF SECUENCIAL
// =====================================================================

void performRFSweep()
{
  for (
      uint8_t channel = CHANNEL_MIN;
      channel <= CHANNEL_MAX;
      channel++) {
    const float rawDetection =
        measureChannel(
            channel);

    processAndSendMeasurement(
        channel,
        rawDetection);
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

  Serial.println(
      "STATUS,Escaneando BLE");

  bleScan->start(
      BLE_SCAN_SECONDS,
      false);

  bleScan->clearResults();

  Serial.println(
      "STATUS,Escaneo BLE finalizado");
}


// =====================================================================
// SETUP
// =====================================================================

void setup()
{
  Serial.begin(
      SERIAL_BAUD);

  delay(1200);

  Serial.println();

  Serial.println(
      "STATUS,Iniciando detector RF con un nRF24L01 y scanner BLE");

  const bool radioReady =
      configureRadio();

  initializeBLE();

  if (!radioReady) {
    Serial.println(
        "STATUS,Revise alimentación cableado y capacitores del nRF24L01");

    while (true) {
      delay(1000);
    }
  }

  Serial.println(
      "STATUS,Sistema listo");
}


// =====================================================================
// LOOP
// =====================================================================

void loop()
{
  performRFSweep();

  sweepsSinceBLE++;

  if (
      sweepsSinceBLE >=
      RF_SWEEPS_PER_BLE_SCAN) {
    sweepsSinceBLE = 0;

    performBLEScan();
  }

  delay(5);
}