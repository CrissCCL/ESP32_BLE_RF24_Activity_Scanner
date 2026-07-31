/*
  =====================================================================
  SCANNER BLE + DETECTOR RELATIVO DE ENERGÍA RF EN 2,4 GHz
  PROCESSING 4
  Versión 6.4
  © CrissCCL 2026
  =====================================================================

  INTERPRETACIÓN DEL PANEL RF

  El nRF24L01 no entrega potencia calibrada en dBm.

  Para cada frecuencia, el firmware realiza 24 observaciones binarias:

    0 = no se detectó energía sobre el umbral RPD/CD.
    1 = se detectó energía sobre el umbral RPD/CD.

  El valor crudo se calcula como:

    detecciones / 24 * 100 %

  Por lo tanto, la resolución cruda es aproximadamente:

    100 / 24 = 4,17 %

  La barra presentada en la interfaz corresponde al valor filtrado.
  No representa potencia, RSSI ni porcentaje exacto de tiempo ocupado.

  ESCALA FIJA DEL PANEL RF

    0–100 %

  Este límite es únicamente visual y no representa
  un umbral físico del receptor.

  CONTROLES RSSI

    Tiempo:
      15, 30, 60, 120 y 300 segundos.

    Eje vertical:
      límites mínimo y máximo ajustables en pasos de 5 dBm.

  TECLAS

    G = iniciar o finalizar registro CSV.
    R = reiniciar máximos RF.
    C = limpiar dispositivos BLE e historial RSSI.
    H = limpiar mapa temporal RF.
*/

import processing.serial.*;
import java.io.File;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;


// =====================================================================
// SERIAL
// =====================================================================

final int SERIAL_BAUD = 115200;

Serial serialPort;

String[] serialPorts = new String[0];

int selectedPortIndex = -1;

boolean serialConnected = false;
boolean portMenuOpen = false;

String connectedPortName = "";

String statusMessage =
  "Presione ACTUALIZAR, seleccione el ESP32 y conecte";


// =====================================================================
// PRIVACIDAD DE DIRECCIONES BLE
// =====================================================================

/*
  false:
    La interfaz muestra:
    XX:XX:XX:XX:AB:CD

  true:
    La interfaz muestra la dirección completa.
*/
final boolean SHOW_FULL_BLE_ADDRESS = false;

/*
  true:
    El CSV conserva la dirección completa.

  false:
    El CSV guarda la dirección enmascarada.
*/
final boolean EXPORT_FULL_BLE_ADDRESS = true;


// =====================================================================
// CONTROLES DEL ENCABEZADO
// =====================================================================

float selectorX;
float selectorY;
float selectorW;
float selectorH;

float refreshX;
float refreshY;
float refreshW;
float refreshH;

float connectX;
float connectY;
float connectW;
float connectH;

float saveX;
float saveY;
float saveW;
float saveH;

final float PORT_ROW_HEIGHT = 28;


// =====================================================================
// DETECCIÓN RF
// =====================================================================

final int FREQUENCY_MIN = 2402;
final int FREQUENCY_MAX = 2480;

final int FREQUENCY_COUNT =
  FREQUENCY_MAX -
  FREQUENCY_MIN +
  1;

final int RADIO_UNKNOWN = 0;
final int RADIO_VSPI = 1;
final int RADIO_HSPI = 2;

/*
  Valor filtrado recibido desde el firmware.
*/
float[] rfValues =
  new float[FREQUENCY_COUNT];

/*
  Valor crudo recibido desde el firmware.
*/
float[] rfRawValues =
  new float[FREQUENCY_COUNT];

/*
  Máximo filtrado registrado por frecuencia.
*/
float[] rfPeaks =
  new float[FREQUENCY_COUNT];

int[] rfSource =
  new int[FREQUENCY_COUNT];

/*
  Escala vertical fija de la gráfica de detección relativa RF.

  El valor representa únicamente el límite visual superior
  del eje y no un umbral físico del receptor.
*/
final float RF_DISPLAY_MAXIMUM = 100.0;

float rfDisplayMaximum = RF_DISPLAY_MAXIMUM;
// =====================================================================
// MAPA TEMPORAL RF
// =====================================================================

final int HISTORY_ROWS = 90;

float[][] rfHistory =
  new float[HISTORY_ROWS][FREQUENCY_COUNT];

int historyWriteIndex = 0;


// =====================================================================
// INFORMACIÓN DE BARRIDOS
// =====================================================================

long frameNumber = 0;

int lastFrameMillis = 0;

float filteredSweepRate = 0;


// =====================================================================
// CONFIGURACIÓN BLE Y RSSI
// =====================================================================

final int BLE_ACTIVE_TIMEOUT_MS = 12000;

/*
  Se conservan dispositivos durante seis minutos para permitir
  utilizar una ventana RSSI de hasta cinco minutos.
*/
final int BLE_REMOVE_TIMEOUT_MS = 360000;

final int RSSI_HISTORY_SIZE = 1200;

final int RSSI_LINE_GAP_MS = 8000;

final int[] RSSI_TIME_OPTIONS_MS = {
  15000,
  30000,
  60000,
  120000,
  300000
};

int rssiTimeOptionIndex = 2;

int rssiTimeWindowMs =
  RSSI_TIME_OPTIONS_MS[rssiTimeOptionIndex];

float rssiMinDbm = -100;
float rssiMaxDbm = -30;

final float RSSI_DBM_STEP = 5;

final float RSSI_MIN_ALLOWED_DBM = -120;
final float RSSI_MAX_ALLOWED_DBM = 0;

final float RSSI_MIN_VERTICAL_SPAN_DB = 10;


// =====================================================================
// POSICIONES DE LOS CONTROLES RSSI
// =====================================================================

float rssiTimeMinusX;
float rssiTimePlusX;

float rssiMinMinusX;
float rssiMinPlusX;

float rssiMaxMinusX;
float rssiMaxPlusX;

float rssiControlY;

final float RSSI_CONTROL_BUTTON_W = 22;
final float RSSI_CONTROL_BUTTON_H = 22;


// =====================================================================
// DISPOSITIVOS BLE
// =====================================================================

int nextBLEDeviceId = 1;

final String DEFAULT_BLE_CHANNELS =
  "37 / 38 / 39";

final String DEFAULT_BLE_FREQUENCIES =
  "2402 / 2426 / 2480 MHz";

HashMap<String, BLEDeviceInfo> bleDevices =
  new HashMap<String, BLEDeviceInfo>();


// =====================================================================
// CLASE PARA DISPOSITIVOS BLE
// =====================================================================

class BLEDeviceInfo {

  int deviceId;

  String address;
  String identification;

  String possibleChannels;
  String possibleFrequencies;

  float filteredRSSI;

  int packets;
  int lastSeenMillis;

  int[] rssiHistoryTime =
    new int[RSSI_HISTORY_SIZE];

  float[] rssiHistoryValue =
    new float[RSSI_HISTORY_SIZE];

  int rssiHistoryWriteIndex = 0;
  int rssiHistoryCount = 0;


  BLEDeviceInfo(
    String address,
    String identification,
    int rawRSSI,
    String possibleChannels,
    String possibleFrequencies
  ) {
    this.deviceId = nextBLEDeviceId++;
    this.address = address;

    this.identification =
      cleanBLEIdentification(
        identification
      );

    this.possibleChannels =
      cleanPossibleChannels(
        possibleChannels
      );

    this.possibleFrequencies =
      cleanPossibleFrequencies(
        possibleFrequencies
      );

    this.filteredRSSI = rawRSSI;

    this.packets = 1;
    this.lastSeenMillis = millis();

    addRSSISample();
  }


  void update(
    String newIdentification,
    int rawRSSI,
    String newChannels,
    String newFrequencies
  ) {
    filteredRSSI =
      0.25 * rawRSSI +
      0.75 * filteredRSSI;

    String cleaned =
      cleanBLEIdentification(
        newIdentification
      );

    int currentRank =
      identificationRank(
        identification
      );

    int newRank =
      identificationRank(
        cleaned
      );

    if (
      newRank > currentRank ||
      (
        newRank == currentRank &&
        currentRank <= 1 &&
        !cleaned.equals(identification)
      )
    ) {
      identification = cleaned;
    }

    possibleChannels =
      cleanPossibleChannels(
        newChannels
      );

    possibleFrequencies =
      cleanPossibleFrequencies(
        newFrequencies
      );

    packets++;
    lastSeenMillis = millis();

    addRSSISample();
  }


  void addRSSISample() {
    rssiHistoryTime[
      rssiHistoryWriteIndex
    ] = millis();

    rssiHistoryValue[
      rssiHistoryWriteIndex
    ] = filteredRSSI;

    rssiHistoryWriteIndex =
      (
        rssiHistoryWriteIndex + 1
      ) % RSSI_HISTORY_SIZE;

    rssiHistoryCount =
      min(
        rssiHistoryCount + 1,
        RSSI_HISTORY_SIZE
      );
  }


