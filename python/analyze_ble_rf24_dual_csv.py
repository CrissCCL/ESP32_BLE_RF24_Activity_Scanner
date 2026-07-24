"""
========================================================================
LECTOR CSV DEL SCANNER BLE + DETECTOR RELATIVO DE ENERGÍA RF
PYTHON
© CrissCCL 2026
========================================================================

INTERPRETACIÓN RF

Las columnas históricas del CSV:

    ocupacion_filtrada_pct
    ocupacion_cruda_pct

representan el porcentaje de ventanas de observación en las que el
nRF24L01 detectó energía sobre su umbral RPD/CD.

No representan:

    - potencia calibrada en dBm;
    - RSSI;
    - porcentaje exacto de tiempo ocupado;
    - identificación del protocolo detectado.

El programa crea internamente:

    deteccion_filtrada_pct
    deteccion_cruda_pct

y mantiene compatibilidad con ambos nombres.
"""

from __future__ import annotations

from pathlib import Path
from tkinter import Tk, filedialog

import matplotlib.pyplot as plt
import pandas as pd


# ======================================================================
# CONFIGURACIÓN
# ======================================================================

FRECUENCIA_PREFERIDA_MHZ = 2426

RSSI_MINIMO_DBM = -110
RSSI_MAXIMO_DBM = -20

GUARDAR_RESUMEN_BLE = True


# ======================================================================
# NOMBRES Y ALIAS DE COLUMNAS
# ======================================================================

COLUMNAS_OBLIGATORIAS = [
    "tiempo_ms",
    "tipo",
]

COLUMNAS_NUMERICAS_COMUNES = [
    "tiempo_ms",
    "frame",
    "frecuencia_MHz",
    "rssi_dBm",
]

COLUMNAS_TEXTO = [
    "tipo",
    "radio",
    "direccion",
    "identificacion",
    "canales_BLE_posibles",
    "frecuencias_BLE_posibles_MHz",
]

ALIAS_DETECCION_FILTRADA = [
    "deteccion_filtrada_pct",
    "ocupacion_filtrada_pct",
]

ALIAS_DETECCION_CRUDA = [
    "deteccion_cruda_pct",
    "ocupacion_cruda_pct",
]


# ======================================================================
# SELECCIÓN DEL ARCHIVO
# ======================================================================

def seleccionar_csv() -> Path | None:
    """Abre una ventana para seleccionar el archivo CSV."""

    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    ruta = filedialog.askopenfilename(
        title="Seleccione el registro del scanner BLE + RF24",
        filetypes=[
            ("Archivos CSV", "*.csv"),
            ("Todos los archivos", "*.*"),
        ],
    )

    root.destroy()

    if not ruta:
        return None

    return Path(ruta)


# ======================================================================
# FUNCIONES DE IMPORTACIÓN
# ======================================================================

def buscar_primera_columna(
    datos: pd.DataFrame,
    candidatos: list[str],
) -> str | None:
    """Devuelve el primer nombre de columna disponible."""

    for candidato in candidatos:
        if candidato in datos.columns:
            return candidato

    return None


def convertir_columna_numerica(
    serie: pd.Series,
) -> pd.Series:
    """Convierte una columna numérica tolerando texto y comas decimales."""

    return pd.to_numeric(
        serie
        .astype(str)
        .str.strip()
        .str.replace(",", ".", regex=False),
        errors="coerce",
    )


def cargar_csv(ruta: Path) -> pd.DataFrame:
    """
    Carga el CSV, valida sus columnas y crea nombres internos
    técnicamente correctos para las detecciones RF.
    """

    try:
        datos = pd.read_csv(
            ruta,
            sep=",",
            encoding="utf-8-sig",
            low_memory=False,
        )
    except UnicodeDecodeError:
        datos = pd.read_csv(
            ruta,
            sep=",",
            encoding="latin-1",
            low_memory=False,
        )

    datos.columns = [
        str(columna).strip()
        for columna in datos.columns
    ]

    faltantes = [
        columna
        for columna in COLUMNAS_OBLIGATORIAS
        if columna not in datos.columns
    ]

    if faltantes:
        raise ValueError(
            "El CSV no contiene las columnas obligatorias: "
            f"{faltantes}"
        )

    columna_filtrada = buscar_primera_columna(
        datos,
        ALIAS_DETECCION_FILTRADA,
    )

    columna_cruda = buscar_primera_columna(
        datos,
        ALIAS_DETECCION_CRUDA,
    )

    if columna_filtrada is None:
        raise ValueError(
            "No se encontró la columna de detección filtrada. "
            "Se esperaba 'ocupacion_filtrada_pct' o "
            "'deteccion_filtrada_pct'."
        )

    for columna in COLUMNAS_NUMERICAS_COMUNES:
        if columna in datos.columns:
            datos[columna] = convertir_columna_numerica(
                datos[columna]
            )
        else:
            datos[columna] = float("nan")

    datos["deteccion_filtrada_pct"] = (
        convertir_columna_numerica(
            datos[columna_filtrada]
        )
    )

    if columna_cruda is not None:
        datos["deteccion_cruda_pct"] = (
            convertir_columna_numerica(
                datos[columna_cruda]
            )
        )
    else:
        print(
            "Advertencia: no se encontró detección cruda. "
            "Se utilizará la detección filtrada como respaldo."
        )

        datos["deteccion_cruda_pct"] = (
            datos["deteccion_filtrada_pct"]
        )

    for columna in COLUMNAS_TEXTO:
        if columna not in datos.columns:
            datos[columna] = ""
        else:
            datos[columna] = (
                datos[columna]
                .fillna("")
                .astype(str)
                .str.strip()
            )

    datos["tipo"] = datos["tipo"].str.upper()

    tiempo_inicial = datos["tiempo_ms"].min()

    if pd.isna(tiempo_inicial):
        tiempo_inicial = 0.0

    datos["tiempo_s"] = (
        datos["tiempo_ms"] -
        tiempo_inicial
    ) / 1000.0

    return datos


# ======================================================================
# ESCALA RF
# ======================================================================

def calcular_limite_escala_rf(
    maximo: float,
) -> float:
    """
    Devuelve el límite superior visual equivalente al utilizado
    en la interfaz Processing.
    """

    if pd.isna(maximo):
        maximo = 0.0

    if maximo <= 5:
        return 5.0

    if maximo <= 10:
        return 10.0

    if maximo <= 20:
        return 20.0

    if maximo <= 50:
        return 50.0

    return 100.0


# ======================================================================
# ESPECTRO RF
# ======================================================================

def obtener_ultimo_espectro(
    datos_rf: pd.DataFrame,
) -> tuple[pd.DataFrame, float | None]:
    """Obtiene el último barrido RF completo disponible."""

    if datos_rf.empty:
        return datos_rf.copy(), None

    frames_validos = (
        datos_rf["frame"]
        .dropna()
    )

    if not frames_validos.empty:
        ultimo_frame = frames_validos.max()

        espectro = datos_rf.loc[
            datos_rf["frame"] ==
            ultimo_frame
        ].copy()
    else:
        ultimo_frame = None

        espectro = (
            datos_rf
            .sort_values("tiempo_ms")
            .drop_duplicates(
                subset="frecuencia_MHz",
                keep="last",
            )
            .copy()
        )

    espectro = (
        espectro
        .dropna(subset=["frecuencia_MHz"])
        .sort_values("frecuencia_MHz")
    )

    return espectro, ultimo_frame