  int historyIndexFromOldest(
    int position
  ) {
    return
      (
        rssiHistoryWriteIndex -
        rssiHistoryCount +
        position +
        RSSI_HISTORY_SIZE
      ) % RSSI_HISTORY_SIZE;
  }


  boolean isActive() {
    return
      millis() -
      lastSeenMillis <
      BLE_ACTIVE_TIMEOUT_MS;
  }


  boolean isVisibleInRSSIGraph() {
    return
      millis() -
      lastSeenMillis <=
      rssiTimeWindowMs;
  }


  float ageSeconds() {
    return
      (
        millis() -
        lastSeenMillis
      ) / 1000.0;
  }
}


// =====================================================================
// REGISTRO CSV
// =====================================================================

boolean recordingCSV = false;
boolean waitingForSavePath = false;

PrintWriter csvWriter;

String csvFilename = "";
String csvFullPath = "";


// =====================================================================
// COLORES
// =====================================================================

color backgroundColor = #10151D;

color panelColor = #1A222D;
color panelSecondaryColor = #202A37;
color borderColor = #39485A;

color primaryTextColor = #EDF2F7;
color secondaryTextColor = #9EADBF;
color gridColor = #3B4858;

color vspiColor = #31B7B4;
color hspiColor = #708FFF;

color goodColor = #52C987;
color warningColor = #F2B134;
color dangerColor = #E6535C;

color peakColor = #F4F6F8;


// =====================================================================
// SETUP
// =====================================================================

void setup() {
  size(
    1280,
    820
  );

  smooth(4);

  surface.setTitle(
    "Scanner BLE y detector relativo de energía RF de 2,4 GHz"
  );

  /*
    El redimensionamiento se bloquea para evitar que se generen
    gráficos con dimensiones incompatibles.
  */
  surface.setResizable(false);

  textFont(
    createFont(
      "SansSerif",
      13
    )
  );

  initializeData();
  refreshSerialPorts();
}


// =====================================================================
// INICIALIZACIÓN
// =====================================================================

void initializeData() {
  for (
    int index = 0;
    index < FREQUENCY_COUNT;
    index++
  ) {
    rfValues[index] = 0;
    rfRawValues[index] = 0;
    rfPeaks[index] = 0;
    rfSource[index] = RADIO_UNKNOWN;

    for (
      int row = 0;
      row < HISTORY_ROWS;
      row++
    ) {
      rfHistory[row][index] = 0;
    }
  }
}


// =====================================================================
// DIBUJO PRINCIPAL
// =====================================================================

void draw() {
  background(backgroundColor);

  removeExpiredBLEDevices();
  updateRFDisplayScale();

  final float margin = 12;
  final float gap = 10;

  final float headerHeight = 76;
  final float footerHeight = 24;

  /*
    Panel BLE bajo para entregar más altura a los gráficos.
  */
  final float blePanelHeight = 136;

  final float availableWidth =
    width -
    2 * margin;

  final float headerY =
    margin;

  final float mainY =
    headerY +
    headerHeight +
    gap;

  final float footerY =
    height -
    margin -
    footerHeight;

  final float blePanelY =
    footerY -
    gap -
    blePanelHeight;

  final float mainRowHeight =
    blePanelY -
    gap -
    mainY;

  final float leftWidth =
    availableWidth * 0.59;

  final float rightWidth =
    availableWidth -
    leftWidth -
    gap;

  final float spectrumHeight =
    mainRowHeight * 0.69;

  final float heatmapHeight =
    mainRowHeight -
    spectrumHeight -
    gap;

  drawHeader(
    margin,
    headerY,
    availableWidth,
    headerHeight
  );

  drawRFDetectionPanel(
    margin,
    mainY,
    leftWidth,
    spectrumHeight
  );

  drawRFHistoryPanel(
    margin,
    mainY +
    spectrumHeight +
    gap,
    leftWidth,
    heatmapHeight
  );

  drawRSSIPanel(
    margin +
    leftWidth +
    gap,
    mainY,
    rightWidth,
    mainRowHeight
  );

  drawBLEPanel(
    margin,
    blePanelY,
    availableWidth,
    blePanelHeight
  );

  drawFooter(
    margin,
    footerY,
    availableWidth,
    footerHeight
  );

  drawPortMenuOverlay();
}


// =====================================================================
// ENCABEZADO
// =====================================================================

void drawHeader(
  float x,
  float y,
  float w,
  float h
) {
  drawPanel(
    x,
    y,
    w,
    h
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(18);

  text(
    "Scanner BLE y detector relativo de energía RF de 2,4 GHz",
    x + 14,
    y + 9
  );

  fill(secondaryTextColor);
  textSize(10);

  text(
    shortenText(
      statusMessage,
      78
    ),
    x + 14,
    y + 36
  );

  fill(
    serialConnected
    ? goodColor
    : dangerColor
  );

  noStroke();

  ellipse(
    x + 19,
    y + 60,
    8,
    8
  );

  fill(secondaryTextColor);
  textAlign(LEFT, CENTER);
  textSize(10);

  String connectionText =
    serialConnected
    ? "Conectado: " +
      connectedPortName
    : "Desconectado";

  if (recordingCSV) {
    connectionText +=
      " | Registrando CSV";
  }

  text(
    connectionText,
    x + 29,
    y + 60
  );

  layoutHeaderControls(
    x,
    y,
    w
  );

  drawPortSelector();

  drawButton(
    refreshX,
    refreshY,
    refreshW,
    refreshH,
    "ACTUALIZAR",
    false,
    vspiColor
  );

  drawButton(
    connectX,
    connectY,
    connectW,
    connectH,
    serialConnected
      ? "DESCONECTAR"
      : "CONECTAR",
    serialConnected,
    goodColor
  );

  String saveLabel;

  if (waitingForSavePath) {
    saveLabel = "SELECCIONE";
  } else if (recordingCSV) {
    saveLabel = "GUARDAR CSV";
  } else {
    saveLabel = "REGISTRAR CSV";
  }

  drawButton(
    saveX,
    saveY,
    saveW,
    saveH,
    saveLabel,
    recordingCSV,
    recordingCSV
      ? dangerColor
      : warningColor
  );
}


void layoutHeaderControls(
  float x,
  float y,
  float w
) {
  selectorW = 205;
  selectorH = 34;

  refreshW = 82;
  refreshH = selectorH;

  connectW = 100;
  connectH = selectorH;

  saveW = 118;
  saveH = selectorH;

  final float controlGap = 7;

  saveX =
    x +
    w -
    saveW -
    13;

  connectX =
    saveX -
    connectW -
    controlGap;

  refreshX =
    connectX -
    refreshW -
    controlGap;

  selectorX =
    refreshX -
    selectorW -
    controlGap;

  selectorY = y + 19;
  refreshY = selectorY;
  connectY = selectorY;
  saveY = selectorY;
}


void drawPortSelector() {
  boolean hover =
    pointInside(
      mouseX,
      mouseY,
      selectorX,
      selectorY,
      selectorW,
      selectorH
    );

  fill(
    hover || portMenuOpen
    ? #2A3746
    : panelSecondaryColor
  );

  stroke(
    portMenuOpen
    ? vspiColor
    : borderColor
  );

  strokeWeight(1);

  rect(
    selectorX,
    selectorY,
    selectorW,
    selectorH,
    5
  );

  fill(secondaryTextColor);
  noStroke();
  textAlign(LEFT, TOP);
  textSize(8);

  text(
    "PUERTO SERIAL",
    selectorX + 9,
    selectorY + 4
  );

  String label =
    "No hay puertos";

  if (
    selectedPortIndex >= 0 &&
    selectedPortIndex < serialPorts.length
  ) {
    label =
      serialPorts[selectedPortIndex];
  }

  fill(primaryTextColor);
  textSize(10);

  text(
    shortenText(
      label,
      28
    ),
    selectorX + 9,
    selectorY + 18
  );

  fill(secondaryTextColor);
  textAlign(RIGHT, CENTER);
  textSize(13);

  text(
    portMenuOpen
      ? "▲"
      : "▼",
    selectorX +
    selectorW -
    10,
    selectorY +
    selectorH / 2
  );
}


void drawButton(
  float x,
  float y,
  float w,
  float h,
  String label,
  boolean active,
  color accentColor
) {
  boolean hover =
    pointInside(
      mouseX,
      mouseY,
      x,
      y,
      w,
      h
    );

  if (active) {
    fill(
      lerpColor(
        panelSecondaryColor,
        accentColor,
        0.24
      )
    );
  } else if (hover) {
    fill(#2C3948);
  } else {
    fill(panelSecondaryColor);
  }

  stroke(
    active || hover
    ? accentColor
    : borderColor
  );

  strokeWeight(1);

  rect(
    x,
    y,
    w,
    h,
    5
  );

  fill(
    active
    ? accentColor
    : primaryTextColor
  );

  noStroke();
  textAlign(CENTER, CENTER);
  textSize(9);

  text(
    label,
    x + w / 2,
    y + h / 2
  );
}


void drawPortMenuOverlay() {
  if (!portMenuOpen) {
    return;
  }

  final float menuY =
    selectorY +
    selectorH +
    4;

  final int visibleRows =
    min(
      serialPorts.length,
      8
    );

  final float menuHeight =
    max(
      PORT_ROW_HEIGHT,
      visibleRows *
      PORT_ROW_HEIGHT
    );

  fill(panelColor);
  stroke(vspiColor);
  strokeWeight(1);

  rect(
    selectorX,
    menuY,
    selectorW,
    menuHeight,
    5
  );

  if (serialPorts.length == 0) {
    fill(secondaryTextColor);
    noStroke();
    textAlign(LEFT, CENTER);
    textSize(10);

    text(
      "Presione ACTUALIZAR",
      selectorX + 9,
      menuY +
      PORT_ROW_HEIGHT / 2
    );

    return;
  }

  for (
    int row = 0;
    row < visibleRows;
    row++
  ) {
    final float rowY =
      menuY +
      row *
      PORT_ROW_HEIGHT;

    final boolean hover =
      pointInside(
        mouseX,
        mouseY,
        selectorX,
        rowY,
        selectorW,
        PORT_ROW_HEIGHT
      );

    final boolean selected =
      row ==
      selectedPortIndex;

    if (selected) {
      fill(#244B4A);
    } else if (hover) {
      fill(#2A3746);
    } else {
      fill(
        row % 2 == 0
        ? panelSecondaryColor
        : panelColor
      );
    }

    noStroke();

    rect(
      selectorX + 1,
      rowY,
      selectorW - 2,
      PORT_ROW_HEIGHT
    );

    fill(
      selected
      ? vspiColor
      : primaryTextColor
    );

    textAlign(LEFT, CENTER);
    textSize(10);

    text(
      shortenText(
        serialPorts[row],
        31
      ),
      selectorX + 9,
      rowY +
      PORT_ROW_HEIGHT / 2
    );
  }
}


// =====================================================================
// INTERACCIÓN DEL MOUSE
// =====================================================================

void mousePressed() {
  if (mouseButton != LEFT) {
    return;
  }

  if (handleRSSIControlClick()) {
    return;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      selectorX,
      selectorY,
      selectorW,
      selectorH
    )
  ) {
    portMenuOpen =
      !portMenuOpen;

    return;
  }

  if (portMenuOpen) {
    final float menuY =
      selectorY +
      selectorH +
      4;

    final int visibleRows =
      min(
        serialPorts.length,
        8
      );

    if (
      pointInside(
        mouseX,
        mouseY,
        selectorX,
        menuY,
        selectorW,
        visibleRows *
        PORT_ROW_HEIGHT
      )
    ) {
      final int row =
        floor(
          (
            mouseY -
            menuY
          ) /
          PORT_ROW_HEIGHT
        );

      if (
        row >= 0 &&
        row < serialPorts.length
      ) {
        selectedPortIndex = row;

        statusMessage =
          "Puerto seleccionado: " +
          serialPorts[row];
      }

      portMenuOpen = false;

      return;
    }

    portMenuOpen = false;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      refreshX,
      refreshY,
      refreshW,
      refreshH
    )
  ) {
    refreshSerialPorts();
    return;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      connectX,
      connectY,
      connectW,
      connectH
    )
  ) {
    if (serialConnected) {
      disconnectSerial();
    } else {
      connectSelectedPort();
    }

    return;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      saveX,
      saveY,
      saveW,
      saveH
    )
  ) {
    handleSaveButton();
  }
}