def graficar_espectro(
    datos_rf: pd.DataFrame,
) -> None:
    """Grafica el último espectro RF disponible."""

    espectro, ultimo_frame = (
        obtener_ultimo_espectro(datos_rf)
    )

    if espectro.empty:
        print("No existen datos RF para graficar.")
        return

    colores = [
        "tab:cyan"
        if frecuencia <= 2441
        else "tab:blue"
        for frecuencia in espectro[
            "frecuencia_MHz"
        ]
    ]

    plt.figure(
        "Detección relativa de energía RF",
        figsize=(12, 5.5),
    )

    plt.bar(
        espectro["frecuencia_MHz"],
        espectro["deteccion_filtrada_pct"],
        width=0.92,
        color=colores,
        linewidth=0,
    )

    plt.axvline(
        2402,
        linestyle="--",
        linewidth=1,
        label="BLE 37",
    )

    plt.axvline(
        2426,
        linestyle="--",
        linewidth=1,
        label="BLE 38",
    )

    plt.axvline(
        2480,
        linestyle="--",
        linewidth=1,
        label="BLE 39",
    )

    plt.axvline(
        2441.5,
        linestyle=":",
        linewidth=1.2,
        label="Separación VSPI/HSPI",
    )

    if ultimo_frame is None:
        titulo = (
            "Última detección relativa "
            "de energía RF disponible"
        )
    else:
        titulo = (
            "Detección relativa de energía RF — "
            f"frame {int(ultimo_frame)}"
        )

    plt.title(
        titulo
        + "\n"
        + (
            "Porcentaje filtrado de ventanas con detección; "
            "no corresponde a potencia en dBm"
        )
    )

    plt.xlabel("Frecuencia [MHz]")

    plt.ylabel(
        "Ventanas con detección de energía [%]"
    )

    plt.xlim(2401.5, 2480.5)

    maximo = (
        espectro["deteccion_filtrada_pct"]
        .max()
    )

    limite_superior = calcular_limite_escala_rf(
        maximo
    )

    plt.ylim(0, limite_superior)

    plt.text(
        0.99,
        0.96,
        f"Escala automática: 0–{limite_superior:.0f} %",
        transform=plt.gca().transAxes,
        horizontalalignment="right",
        verticalalignment="top",
        fontsize=8,
        bbox={
            "facecolor": "white",
            "alpha": 0.8,
            "edgecolor": "none",
        },
    )

    plt.grid(
        True,
        axis="y",
        alpha=0.3,
    )

    plt.legend(
        loc="upper right",
        fontsize=8,
    )

    plt.tight_layout()


# ======================================================================
# FRECUENCIA PARA ANÁLISIS TEMPORAL
# ======================================================================

def seleccionar_frecuencia_analisis(
    datos_rf: pd.DataFrame,
    frecuencia_preferida: int,
) -> float | None:
    """
    Usa la frecuencia preferida cuando está disponible.

    En caso contrario, selecciona la frecuencia con mayor detección
    filtrada media.
    """

    frecuencias = (
        datos_rf["frecuencia_MHz"]
        .dropna()
        .unique()
    )

    if len(frecuencias) == 0:
        return None

    if frecuencia_preferida in frecuencias:
        return float(frecuencia_preferida)

    medias = (
        datos_rf
        .groupby("frecuencia_MHz")[
            "deteccion_filtrada_pct"
        ]
        .mean()
        .dropna()
    )

    if medias.empty:
        return float(frecuencias[0])

    return float(
        medias.idxmax()
    )


# ======================================================================
# DETECCIÓN CRUDA Y FILTRADA
# ======================================================================

def graficar_deteccion_cruda_filtrada(
    datos_rf: pd.DataFrame,
    frecuencia_preferida_mhz: int = 2426,
) -> None:
    """
    Compara el porcentaje crudo de ventanas con detección
    con el valor filtrado enviado por el firmware.
    """

    frecuencia = seleccionar_frecuencia_analisis(
        datos_rf,
        frecuencia_preferida_mhz,
    )

    if frecuencia is None:
        print(
            "No fue posible seleccionar una frecuencia RF."
        )
        return

    canal = datos_rf.loc[
        datos_rf["frecuencia_MHz"] ==
        frecuencia
    ].copy()

    canal = (
        canal
        .dropna(
            subset=[
                "tiempo_s",
                "deteccion_cruda_pct",
                "deteccion_filtrada_pct",
            ]
        )
        .sort_values("tiempo_s")
    )

    if canal.empty:
        print(
            "No existen muestras válidas para "
            f"{frecuencia:.0f} MHz."
        )
        return

    plt.figure(
        "Detección RF cruda y filtrada",
        figsize=(12, 5),
    )

    plt.step(
        canal["tiempo_s"],
        canal["deteccion_cruda_pct"],
        where="post",
        linewidth=1.0,
        label="Detección cruda",
    )

    plt.plot(
        canal["tiempo_s"],
        canal["deteccion_filtrada_pct"],
        linewidth=1.6,
        label="Detección filtrada",
    )

    plt.title(
        "Detección relativa de energía RF "
        f"en {frecuencia:.0f} MHz\n"
        "El valor crudo es discreto; "
        "el filtrado suaviza la visualización"
    )

    plt.xlabel("Tiempo [s]")

    plt.ylabel(
        "Ventanas con detección de energía [%]"
    )

    maximo = max(
        canal["deteccion_cruda_pct"].max(),
        canal["deteccion_filtrada_pct"].max(),
    )

    limite_superior = calcular_limite_escala_rf(
        maximo
    )

    plt.ylim(0, limite_superior)

    plt.grid(
        True,
        alpha=0.3,
    )

    plt.legend()
    plt.tight_layout()


# ======================================================================
# IDENTIFICADORES BLE
# ======================================================================

def construir_identificador_ble(
    datos_ble: pd.DataFrame,
) -> pd.Series:
    """
    Usa la identificación BLE como nombre principal.

    Cuando la identificación es genérica, utiliza la dirección
    completa o protegida almacenada en el CSV.
    """

    identificacion = (
        datos_ble["identificacion"]
        .fillna("")
        .astype(str)
        .str.strip()
    )

    direccion = (
        datos_ble["direccion"]
        .fillna("")
        .astype(str)
        .str.strip()
    )

    identificadores = identificacion.copy()

    identificaciones_genericas = {
        "",
        "BLE anónimo",
        "Sin nombre",
        "nan",
    }

    mascara_generica = (
        identificadores
        .isin(identificaciones_genericas)
    )

    identificadores.loc[mascara_generica] = (
        direccion.loc[mascara_generica]
    )

    mascara_vacia = (
        identificadores
        .isin({"", "nan"})
    )

    indices_vacios = identificadores.index[
        mascara_vacia
    ]

    for numero, indice in enumerate(
        indices_vacios,
        start=1,
    ):
        identificadores.loc[indice] = (
            f"BLE_{numero}"
        )

    return identificadores


# ======================================================================
# RSSI BLE
# ======================================================================

def graficar_rssi(
    datos_ble: pd.DataFrame,
) -> None:
    """Grafica el RSSI BLE respecto del tiempo."""

    if datos_ble.empty:
        print("No existen registros BLE.")
        return

    datos_ble = datos_ble.copy()

    datos_ble["dispositivo"] = (
        construir_identificador_ble(
            datos_ble
        )
    )

    plt.figure(
        "RSSI Bluetooth LE",
        figsize=(12, 6),
    )

    for dispositivo, grupo in (
        datos_ble.groupby(
            "dispositivo",
            sort=False,
        )
    ):
        grupo = (
            grupo
            .dropna(
                subset=[
                    "tiempo_s",
                    "rssi_dBm",
                ]
            )
            .sort_values("tiempo_s")
        )

        if grupo.empty:
            continue

        plt.plot(
            grupo["tiempo_s"],
            grupo["rssi_dBm"],
            marker="o",
            markersize=3,
            linewidth=1.2,
            label=dispositivo,
        )

    plt.title(
        "RSSI de dispositivos Bluetooth LE\n"
        "Medición independiente del detector relativo de energía RF"
    )

    plt.xlabel("Tiempo [s]")
    plt.ylabel("RSSI [dBm]")

    plt.ylim(
        RSSI_MINIMO_DBM,
        RSSI_MAXIMO_DBM,
    )

    plt.grid(
        True,
        alpha=0.3,
    )

    plt.legend(
        loc="center left",
        bbox_to_anchor=(1.02, 0.5),
        fontsize=8,
    )

    plt.tight_layout()