// =====================================================================
// CONTROLES RSSI
// =====================================================================

boolean handleRSSIControlClick() {
  if (
    pointInside(
      mouseX,
      mouseY,
      rssiTimeMinusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiTimeOptionIndex =
      max(
        0,
        rssiTimeOptionIndex - 1
      );

    rssiTimeWindowMs =
      RSSI_TIME_OPTIONS_MS[
        rssiTimeOptionIndex
      ];

    statusMessage =
      "Ventana RSSI: " +
      rssiTimeWindowMs / 1000 +
      " segundos";

    return true;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      rssiTimePlusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiTimeOptionIndex =
      min(
        RSSI_TIME_OPTIONS_MS.length - 1,
        rssiTimeOptionIndex + 1
      );

    rssiTimeWindowMs =
      RSSI_TIME_OPTIONS_MS[
        rssiTimeOptionIndex
      ];

    statusMessage =
      "Ventana RSSI: " +
      rssiTimeWindowMs / 1000 +
      " segundos";

    return true;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      rssiMinMinusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiMinDbm =
      max(
        RSSI_MIN_ALLOWED_DBM,
        rssiMinDbm -
        RSSI_DBM_STEP
      );

    statusMessage =
      "RSSI mínimo: " +
      nf(
        rssiMinDbm,
        1,
        0
      ) +
      " dBm";

    return true;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      rssiMinPlusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiMinDbm =
      min(
        rssiMaxDbm -
        RSSI_MIN_VERTICAL_SPAN_DB,
        rssiMinDbm +
        RSSI_DBM_STEP
      );

    statusMessage =
      "RSSI mínimo: " +
      nf(
        rssiMinDbm,
        1,
        0
      ) +
      " dBm";

    return true;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      rssiMaxMinusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiMaxDbm =
      max(
        rssiMinDbm +
        RSSI_MIN_VERTICAL_SPAN_DB,
        rssiMaxDbm -
        RSSI_DBM_STEP
      );

    statusMessage =
      "RSSI máximo: " +
      nf(
        rssiMaxDbm,
        1,
        0
      ) +
      " dBm";

    return true;
  }

  if (
    pointInside(
      mouseX,
      mouseY,
      rssiMaxPlusX,
      rssiControlY,
      RSSI_CONTROL_BUTTON_W,
      RSSI_CONTROL_BUTTON_H
    )
  ) {
    rssiMaxDbm =
      min(
        RSSI_MAX_ALLOWED_DBM,
        rssiMaxDbm +
        RSSI_DBM_STEP
      );

    statusMessage =
      "RSSI máximo: " +
      nf(
        rssiMaxDbm,
        1,
        0
      ) +
      " dBm";

    return true;
  }

  return false;
}


// =====================================================================
// CSV
// =====================================================================

void handleSaveButton() {
  if (waitingForSavePath) {
    statusMessage =
      "Ya existe un selector de archivo abierto";

    return;
  }

  if (recordingCSV) {
    finishCSVRecording();
    return;
  }

  waitingForSavePath = true;

  statusMessage =
    "Seleccione dónde guardar el archivo CSV";

  selectOutput(
    "Guardar registro RF y BLE",
    "csvFileSelected"
  );
}


void csvFileSelected(
  File selection
) {
  waitingForSavePath = false;

  if (selection == null) {
    statusMessage =
      "Guardado cancelado";

    return;
  }

  String path =
    selection.getAbsolutePath();

  if (
    !path
      .toLowerCase()
      .endsWith(".csv")
  ) {
    path += ".csv";
  }

  try {
    csvWriter =
      createWriter(path);

    /*
      Se mantienen estos nombres para conservar compatibilidad
      con los lectores MATLAB y Python anteriores.

      Interpretación correcta:

      ocupacion_filtrada_pct =
        porcentaje filtrado de ventanas con detección.

      ocupacion_cruda_pct =
        porcentaje crudo de ventanas con detección.
    */
    csvWriter.println(
      "tiempo_ms,tipo,frame,radio," +
      "frecuencia_MHz,ocupacion_filtrada_pct," +
      "ocupacion_cruda_pct,direccion,rssi_dBm," +
      "identificacion,canales_BLE_posibles," +
      "frecuencias_BLE_posibles_MHz"
    );

    csvWriter.flush();

    csvFullPath = path;

    File outputFile =
      new File(path);

    csvFilename =
      outputFile.getName();

    recordingCSV = true;

    statusMessage =
      "Registro iniciado: " +
      csvFilename;
  }
  catch (Exception error) {
    csvWriter = null;
    recordingCSV = false;

    statusMessage =
      "No se pudo crear el CSV: " +
      error.getMessage();
  }
}


void finishCSVRecording() {
  if (csvWriter != null) {
    csvWriter.flush();
    csvWriter.close();

    csvWriter = null;
  }

  recordingCSV = false;

  statusMessage =
    "CSV guardado: " +
    csvFullPath;
}


// =====================================================================
// PUERTOS SERIALES
// =====================================================================

void refreshSerialPorts() {
  String previousSelection = "";

  if (
    selectedPortIndex >= 0 &&
    selectedPortIndex < serialPorts.length
  ) {
    previousSelection =
      serialPorts[selectedPortIndex];
  }

  String[] detectedPorts =
    Serial.list();

  serialPorts =
    detectedPorts == null
    ? new String[0]
    : detectedPorts;

  selectedPortIndex = -1;

  for (
    int index = 0;
    index < serialPorts.length;
    index++
  ) {
    if (
      serialPorts[index]
        .equals(previousSelection)
    ) {
      selectedPortIndex = index;
      break;
    }
  }

  if (
    selectedPortIndex < 0 &&
    serialPorts.length > 0
  ) {
    selectedPortIndex = 0;
  }

  println();
  println("Puertos seriales detectados:");

  printArray(serialPorts);

  if (serialPorts.length == 0) {
    statusMessage =
      "No se detectaron puertos; revise el USB y cierre el monitor serial";
  } else {
    statusMessage =
      serialPorts.length +
      " puerto(s) detectado(s); seleccione el ESP32";
  }
}


void connectSelectedPort() {
  if (serialPorts.length == 0) {
    refreshSerialPorts();
  }

  if (
    selectedPortIndex < 0 ||
    selectedPortIndex >= serialPorts.length
  ) {
    statusMessage =
      "Seleccione un puerto válido";

    return;
  }

  disconnectSerial();

  try {
    connectedPortName =
      serialPorts[selectedPortIndex];

    serialPort =
      new Serial(
        this,
        connectedPortName,
        SERIAL_BAUD
      );

    serialPort.clear();
    serialPort.bufferUntil('\n');

    serialConnected = true;

    statusMessage =
      "Conectado a " +
      connectedPortName +
      " a " +
      SERIAL_BAUD +
      " baudios";
  }
  catch (Exception error) {
    serialPort = null;
    serialConnected = false;
    connectedPortName = "";

    statusMessage =
      "No se pudo abrir el puerto: " +
      error.getMessage();
  }
}


void disconnectSerial() {
  if (serialPort != null) {
    try {
      serialPort.stop();
    }
    catch (Exception error) {
      println(
        error.getMessage()
      );
    }
  }

  serialPort = null;
  serialConnected = false;
  connectedPortName = "";

  statusMessage =
    "Puerto serial desconectado";
}


// =====================================================================
// ESCALA FIJA DEL PANEL RF
// =====================================================================

void updateRFDisplayScale() {
  /*
    La escala permanece fija para permitir comparaciones
    visuales entre diferentes mediciones.
  */
  rfDisplayMaximum =
    RF_DISPLAY_MAXIMUM;
}


// =====================================================================
// PANEL DE DETECCIÓN RELATIVA RF
// =====================================================================

void drawRFDetectionPanel(
  float panelX,
  float panelY,
  float panelW,
  float panelH
) {
  drawPanel(
    panelX,
    panelY,
    panelW,
    panelH
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(14);

  text(
    "Detección relativa de energía RF",
    panelX + 15,
    panelY + 10
  );

  drawRadioLegend(
    panelX +
    panelW -
    277,
    panelY + 12
  );

  fill(secondaryTextColor);
  textAlign(LEFT, TOP);
  textSize(10);

  text(
    "24 ventanas por canal: resolución cruda ≈ 4,17 %. " +
    "La barra es filtrada y no representa potencia en dBm.",
    panelX + 15,
    panelY + 31,
    panelW - 245,
    24
  );

  fill(secondaryTextColor);
  textAlign(RIGHT, TOP);
  textSize(8);

  text(
    "Escala fija: 0–" +
    formatRFScaleMaximum() +
    " %",
    panelX +
    panelW -
    15,
    panelY + 31
  );

  final float plotX =
    panelX + 58;

  final float plotY =
    panelY + 58;

  final float plotW =
    panelW - 73;

  final float plotH =
    panelH - 88;

  drawRFDetectionGrid(
    plotX,
    plotY,
    plotW,
    plotH
  );

  drawRadioRegions(
    plotX,
    plotY,
    plotW,
    plotH
  );

  drawBLEAdvertisingMarkers(
    plotX,
    plotY,
    plotW,
    plotH
  );

  drawRFDetectionBars(
    plotX,
    plotY,
    plotW,
    plotH
  );

  drawFrequencyLabels(
    plotX,
    plotY,
    plotW,
    plotH
  );
}


String formatRFScaleMaximum() {
  if (rfDisplayMaximum < 10) {
    return nf(
      rfDisplayMaximum,
      1,
      1
    );
  }

  return nf(
    rfDisplayMaximum,
    1,
    0
  );
}


void drawRadioLegend(
  float x,
  float y
) {
  noStroke();

  fill(vspiColor);

  rect(
    x,
    y + 2,
    11,
    7,
    2
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(8);

  text(
    "VSPI 2402–2441",
    x + 15,
    y
  );

  fill(hspiColor);

  rect(
    x + 135,
    y + 2,
    11,
    7,
    2
  );

  fill(primaryTextColor);

  text(
    "HSPI 2442–2480",
    x + 150,
    y
  );
}


void drawRFDetectionGrid(
  float x,
  float y,
  float w,
  float h
) {
  for (
    int step = 0;
    step <= 4;
    step++
  ) {
    float value =
      rfDisplayMaximum *
      step /
      4.0;

    float lineY =
      map(
        value,
        0,
        rfDisplayMaximum,
        y + h,
        y
      );

    stroke(gridColor);
    strokeWeight(1);

    line(
      x,
      lineY,
      x + w,
      lineY
    );

    fill(secondaryTextColor);
    noStroke();
    textAlign(RIGHT, CENTER);
    textSize(8);

    text(
      nf(
        value,
        1,
        value < 10
        ? 1
        : 0
      ) +
      " %",
      x - 7,
      lineY
    );
  }

  /*
    Nombre correcto del eje vertical.
  */
  pushMatrix();

  translate(
    x - 42,
    y + h / 2
  );

  rotate(
    -HALF_PI
  );

  fill(secondaryTextColor);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(8);

  text(
    "Ventanas con detección [%]",
    0,
    0
  );

  popMatrix();

  noFill();
  stroke(borderColor);

  rect(
    x,
    y,
    w,
    h
  );
}


void drawRadioRegions(
  float x,
  float y,
  float w,
  float h
) {
  final float splitX =
    frequencyToX(
      2441.5,
      x,
      w
    );

  noStroke();

  fill(
    red(vspiColor),
    green(vspiColor),
    blue(vspiColor),
    14
  );

  rect(
    x,
    y,
    splitX - x,
    h
  );

  fill(
    red(hspiColor),
    green(hspiColor),
    blue(hspiColor),
    14
  );

  rect(
    splitX,
    y,
    x + w - splitX,
    h
  );

  stroke(borderColor);
  strokeWeight(1.3);

  line(
    splitX,
    y,
    splitX,
    y + h
  );
}


void drawBLEAdvertisingMarkers(
  float x,
  float y,
  float w,
  float h
) {
  int[] frequencies = {
    2402,
    2426,
    2480
  };

  String[] labels = {
    "BLE 37",
    "BLE 38",
    "BLE 39"
  };

  for (
    int index = 0;
    index < frequencies.length;
    index++
  ) {
    float markerX =
      frequencyToX(
        frequencies[index],
        x,
        w
      );

    stroke(
      warningColor,
      150
    );

    strokeWeight(1);

    line(
      markerX,
      y,
      markerX,
      y + h
    );

    fill(warningColor);
    noStroke();
    textSize(7);

    if (index == 0) {
      textAlign(LEFT, BOTTOM);

      text(
        labels[index],
        markerX + 3,
        y + h - 3
      );
    } else if (
      index ==
      frequencies.length - 1
    ) {
      textAlign(RIGHT, BOTTOM);

      text(
        labels[index],
        markerX - 3,
        y + h - 3
      );
    } else {
      textAlign(CENTER, BOTTOM);

      text(
        labels[index],
        markerX,
        y + h - 3
      );
    }
  }
}


void drawRFDetectionBars(
  float x,
  float y,
  float w,
  float h
) {
  final float channelWidth =
    w /
    FREQUENCY_COUNT;

  for (
    int index = 0;
    index < FREQUENCY_COUNT;
    index++
  ) {
    float value =
      constrain(
        rfValues[index],
        0,
        rfDisplayMaximum
      );

    float peak =
      constrain(
        rfPeaks[index],
        0,
        rfDisplayMaximum
      );

    float barHeight =
      map(
        value,
        0,
        rfDisplayMaximum,
        0,
        h
      );

    float barX =
      x +
      index *
      channelWidth;

    float barY =
      y +
      h -
      barHeight;

    int frequency =
      FREQUENCY_MIN +
      index;

    color baseColor =
      frequency <= 2441
      ? vspiColor
      : hspiColor;

    fill(
      detectionColor(
        baseColor,
        value /
        max(
          rfDisplayMaximum,
          0.001
        ) *
        100.0
      )
    );

    noStroke();

    rect(
      barX + 0.3,
      barY,
      max(
        1,
        channelWidth - 0.6
      ),
      barHeight
    );

    float peakY =
      map(
        peak,
        0,
        rfDisplayMaximum,
        y + h,
        y
      );

    stroke(
      peakColor,
      135
    );

    strokeWeight(0.8);

    line(
      barX + 0.3,
      peakY,
      barX +
      channelWidth -
      0.3,
      peakY
    );
  }
}


color detectionColor(
  color baseColor,
  float normalizedPercent
) {
  if (normalizedPercent < 55) {
    return lerpColor(
      panelSecondaryColor,
      baseColor,
      map(
        normalizedPercent,
        0,
        55,
        0.20,
        1.0
      )
    );
  }

  return lerpColor(
    baseColor,
    dangerColor,
    map(
      normalizedPercent,
      55,
      100,
      0,
      1
    )
  );
}


void drawFrequencyLabels(
  float x,
  float y,
  float w,
  float h
) {
  int[] ticks = {
    2402,
    2410,
    2420,
    2430,
    2440,
    2450,
    2460,
    2470,
    2480
  };

  fill(secondaryTextColor);
  textSize(8);
  textAlign(CENTER, TOP);

  for (
    int frequency :
    ticks
  ) {
    text(
      str(frequency),
      frequencyToX(
        frequency,
        x,
        w
      ),
      y + h + 5
    );
  }

  textAlign(RIGHT, TOP);

  text(
    "Frecuencia [MHz]",
    x + w,
    y + h + 17
  );
}


float frequencyToX(
  float frequency,
  float x,
  float w
) {
  return map(
    frequency,
    FREQUENCY_MIN,
    FREQUENCY_MAX,
    x,
    x + w
  );
}


// =====================================================================
// MAPA TEMPORAL DE DETECCIÓN RF
// =====================================================================

void drawRFHistoryPanel(
  float panelX,
  float panelY,
  float panelW,
  float panelH
) {
  drawPanel(
    panelX,
    panelY,
    panelW,
    panelH
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(12);

  text(
    "Historial de detección relativa RF",
    panelX + 14,
    panelY + 8
  );

  fill(secondaryTextColor);
  textSize(8);

  text(
    "Cada fila corresponde a un barrido; el más reciente aparece abajo",
    panelX + 220,
    panelY + 10
  );

  final float mapX =
    panelX + 48;

  final float mapY =
    panelY + 30;

  final float mapW =
    panelW - 62;

  final float mapH =
    panelH - 42;

  final float cellWidth =
    mapW /
    FREQUENCY_COUNT;

  final float cellHeight =
    mapH /
    HISTORY_ROWS;

  noStroke();

  for (
    int displayRow = 0;
    displayRow < HISTORY_ROWS;
    displayRow++
  ) {
    int historyRow =
      (
        historyWriteIndex +
        displayRow
      ) % HISTORY_ROWS;

    for (
      int channel = 0;
      channel < FREQUENCY_COUNT;
      channel++
    ) {
      fill(
        rfHistoryColor(
          rfHistory[
            historyRow
          ][
            channel
          ]
        )
      );

      rect(
        mapX +
        channel *
        cellWidth,
        mapY +
        displayRow *
        cellHeight,
        cellWidth + 0.25,
        cellHeight + 0.25
      );
    }
  }

  noFill();
  stroke(borderColor);

  rect(
    mapX,
    mapY,
    mapW,
    mapH
  );

  fill(secondaryTextColor);
  noStroke();
  textAlign(RIGHT, CENTER);
  textSize(7);

  text(
    "anterior",
    mapX - 5,
    mapY + 3
  );

  text(
    "reciente",
    mapX - 5,
    mapY + mapH - 3
  );
}


color rfHistoryColor(
  float value
) {
  float normalized =
    constrain(
      value /
      max(
        rfDisplayMaximum,
        0.001
      ) *
      100.0,
      0,
      100
    );

  if (normalized < 35) {
    return lerpColor(
      backgroundColor,
      vspiColor,
      normalized / 35.0
    );
  }

  if (normalized < 70) {
    return lerpColor(
      vspiColor,
      warningColor,
      (
        normalized -
        35
      ) / 35.0
    );
  }

  return lerpColor(
    warningColor,
    dangerColor,
    (
      normalized -
      70
    ) / 30.0
  );
}


// =====================================================================
// PANEL RSSI BLE
// =====================================================================

void drawRSSIPanel(
  float panelX,
  float panelY,
  float panelW,
  float panelH
) {
  drawPanel(
    panelX,
    panelY,
    panelW,
    panelH
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(14);

  text(
    "RSSI Bluetooth LE",
    panelX + 14,
    panelY + 9
  );

  fill(secondaryTextColor);
  textAlign(RIGHT, TOP);
  textSize(8);

  text(
    "Potencia recibida informada por el ESP32 BLE",
    panelX + panelW - 14,
    panelY + 11
  );

  drawRSSIControls(
    panelX + 14,
    panelY + 42,
    panelW - 28
  );

  final float plotX =
    panelX + 48;

  final float plotY =
    panelY + 82;

  final float legendWidth =
    constrain(
      panelW * 0.30,
      125,
      155
    );

  final float plotW =
    panelW -
    legendWidth -
    70;

  final float plotH =
    panelH - 112;

  drawRSSIGrid(
    plotX,
    plotY,
    plotW,
    plotH
  );

  ArrayList<BLEDeviceInfo> visibleDevices =
    getRSSIGraphDevices();

  drawRSSITraces(
    visibleDevices,
    plotX,
    plotY,
    plotW,
    plotH
  );

  drawRSSILegend(
    visibleDevices,
    plotX + plotW + 12,
    plotY,
    legendWidth - 8,
    plotH
  );
}


void drawRSSIControls(
  float x,
  float y,
  float availableWidth
) {
  final float groupGap = 5;

  final float groupWidth =
    min(
      112,
      (
        availableWidth -
        2 * groupGap
      ) / 3.0
    );

  drawRSSIValueControl(
    x,
    y,
    groupWidth,
    "TIEMPO",
    str(
      rssiTimeWindowMs /
      1000
    ) +
    " s",
    0
  );

  drawRSSIValueControl(
    x +
    groupWidth +
    groupGap,
    y,
    groupWidth,
    "dBm MÍN.",
    nf(
      rssiMinDbm,
      1,
      0
    ),
    1
  );

  drawRSSIValueControl(
    x +
    2 *
    (
      groupWidth +
      groupGap
    ),
    y,
    groupWidth,
    "dBm MÁX.",
    nf(
      rssiMaxDbm,
      1,
      0
    ),
    2
  );
}


void drawRSSIValueControl(
  float x,
  float y,
  float w,
  String label,
  String value,
  int controlType
) {
  final float buttonW =
    RSSI_CONTROL_BUTTON_W;

  final float buttonH =
    RSSI_CONTROL_BUTTON_H;

  final float plusX =
    x +
    w -
    buttonW;

  final float valueX =
    x +
    buttonW;

  final float valueW =
    w -
    2 * buttonW;

  if (controlType == 0) {
    rssiTimeMinusX = x;
    rssiTimePlusX = plusX;
  } else if (controlType == 1) {
    rssiMinMinusX = x;
    rssiMinPlusX = plusX;
  } else {
    rssiMaxMinusX = x;
    rssiMaxPlusX = plusX;
  }

  rssiControlY = y;

  fill(secondaryTextColor);
  noStroke();
  textAlign(CENTER, BOTTOM);
  textSize(7);

  text(
    label,
    x + w / 2,
    y - 2
  );

  drawRSSIMiniButton(
    x,
    y,
    buttonW,
    buttonH,
    "−"
  );

  fill(panelSecondaryColor);
  stroke(borderColor);
  strokeWeight(1);

  rect(
    valueX,
    y,
    valueW,
    buttonH
  );

  fill(primaryTextColor);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(9);

  text(
    value,
    valueX +
    valueW / 2,
    y +
    buttonH / 2
  );

  drawRSSIMiniButton(
    plusX,
    y,
    buttonW,
    buttonH,
    "+"
  );
}


void drawRSSIMiniButton(
  float x,
  float y,
  float w,
  float h,
  String label
) {
  boolean hover =
    pointInside(
      mouseX,
      mouseY,
      x,
      y,
      w,
      h
    );

  fill(
    hover
    ? #314153
    : panelSecondaryColor
  );

  stroke(
    hover
    ? vspiColor
    : borderColor
  );

  strokeWeight(1);

  rect(
    x,
    y,
    w,
    h,
    4
  );

  fill(primaryTextColor);
  noStroke();
  textAlign(CENTER, CENTER);
  textSize(12);

  text(
    label,
    x + w / 2,
    y + h / 2 - 1
  );
}


void drawRSSIGrid(
  float x,
  float y,
  float w,
  float h
) {
  final int verticalDivisions = 5;

  for (
    int step = 0;
    step <= verticalDivisions;
    step++
  ) {
    float fraction =
      step /
      float(verticalDivisions);

    float rssi =
      lerp(
        rssiMinDbm,
        rssiMaxDbm,
        fraction
      );

    float lineY =
      lerp(
        y + h,
        y,
        fraction
      );

    stroke(gridColor);
    strokeWeight(1);

    line(
      x,
      lineY,
      x + w,
      lineY
    );

    fill(secondaryTextColor);
    noStroke();
    textAlign(RIGHT, CENTER);
    textSize(8);

    text(
      nf(
        rssi,
        1,
        0
      ),
      x - 5,
      lineY
    );
  }

  final int horizontalDivisions = 4;

  final float totalSeconds =
    rssiTimeWindowMs /
    1000.0;

  for (
    int step = 0;
    step <= horizontalDivisions;
    step++
  ) {
    float fraction =
      step /
      float(horizontalDivisions);

    float lineX =
      lerp(
        x,
        x + w,
        fraction
      );

    int secondsAgo =
      round(
        totalSeconds *
        (
          1.0 -
          fraction
        )
      );

    stroke(
      gridColor,
      150
    );

    line(
      lineX,
      y,
      lineX,
      y + h
    );

    fill(secondaryTextColor);
    noStroke();
    textAlign(CENTER, TOP);
    textSize(7);

    text(
      secondsAgo == 0
      ? "ahora"
      : "−" +
        secondsAgo +
        " s",
      lineX,
      y + h + 4
    );
  }

  fill(secondaryTextColor);
  noStroke();
  textAlign(LEFT, BOTTOM);
  textSize(7);

  text(
    "RSSI [dBm]",
    x - 38,
    y - 2
  );

  noFill();
  stroke(borderColor);

  rect(
    x,
    y,
    w,
    h
  );
}


ArrayList<BLEDeviceInfo> getRSSIGraphDevices() {
  ArrayList<BLEDeviceInfo> devices =
    new ArrayList<BLEDeviceInfo>();

  for (
    BLEDeviceInfo device :
    bleDevices.values()
  ) {
    if (
      device.isVisibleInRSSIGraph()
    ) {
      devices.add(device);
    }
  }

  Collections.sort(
    devices,
    new Comparator<BLEDeviceInfo>() {
      public int compare(
        BLEDeviceInfo first,
        BLEDeviceInfo second
      ) {
        return
          first.deviceId -
          second.deviceId;
      }
    }
  );

  while (
    devices.size() > 10
  ) {
    devices.remove(
      devices.size() - 1
    );
  }

  return devices;
}


void drawRSSITraces(
  ArrayList<BLEDeviceInfo> devices,
  float x,
  float y,
  float w,
  float h
) {
  final int now = millis();

  for (
    BLEDeviceInfo device :
    devices
  ) {
    color traceColor =
      bleTraceColor(
        device.deviceId
      );

    stroke(traceColor);
    strokeWeight(1.7);
    noFill();

    boolean hasPrevious = false;

    float previousX = 0;
    float previousY = 0;

    int previousTime = 0;

    float lastX = 0;
    float lastY = 0;

    boolean hasVisibleSample = false;

    for (
      int position = 0;
      position <
      device.rssiHistoryCount;
      position++
    ) {
      int historyIndex =
        device.historyIndexFromOldest(
          position
        );

      int sampleTime =
        device.rssiHistoryTime[
          historyIndex
        ];

      int sampleAge =
        now -
        sampleTime;

      if (
        sampleAge < 0 ||
        sampleAge >
        rssiTimeWindowMs
      ) {
        continue;
      }

      float sampleRSSI =
        constrain(
          device.rssiHistoryValue[
            historyIndex
          ],
          rssiMinDbm,
          rssiMaxDbm
        );

      float sampleX =
        map(
          sampleAge,
          rssiTimeWindowMs,
          0,
          x,
          x + w
        );

      float sampleY =
        map(
          sampleRSSI,
          rssiMinDbm,
          rssiMaxDbm,
          y + h,
          y
        );

      if (
        hasPrevious &&
        sampleTime -
        previousTime <=
        RSSI_LINE_GAP_MS
      ) {
        line(
          previousX,
          previousY,
          sampleX,
          sampleY
        );
      }

      noStroke();
      fill(traceColor);

      ellipse(
        sampleX,
        sampleY,
        3.2,
        3.2
      );

      stroke(traceColor);
      noFill();

      previousX = sampleX;
      previousY = sampleY;
      previousTime = sampleTime;

      hasPrevious = true;

      lastX = sampleX;
      lastY = sampleY;

      hasVisibleSample = true;
    }

    if (hasVisibleSample) {
      fill(traceColor);
      stroke(backgroundColor);
      strokeWeight(1);

      ellipse(
        lastX,
        lastY,
        7,
        7
      );

      fill(traceColor);
      noStroke();

      textAlign(LEFT, BOTTOM);
      textSize(8);

      text(
        "[" +
        device.deviceId +
        "]",
        min(
          lastX + 4,
          x + w - 20
        ),
        lastY - 2
      );
    }
  }
}


void drawRSSILegend(
  ArrayList<BLEDeviceInfo> devices,
  float x,
  float y,
  float w,
  float h
) {
  fill(secondaryTextColor);
  textAlign(LEFT, TOP);
  textSize(8);

  text(
    "DISPOSITIVOS",
    x,
    y
  );

  final float rowHeight = 17;

  int rowsToDraw =
    min(
      devices.size(),
      floor(
        (
          h - 17
        ) /
        rowHeight
      )
    );

  for (
    int row = 0;
    row < rowsToDraw;
    row++
  ) {
    BLEDeviceInfo device =
      devices.get(row);

    float rowY =
      y +
      16 +
      row *
      rowHeight;

    color traceColor =
      bleTraceColor(
        device.deviceId
      );

    fill(traceColor);
    noStroke();

    rect(
      x,
      rowY + 4,
      10,
      3
    );

    fill(primaryTextColor);
    textAlign(LEFT, TOP);
    textSize(8);

    text(
      "[" +
      device.deviceId +
      "] " +
      shortenText(
        device.identification,
        14
      ),
      x + 14,
      rowY
    );

    fill(
      rssiColor(
        device.filteredRSSI
      )
    );

    textAlign(RIGHT, TOP);

    text(
      nf(
        device.filteredRSSI,
        1,
        0
      ),
      x + w,
      rowY
    );
  }

  if (devices.size() == 0) {
    fill(secondaryTextColor);
    noStroke();
    textAlign(LEFT, TOP);
    textSize(8);

    text(
      "Sin datos RSSI",
      x,
      y + 18
    );
  }
}


color bleTraceColor(
  int deviceId
) {
  switch (
    (
      deviceId - 1
    ) % 10
  ) {
    case 0:
      return #31B7B4;

    case 1:
      return #708FFF;

    case 2:
      return #F2B134;

    case 3:
      return #E6535C;

    case 4:
      return #9B7EDE;

    case 5:
      return #56C271;

    case 6:
      return #E786C3;

    case 7:
      return #D9884A;

    case 8:
      return #55A7D9;

    default:
      return #B8C45A;
  }
}


// =====================================================================
// TABLA BLE COMPACTA
// =====================================================================

void drawBLEPanel(
  float panelX,
  float panelY,
  float panelW,
  float panelH
) {
  drawPanel(
    panelX,
    panelY,
    panelW,
    panelH
  );

  fill(primaryTextColor);
  textAlign(LEFT, TOP);
  textSize(12);

  text(
    "Dispositivos Bluetooth LE detectados",
    panelX + 14,
    panelY + 7
  );

  ArrayList<BLEDeviceInfo> devices =
    new ArrayList<BLEDeviceInfo>(
      bleDevices.values()
    );

  Collections.sort(
    devices,
    new Comparator<BLEDeviceInfo>() {
      public int compare(
        BLEDeviceInfo first,
        BLEDeviceInfo second
      ) {
        return Float.compare(
          second.filteredRSSI,
          first.filteredRSSI
        );
      }
    }
  );

  fill(secondaryTextColor);
  textAlign(RIGHT, TOP);
  textSize(8);

  text(
    devices.size() +
    " dispositivos | " +
    nf(
      filteredSweepRate,
      1,
      1
    ) +
    " barridos/s | Frame " +
    frameNumber,
    panelX +
    panelW -
    14,
    panelY + 9
  );

  final float tableX =
    panelX + 14;

  final float tableY =
    panelY + 29;

  final float tableW =
    panelW - 28;

  drawBLETableHeader(
    tableX,
    tableY,
    tableW
  );

  final float rowHeight = 19;

  final float firstRowY =
    tableY + 21;

  final int maximumRows =
    max(
      0,
      floor(
        (
          panelY +
          panelH -
          firstRowY -
          5
        ) /
        rowHeight
      )
    );

  final int rowsToDraw =
    min(
      maximumRows,
      devices.size()
    );

  for (
    int row = 0;
    row < rowsToDraw;
    row++
  ) {
    drawBLEDeviceRow(
      devices.get(row),
      tableX,
      firstRowY +
      row *
      rowHeight,
      tableW,
      rowHeight,
      row
    );
  }

  if (devices.size() == 0) {
    fill(secondaryTextColor);
    textAlign(CENTER, CENTER);
    textSize(10);

    text(
      "Esperando dispositivos BLE...",
      panelX +
      panelW / 2,
      firstRowY + 25
    );
  }
}


void drawBLETableHeader(
  float x,
  float y,
  float w
) {
  fill(panelSecondaryColor);
  noStroke();

  rect(
    x,
    y,
    w,
    19,
    4
  );

  fill(secondaryTextColor);
  textAlign(LEFT, CENTER);
  textSize(8);

  text(
    "N°",
    x + 8,
    y + 9.5
  );

  text(
    "Identificación",
    x + w * 0.035,
    y + 9.5
  );

  text(
    "Dirección protegida",
    x + w * 0.255,
    y + 9.5
  );

  text(
    "RSSI",
    x + w * 0.435,
    y + 9.5
  );

  text(
    "Canales",
    x + w * 0.505,
    y + 9.5
  );

  text(
    "Frecuencias posibles",
    x + w * 0.59,
    y + 9.5
  );

  text(
    "Estado",
    x + w * 0.79,
    y + 9.5
  );

  text(
    "Última",
    x + w * 0.865,
    y + 9.5
  );

  text(
    "Tramas",
    x + w * 0.95,
    y + 9.5
  );
}


void drawBLEDeviceRow(
  BLEDeviceInfo device,
  float x,
  float y,
  float w,
  float h,
  int row
) {
  fill(
    row % 2 == 0
    ? #1D2632
    : #18212B
  );

  noStroke();

  rect(
    x,
    y,
    w,
    h
  );

  fill(
    bleTraceColor(
      device.deviceId
    )
  );

  textAlign(LEFT, CENTER);
  textSize(8);

  text(
    "[" +
    device.deviceId +
    "]",
    x + 8,
    y + h / 2
  );

  fill(primaryTextColor);

  text(
    shortenText(
      device.identification,
      27
    ),
    x + w * 0.035,
    y + h / 2
  );

  fill(secondaryTextColor);

  text(
    displayBLEAddress(
      device.address
    ),
    x + w * 0.255,
    y + h / 2
  );

  fill(
    rssiColor(
      device.filteredRSSI
    )
  );

  text(
    nf(
      device.filteredRSSI,
      1,
      0
    ) +
    " dBm",
    x + w * 0.435,
    y + h / 2
  );

  fill(secondaryTextColor);

  text(
    device.possibleChannels,
    x + w * 0.505,
    y + h / 2
  );

  text(
    shortenText(
      device.possibleFrequencies,
      23
    ),
    x + w * 0.59,
    y + h / 2
  );

  fill(
    device.isActive()
    ? goodColor
    : warningColor
  );

  text(
    device.isActive()
    ? "Activo"
    : "Inactivo",
    x + w * 0.79,
    y + h / 2
  );

  fill(secondaryTextColor);

  text(
    nf(
      device.ageSeconds(),
      1,
      1
    ) +
    " s",
    x + w * 0.865,
    y + h / 2
  );

  text(
    str(device.packets),
    x + w * 0.95,
    y + h / 2
  );
}


color rssiColor(
  float rssi
) {
  if (rssi >= -60) {
    return goodColor;
  }

  if (rssi >= -80) {
    return warningColor;
  }

  return dangerColor;
}


// =====================================================================
// RECEPCIÓN SERIAL
// =====================================================================

void serialEvent(
  Serial port
) {
  String line =
    port.readStringUntil('\n');

  if (line == null) {
    return;
  }

  line = trim(line);

  if (line.length() > 0) {
    parseSerialMessage(line);
  }
}


void parseSerialMessage(
  String line
) {
  String[] fields =
    split(
      line,
      ','
    );

  if (
    fields == null ||
    fields.length == 0
  ) {
    return;
  }

  String messageType =
    trim(fields[0]);

  try {
    if (
      (
        messageType.equals("RF") ||
        messageType.equals("RF1") ||
        messageType.equals("RF2")
      ) &&
      fields.length >= 3
    ) {
      int frequency =
        int(
          trim(fields[1])
        );

      float filteredDetection =
        float(
          trim(fields[2])
        );

      float rawDetection =
        fields.length >= 4
        ? float(
            trim(fields[3])
          )
        : filteredDetection;

      int source =
        RADIO_UNKNOWN;

      if (
        messageType.equals("RF1")
      ) {
        source =
          RADIO_VSPI;
      } else if (
        messageType.equals("RF2")
      ) {
        source =
          RADIO_HSPI;
      } else {
        source =
          frequency <= 2441
          ? RADIO_VSPI
          : RADIO_HSPI;
      }

      processRFValue(
        frequency,
        filteredDetection,
        rawDetection,
        source
      );
    } else if (
      messageType.equals("BLE") &&
      fields.length >= 4
    ) {
      String address =
        trim(fields[1]);

      int rssi =
        int(
          trim(fields[2])
        );

      String identification =
        trim(fields[3]);

      String possibleChannels =
        fields.length >= 5
        ? trim(fields[4])
        : "37|38|39";

      String possibleFrequencies =
        fields.length >= 6
        ? trim(fields[5])
        : "2402|2426|2480";

      processBLEDevice(
        address,
        rssi,
        identification,
        possibleChannels,
        possibleFrequencies
      );
    } else if (
      messageType.equals("FRAME") &&
      fields.length >= 2
    ) {
      processFrame(
        Long.parseLong(
          trim(fields[1])
        )
      );
    } else if (
      messageType.equals("STATUS") &&
      fields.length >= 2
    ) {
      int separator =
        line.indexOf(',');

      statusMessage =
        line.substring(
          separator + 1
        );
    }
  }
  catch (Exception error) {
    println(
      "Mensaje descartado: " +
      line
    );

    println(
      error.getMessage()
    );
  }
}


void processRFValue(
  int frequency,
  float filteredDetection,
  float rawDetection,
  int source
) {
  int index =
    frequency -
    FREQUENCY_MIN;

  if (
    index < 0 ||
    index >= FREQUENCY_COUNT
  ) {
    return;
  }

  filteredDetection =
    constrain(
      filteredDetection,
      0,
      100
    );

  rawDetection =
    constrain(
      rawDetection,
      0,
      100
    );

  rfValues[index] =
    filteredDetection;

  rfRawValues[index] =
    rawDetection;

  rfSource[index] =
    source;

  rfPeaks[index] =
    max(
      rfPeaks[index],
      filteredDetection
    );

  if (
    recordingCSV &&
    csvWriter != null
  ) {
    csvWriter.println(
      millis() + "," +
      "RF" + "," +
      frameNumber + "," +
      radioName(source) + "," +
      frequency + "," +
      nf(
        filteredDetection,
        1,
        2
      ) + "," +
      nf(
        rawDetection,
        1,
        2
      ) + "," +
      "" + "," +
      "" + "," +
      "" + "," +
      "" + "," +
      ""
    );
  }
}


void processBLEDevice(
  String address,
  int rssi,
  String identification,
  String possibleChannels,
  String possibleFrequencies
) {
  BLEDeviceInfo device =
    bleDevices.get(address);

  if (device == null) {
    device =
      new BLEDeviceInfo(
        address,
        identification,
        rssi,
        possibleChannels,
        possibleFrequencies
      );

    bleDevices.put(
      address,
      device
    );
  } else {
    device.update(
      identification,
      rssi,
      possibleChannels,
      possibleFrequencies
    );
  }

  if (
    recordingCSV &&
    csvWriter != null
  ) {
    csvWriter.println(
      millis() + "," +
      "BLE" + "," +
      frameNumber + "," +
      "" + "," +
      "" + "," +
      "" + "," +
      "" + "," +
      csvClean(
        exportBLEAddress(
          address
        )
      ) + "," +
      rssi + "," +
      csvClean(
        device.identification
      ) + "," +
      csvClean(
        device.possibleChannels
      ) + "," +
      csvClean(
        device.possibleFrequencies
      )
    );
  }
}


void processFrame(
  long newFrameNumber
) {
  int currentMillis =
    millis();

  if (lastFrameMillis > 0) {
    float elapsedSeconds =
      (
        currentMillis -
        lastFrameMillis
      ) / 1000.0;

    if (elapsedSeconds > 0) {
      float instantaneousRate =
        1.0 /
        elapsedSeconds;

      filteredSweepRate =
        0.20 *
        instantaneousRate +
        0.80 *
        filteredSweepRate;
    }
  }

  frameNumber = newFrameNumber;
  lastFrameMillis = currentMillis;

  for (
    int index = 0;
    index < FREQUENCY_COUNT;
    index++
  ) {
    rfHistory[
      historyWriteIndex
    ][
      index
    ] = rfValues[index];
  }

  historyWriteIndex =
    (
      historyWriteIndex + 1
    ) % HISTORY_ROWS;

  if (
    recordingCSV &&
    csvWriter != null
  ) {
    csvWriter.flush();
  }
}


// =====================================================================
// IDENTIFICACIÓN BLE
// =====================================================================

int identificationRank(
  String value
) {
  if (value == null) {
    return 0;
  }

  String normalized =
    trim(value);

  if (
    normalized.length() == 0 ||
    normalized.equals(
      "BLE anónimo"
    ) ||
    normalized.equals(
      "Sin nombre"
    )
  ) {
    return 0;
  }

  if (
    normalized.startsWith(
      "Fabricante "
    ) ||
    normalized.startsWith(
      "Servicio 000"
    )
  ) {
    return 1;
  }

  if (
    normalized.startsWith(
      "Servicio "
    ) ||
    normalized.startsWith(
      "Información "
    ) ||
    normalized.startsWith(
      "Sensor "
    ) ||
    normalized.startsWith(
      "Dispositivo "
    ) ||
    normalized.startsWith(
      "Termómetro "
    )
  ) {
    return 2;
  }

  if (
    normalized.indexOf(
      "Beacon"
    ) >= 0 ||
    normalized.endsWith(
      " BLE"
    )
  ) {
    return 3;
  }

  return 4;
}


String cleanBLEIdentification(
  String value
) {
  if (value == null) {
    return "BLE anónimo";
  }

  value = trim(value);

  if (value.length() == 0) {
    return "BLE anónimo";
  }

  return value;
}


String cleanPossibleChannels(
  String value
) {
  if (
    value == null ||
    trim(value).length() == 0
  ) {
    return DEFAULT_BLE_CHANNELS;
  }

  value = trim(value);

  value =
    value.replace(
      "|",
      " / "
    );

  return value;
}


String cleanPossibleFrequencies(
  String value
) {
  if (
    value == null ||
    trim(value).length() == 0
  ) {
    return DEFAULT_BLE_FREQUENCIES;
  }

  value = trim(value);

  value =
    value.replace(
      "|",
      " / "
    );

  if (
    value.indexOf("MHz") < 0
  ) {
    value += " MHz";
  }

  return value;
}


// =====================================================================
// PRIVACIDAD BLE
// =====================================================================

String displayBLEAddress(
  String address
) {
  if (address == null) {
    return "";
  }

  address = trim(address);

  if (
    SHOW_FULL_BLE_ADDRESS ||
    address.length() == 0
  ) {
    return address;
  }

  String[] octets =
    split(
      address,
      ':'
    );

  if (
    octets != null &&
    octets.length == 6
  ) {
    return
      "XX:XX:XX:XX:" +
      octets[4] +
      ":" +
      octets[5];
  }

  octets =
    split(
      address,
      '-'
    );

  if (
    octets != null &&
    octets.length == 6
  ) {
    return
      "XX-XX-XX-XX-" +
      octets[4] +
      "-" +
      octets[5];
  }

  return "DIRECCIÓN OCULTA";
}


String exportBLEAddress(
  String address
) {
  if (EXPORT_FULL_BLE_ADDRESS) {
    return address;
  }

  return displayBLEAddress(
    address
  );
}


void removeExpiredBLEDevices() {
  ArrayList<String> addressesToRemove =
    new ArrayList<String>();

  for (
    String address :
    bleDevices.keySet()
  ) {
    BLEDeviceInfo device =
      bleDevices.get(address);

    if (
      millis() -
      device.lastSeenMillis >
      BLE_REMOVE_TIMEOUT_MS
    ) {
      addressesToRemove.add(
        address
      );
    }
  }

  for (
    String address :
    addressesToRemove
  ) {
    bleDevices.remove(address);
  }
}


// =====================================================================
// TECLADO
// =====================================================================

void keyPressed() {
  if (
    key == 'g' ||
    key == 'G'
  ) {
    handleSaveButton();
  } else if (
    key == 'r' ||
    key == 'R'
  ) {
    resetRFPeaks();
  } else if (
    key == 'c' ||
    key == 'C'
  ) {
    clearBLEDevices();
  } else if (
    key == 'h' ||
    key == 'H'
  ) {
    clearRFHistory();
  }
}


void resetRFPeaks() {
  for (
    int index = 0;
    index < FREQUENCY_COUNT;
    index++
  ) {
    rfPeaks[index] =
      rfValues[index];
  }

  statusMessage =
    "Máximos de detección RF reiniciados";
}


void clearBLEDevices() {
  bleDevices.clear();

  nextBLEDeviceId = 1;

  statusMessage =
    "Lista BLE e historial RSSI limpiados";
}


void clearRFHistory() {
  for (
    int row = 0;
    row < HISTORY_ROWS;
    row++
  ) {
    for (
      int channel = 0;
      channel < FREQUENCY_COUNT;
      channel++
    ) {
      rfHistory[row][channel] = 0;
    }
  }

  historyWriteIndex = 0;

  statusMessage =
    "Historial de detección RF limpiado";
}


// =====================================================================
// ELEMENTOS GENÉRICOS
// =====================================================================

void drawPanel(
  float x,
  float y,
  float w,
  float h
) {
  fill(panelColor);
  stroke(borderColor);
  strokeWeight(1);

  rect(
    x,
    y,
    w,
    h,
    8
  );
}


// =====================================================================
// BARRA INFERIOR
// =====================================================================

void drawFooter(
  float x,
  float y,
  float w,
  float h
) {
  fill(panelSecondaryColor);
  stroke(borderColor);
  strokeWeight(1);

  rect(
    x,
    y,
    w,
    h,
    6
  );

  fill(primaryTextColor);
  noStroke();
  textAlign(LEFT, CENTER);
  textSize(8);

  text(
    "© CrissCCL 2026",
    x + 10,
    y + h / 2
  );

  fill(
    recordingCSV
    ? dangerColor
    : secondaryTextColor
  );

  textAlign(LEFT, CENTER);

  text(
    recordingCSV
    ? "● CSV ACTIVO"
    : "● CSV INACTIVO",
    x + 126,
    y + h / 2
  );

  fill(secondaryTextColor);

  text(
    SHOW_FULL_BLE_ADDRESS
    ? "BLE: DIRECCIÓN VISIBLE"
    : "BLE: DIRECCIÓN PROTEGIDA",
    x + 225,
    y + h / 2
  );

  text(
    "RF: DETECCIÓN RELATIVA",
    x + 390,
    y + h / 2
  );

  textAlign(RIGHT, CENTER);

  text(
    "G: CSV   |   R: máximos RF   |   " +
    "C: limpiar BLE/RSSI   |   H: limpiar historial RF",
    x + w - 10,
    y + h / 2
  );
}


boolean pointInside(
  float pointX,
  float pointY,
  float x,
  float y,
  float w,
  float h
) {
  return
    pointX >= x &&
    pointX <= x + w &&
    pointY >= y &&
    pointY <= y + h;
}


String shortenText(
  String value,
  int maximumLength
) {
  if (
    value == null ||
    value.length() == 0
  ) {
    return "";
  }

  if (
    value.length() <=
    maximumLength
  ) {
    return value;
  }

  return
    value.substring(
      0,
      maximumLength - 1
    ) +
    "…";
}


String radioName(
  int source
) {
  if (source == RADIO_VSPI) {
    return "VSPI";
  }

  if (source == RADIO_HSPI) {
    return "HSPI";
  }

  return "DESCONOCIDO";
}


String csvClean(
  String value
) {
  if (value == null) {
    return "";
  }

  value =
    value.replace(
      ',',
      ' '
    );

  value =
    value.replace(
      '\n',
      ' '
    );

  value =
    value.replace(
      '\r',
      ' '
    );

  return trim(value);
}


// =====================================================================
// CIERRE
// =====================================================================

void exit() {
  if (csvWriter != null) {
    csvWriter.flush();
    csvWriter.close();

    csvWriter = null;
  }

  if (serialPort != null) {
    try {
      serialPort.stop();
    }
    catch (Exception error) {
      println(
        error.getMessage()
      );
    }
  }

  super.exit();
}