# ======================================================================
# RESUMEN BLE
# ======================================================================

def crear_resumen_ble(
    datos_ble: pd.DataFrame,
) -> pd.DataFrame:
    """Calcula estadísticas por dispositivo BLE."""

    if datos_ble.empty:
        return pd.DataFrame()

    datos_ble = datos_ble.copy()

    datos_ble["dispositivo"] = (
        construir_identificador_ble(
            datos_ble
        )
    )

    resumen = (
        datos_ble
        .groupby(
            "dispositivo",
            sort=False,
        )
        .agg(
            direccion=(
                "direccion",
                lambda serie: next(
                    (
                        valor
                        for valor in serie
                        if str(valor).strip()
                    ),
                    "",
                ),
            ),
            cantidad_tramas=(
                "rssi_dBm",
                "count",
            ),
            rssi_medio_dBm=(
                "rssi_dBm",
                "mean",
            ),
            rssi_maximo_dBm=(
                "rssi_dBm",
                "max",
            ),
            rssi_minimo_dBm=(
                "rssi_dBm",
                "min",
            ),
            primer_tiempo_s=(
                "tiempo_s",
                "min",
            ),
            ultimo_tiempo_s=(
                "tiempo_s",
                "max",
            ),
        )
        .reset_index()
        .sort_values(
            "rssi_medio_dBm",
            ascending=False,
        )
    )

    columnas_decimales = [
        "rssi_medio_dBm",
        "rssi_maximo_dBm",
        "rssi_minimo_dBm",
        "primer_tiempo_s",
        "ultimo_tiempo_s",
    ]

    resumen[columnas_decimales] = (
        resumen[columnas_decimales]
        .round(2)
    )

    return resumen


# ======================================================================
# PROGRAMA PRINCIPAL
# ======================================================================

def main() -> None:
    ruta = seleccionar_csv()

    if ruta is None:
        print("Selección cancelada.")
        return

    print(f"\nArchivo seleccionado:\n{ruta}\n")

    try:
        datos = cargar_csv(ruta)
    except Exception as error:
        print(
            "No se pudo leer el archivo:\n"
            f"{error}"
        )
        return

    datos_rf = datos.loc[
        datos["tipo"].str.startswith("RF")
    ].copy()

    datos_ble = datos.loc[
        datos["tipo"] == "BLE"
    ].copy()

    print(
        f"Filas importadas: {len(datos)}"
    )

    print(
        f"Registros RF: {len(datos_rf)}"
    )

    print(
        f"Registros BLE: {len(datos_ble)}"
    )

    resumen_ble = crear_resumen_ble(
        datos_ble
    )

    if not resumen_ble.empty:
        print(
            "\nResumen de dispositivos BLE:"
        )

        print(
            resumen_ble.to_string(
                index=False
            )
        )

        if GUARDAR_RESUMEN_BLE:
            ruta_resumen = (
                ruta.parent /
                f"{ruta.stem}_resumen_BLE.csv"
            )

            resumen_ble.to_csv(
                ruta_resumen,
                index=False,
                encoding="utf-8-sig",
            )

            print(
                "\nResumen BLE guardado en:"
            )

            print(ruta_resumen)

    graficar_espectro(
        datos_rf
    )

    graficar_deteccion_cruda_filtrada(
        datos_rf,
        frecuencia_preferida_mhz=(
            FRECUENCIA_PREFERIDA_MHZ
        ),
    )

    graficar_rssi(
        datos_ble
    )

    plt.show()


if __name__ == "__main__":
    main()