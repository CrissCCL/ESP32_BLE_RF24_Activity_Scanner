%% ========================================================================
%  LECTOR CSV DEL SCANNER BLE + DETECTOR RELATIVO DE ENERGÍA RF
%  MATLAB
%  © CrissCCL 2026
%  ========================================================================
%
%  INTERPRETACIÓN RF
%
%  Las columnas:
%
%    ocupacion_filtrada_pct
%    ocupacion_cruda_pct
%
%  representan el porcentaje de ventanas de observación en las que
%  el nRF24L01 detectó energía sobre su umbral RPD/CD.
%
%  No corresponden a:
%
%    - potencia calibrada en dBm;
%    - RSSI;
%    - porcentaje exacto de tiempo ocupado;
%    - identificación del protocolo detectado.
%
%  El programa:
%
%    1. Selecciona y carga el archivo CSV.
%    2. Separa registros RF y BLE.
%    3. Grafica el último barrido RF.
%    4. Compara detección cruda y filtrada.
%    5. Grafica el RSSI BLE.
%    6. Genera un resumen estadístico BLE.
%
%  ========================================================================

clear;
clc;
close all;

%% ========================================================================
%  CONFIGURACIÓN
%  ========================================================================

% Frecuencia que se intenta utilizar para la comparación temporal.
% Si no existe en el archivo, el programa selecciona automáticamente
% la frecuencia con mayor detección filtrada media.
frecuenciaPreferidaMHz = 2426;

% Límites iniciales para la gráfica RSSI.
rssiMinimo_dBm = -110;
rssiMaximo_dBm = -20;

% Guardar automáticamente el resumen BLE.
guardarResumenBLE = true;

%% ========================================================================
%  SELECCIÓN DEL ARCHIVO
%  ========================================================================

[nombreArchivo, carpetaArchivo] = uigetfile( ...
    {'*.csv', 'Archivos CSV (*.csv)'}, ...
    'Seleccione el registro del scanner BLE + RF24');

if isequal(nombreArchivo, 0)
    disp('Selección cancelada.');
    return;
end

rutaArchivo = fullfile(carpetaArchivo, nombreArchivo);

fprintf('\nArchivo seleccionado:\n%s\n\n', rutaArchivo);

%% ========================================================================
%  DETECCIÓN DE OPCIONES DE IMPORTACIÓN
%  ========================================================================

opciones = detectImportOptions( ...
    rutaArchivo, ...
    'Delimiter', ',', ...
    'VariableNamingRule', 'preserve');

columnasTexto = { ...
    'tipo', ...
    'radio', ...
    'direccion', ...
    'identificacion', ...
    'canales_BLE_posibles', ...
    'frecuencias_BLE_posibles_MHz'};

for k = 1:numel(columnasTexto)

    nombreColumna = columnasTexto{k};

    if any(strcmp(opciones.VariableNames, nombreColumna))
        opciones = setvartype( ...
            opciones, ...
            nombreColumna, ...
            'string');
    end

end

datos = readtable(rutaArchivo, opciones);

fprintf('Filas importadas:    %d\n', height(datos));
fprintf('Columnas importadas: %d\n\n', width(datos));

%% ========================================================================
%  VERIFICACIÓN DE COLUMNAS BÁSICAS
%  ========================================================================

columnasObligatorias = { ...
    'tiempo_ms', ...
    'tipo'};

for k = 1:numel(columnasObligatorias)

    nombreColumna = columnasObligatorias{k};

    if ~any(strcmp(datos.Properties.VariableNames, nombreColumna))
        error( ...
            'El CSV no contiene la columna obligatoria "%s".', ...
            nombreColumna);
    end

end

%% ========================================================================
%  RESOLUCIÓN DE NOMBRES RF
%  ========================================================================

% Se admiten tanto los nombres actuales del CSV como nombres futuros
% técnicamente más correctos.

columnaDeteccionFiltrada = buscarPrimeraColumna( ...
    datos, ...
    {'deteccion_filtrada_pct', 'ocupacion_filtrada_pct'});

columnaDeteccionCruda = buscarPrimeraColumna( ...
    datos, ...
    {'deteccion_cruda_pct', 'ocupacion_cruda_pct'});

if strlength(columnaDeteccionFiltrada) == 0
    error( ...
        ['No se encontró una columna de detección filtrada. ' ...
         'Se esperaba "ocupacion_filtrada_pct" o ' ...
         '"deteccion_filtrada_pct".']);
end

if strlength(columnaDeteccionCruda) == 0
    warning( ...
        ['No se encontró detección cruda. Se utilizará la detección ' ...
         'filtrada como respaldo.']);
end

%% ========================================================================
%  CONVERSIÓN DE COLUMNAS NUMÉRICAS
%  ========================================================================

columnasNumericasComunes = { ...
    'tiempo_ms', ...
    'frame', ...
    'frecuencia_MHz', ...
    'rssi_dBm'};

for k = 1:numel(columnasNumericasComunes)

    nombreColumna = columnasNumericasComunes{k};

    if any(strcmp(datos.Properties.VariableNames, nombreColumna))

        datos.(nombreColumna) = convertirANumerico( ...
            datos.(nombreColumna));

    end

end

datos.deteccion_filtrada_pct = convertirANumerico( ...
    datos.(char(columnaDeteccionFiltrada)));

if strlength(columnaDeteccionCruda) > 0

    datos.deteccion_cruda_pct = convertirANumerico( ...
        datos.(char(columnaDeteccionCruda)));

else

    datos.deteccion_cruda_pct = ...
        datos.deteccion_filtrada_pct;

end

%% ========================================================================
%  NORMALIZACIÓN DE COLUMNAS DE TEXTO
%  ========================================================================

datos.tipo = upper(strtrim(string(datos.tipo)));

datos.radio = obtenerColumnaTexto( ...
    datos, ...
    'radio');

datos.direccion = obtenerColumnaTexto( ...
    datos, ...
    'direccion');

datos.identificacion = obtenerColumnaTexto( ...
    datos, ...
    'identificacion');

datos.canales_BLE_posibles = obtenerColumnaTexto( ...
    datos, ...
    'canales_BLE_posibles');

datos.frecuencias_BLE_posibles_MHz = obtenerColumnaTexto( ...
    datos, ...
    'frecuencias_BLE_posibles_MHz');

%% ========================================================================
%  TIEMPO RELATIVO
%  ========================================================================

tiempoInicial = min( ...
    datos.tiempo_ms, ...
    [], ...
    'omitnan');

if isempty(tiempoInicial) || isnan(tiempoInicial)
    tiempoInicial = 0;
end

datos.tiempo_s = ...
    (datos.tiempo_ms - tiempoInicial) / 1000;

%% ========================================================================
%  SEPARACIÓN RF Y BLE
%  ========================================================================

indicesRF = startsWith( ...
    datos.tipo, ...
    "RF");

indicesBLE = ...
    datos.tipo == "BLE";

datosRF = datos(indicesRF, :);
datosBLE = datos(indicesBLE, :);

fprintf('Registros RF:  %d\n', height(datosRF));
fprintf('Registros BLE: %d\n\n', height(datosBLE));

%% ========================================================================
%  ÚLTIMO ESPECTRO RF
%  ========================================================================

if ~isempty(datosRF)

    [espectro, ultimoFrame] = obtenerUltimoEspectro(datosRF);

    if ~isempty(espectro)

        figuraRF = figure( ...
            'Name', 'Detección relativa de energía RF', ...
            'Color', 'w');

        valoresRF = ...
            espectro.deteccion_filtrada_pct;

        barras = bar( ...
            espectro.frecuencia_MHz, ...
            valoresRF, ...
            1.0);

        barras.FaceColor = 'flat';

        for k = 1:height(espectro)

            if espectro.frecuencia_MHz(k) <= 2441
                barras.CData(k, :) = [0.19, 0.72, 0.71];
            else
                barras.CData(k, :) = [0.44, 0.56, 1.00];
            end

        end

        hold on;

        xline( ...
            2402, ...
            '--', ...
            'BLE 37', ...
            'LabelVerticalAlignment', 'bottom');

        xline( ...
            2426, ...
            '--', ...
            'BLE 38', ...
            'LabelVerticalAlignment', 'bottom');

        xline( ...
            2480, ...
            '--', ...
            'BLE 39', ...
            'LabelVerticalAlignment', 'bottom');

        xline( ...
            2441.5, ...
            ':', ...
            'VSPI / HSPI', ...
            'LabelVerticalAlignment', 'middle');

        hold off;

        grid on;
        box on;

        xlabel('Frecuencia [MHz]');

        ylabel( ...
            'Ventanas con detección de energía [%]');

        if isnan(ultimoFrame)

            tituloPrincipal = ...
                'Última detección relativa de energía RF disponible';

        else

            tituloPrincipal = sprintf( ...
                'Detección relativa de energía RF — frame %d', ...
                round(ultimoFrame));

        end

        title({ ...
            tituloPrincipal, ...
            ['Porcentaje filtrado de ventanas con detección; ' ...
             'no corresponde a potencia en dBm']});

        xlim([2401.5, 2480.5]);

        maximoDeteccion = max( ...
            valoresRF, ...
            [], ...
            'omitnan');

        limiteSuperior = calcularLimiteEscalaRF( ...
            maximoDeteccion);

        ylim([0, limiteSuperior]);

        text( ...
            0.99, ...
            0.96, ...
            sprintf('Escala automática: 0–%.0f %%', limiteSuperior), ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', ...
            'FontSize', 8, ...
            'BackgroundColor', 'w');

    else

        warning( ...
            'No fue posible reconstruir el último espectro RF.');

    end

else

    warning( ...
        'El archivo no contiene registros RF.');

end

%% ========================================================================
%  DETECCIÓN CRUDA Y FILTRADA RESPECTO DEL TIEMPO
%  ========================================================================

if ~isempty(datosRF)

    frecuenciaAnalizadaMHz = seleccionarFrecuenciaAnalisis( ...
        datosRF, ...
        frecuenciaPreferidaMHz);

    if ~isnan(frecuenciaAnalizadaMHz)

        datosCanal = datosRF( ...
            datosRF.frecuencia_MHz == frecuenciaAnalizadaMHz, :);

        datosCanal = sortrows( ...
            datosCanal, ...
            'tiempo_s');

        datosCanal = datosCanal( ...
            ~isnan(datosCanal.tiempo_s), :);

        if ~isempty(datosCanal)

            figure( ...
                'Name', 'Detección RF cruda y filtrada', ...
                'Color', 'w');

            stairs( ...
                datosCanal.tiempo_s, ...
                datosCanal.deteccion_cruda_pct, ...
                'LineWidth', 1.0, ...
                'DisplayName', 'Detección cruda');

            hold on;

            plot( ...
                datosCanal.tiempo_s, ...
                datosCanal.deteccion_filtrada_pct, ...
                'LineWidth', 1.6, ...
                'DisplayName', 'Detección filtrada');

            hold off;

            grid on;
            box on;

            xlabel('Tiempo [s]');

            ylabel( ...
                'Ventanas con detección de energía [%]');

            title({ ...
                sprintf( ...
                    'Detección relativa de energía RF en %.0f MHz', ...
                    frecuenciaAnalizadaMHz), ...
                ['El valor crudo avanza en pasos discretos; ' ...
                 'el valor filtrado suaviza la visualización']});

            legend( ...
                'Location', ...
                'best');

            maximoCanal = max( ...
                [ ...
                    datosCanal.deteccion_cruda_pct; ...
                    datosCanal.deteccion_filtrada_pct ...
                ], ...
                [], ...
                'omitnan');

            limiteSuperior = calcularLimiteEscalaRF( ...
                maximoCanal);

            ylim([0, limiteSuperior]);

        end

    end

end

%% ========================================================================
%  RSSI BLE RESPECTO DEL TIEMPO
%  ========================================================================

if ~isempty(datosBLE)

    identificadoresBLE = obtenerIdentificadoresBLE( ...
        datosBLE);

    dispositivosUnicos = unique( ...
        identificadoresBLE, ...
        'stable');

    figure( ...
        'Name', 'RSSI Bluetooth LE', ...
        'Color', 'w');

    hold on;

    for k = 1:numel(dispositivosUnicos)

        dispositivoActual = ...
            dispositivosUnicos(k);

        indicesDispositivo = ...
            identificadoresBLE == dispositivoActual;

        tiempoDispositivo = ...
            datosBLE.tiempo_s(indicesDispositivo);

        rssiDispositivo = ...
            datosBLE.rssi_dBm(indicesDispositivo);

        indicesValidos = ...
            ~isnan(tiempoDispositivo) & ...
            ~isnan(rssiDispositivo);

        tiempoDispositivo = ...
            tiempoDispositivo(indicesValidos);

        rssiDispositivo = ...
            rssiDispositivo(indicesValidos);

        [tiempoDispositivo, orden] = sort( ...
            tiempoDispositivo);

        rssiDispositivo = ...
            rssiDispositivo(orden);

        if isempty(tiempoDispositivo)
            continue;
        end

        plot( ...
            tiempoDispositivo, ...
            rssiDispositivo, ...
            '-o', ...
            'LineWidth', 1.2, ...
            'MarkerSize', 3, ...
            'DisplayName', dispositivoActual);

    end

    hold off;

    grid on;
    box on;

    xlabel('Tiempo [s]');
    ylabel('RSSI [dBm]');

    title({ ...
        'RSSI de dispositivos Bluetooth LE', ...
        'Medición independiente del detector relativo de energía RF'});

    ylim([rssiMinimo_dBm, rssiMaximo_dBm]);

    leyendaRSSI = legend( ...
        'Location', ...
        'eastoutside');

    leyendaRSSI.Interpreter = 'none';

else

    warning( ...
        'El archivo no contiene registros BLE.');

end

%% ========================================================================
%  RESUMEN DE DISPOSITIVOS BLE
%  ========================================================================

if ~isempty(datosBLE)

    identificadoresBLE = obtenerIdentificadoresBLE( ...
        datosBLE);

    dispositivosUnicos = unique( ...
        identificadoresBLE, ...
        'stable');

    resumenBLE = table( ...
        'Size', [numel(dispositivosUnicos), 8], ...
        'VariableTypes', { ...
            'string', ...
            'string', ...
            'double', ...
            'double', ...
            'double', ...
            'double', ...
            'double', ...
            'double'}, ...
        'VariableNames', { ...
            'Dispositivo', ...
            'Direccion', ...
            'CantidadTramas', ...
            'RSSIMedio_dBm', ...
            'RSSIMaximo_dBm', ...
            'RSSIMinimo_dBm', ...
            'PrimerTiempo_s', ...
            'UltimoTiempo_s'});

    for k = 1:numel(dispositivosUnicos)

        dispositivoActual = ...
            dispositivosUnicos(k);

        indicesDispositivo = ...
            identificadoresBLE == dispositivoActual;

        rssiActual = ...
            datosBLE.rssi_dBm(indicesDispositivo);

        tiempoActual = ...
            datosBLE.tiempo_s(indicesDispositivo);

        direccionesActuales = unique( ...
            datosBLE.direccion(indicesDispositivo), ...
            'stable');

        direccionesActuales = direccionesActuales( ...
            direccionesActuales ~= "");

        if isempty(direccionesActuales)
            direccionMostrada = "";
        else
            direccionMostrada = direccionesActuales(1);
        end

        resumenBLE.Dispositivo(k) = ...
            dispositivoActual;

        resumenBLE.Direccion(k) = ...
            direccionMostrada;

        resumenBLE.CantidadTramas(k) = ...
            sum(~isnan(rssiActual));

        resumenBLE.RSSIMedio_dBm(k) = ...
            mean(rssiActual, 'omitnan');

        resumenBLE.RSSIMaximo_dBm(k) = ...
            max(rssiActual, [], 'omitnan');

        resumenBLE.RSSIMinimo_dBm(k) = ...
            min(rssiActual, [], 'omitnan');

        resumenBLE.PrimerTiempo_s(k) = ...
            min(tiempoActual, [], 'omitnan');

        resumenBLE.UltimoTiempo_s(k) = ...
            max(tiempoActual, [], 'omitnan');

    end

    resumenBLE = sortrows( ...
        resumenBLE, ...
        'RSSIMedio_dBm', ...
        'descend');

    disp('Resumen de dispositivos BLE:');
    disp(resumenBLE);

    if guardarResumenBLE

        [~, nombreSinExtension, ~] = fileparts( ...
            nombreArchivo);

        rutaResumen = fullfile( ...
            carpetaArchivo, ...
            [nombreSinExtension, '_resumen_BLE.csv']);

        writetable( ...
            resumenBLE, ...
            rutaResumen);

        fprintf( ...
            '\nResumen BLE guardado en:\n%s\n', ...
            rutaResumen);

    end

end

%% ========================================================================
%  FUNCIONES LOCALES
%  ========================================================================

function salida = convertirANumerico(entrada)

    if isnumeric(entrada)
        salida = double(entrada);
        return;
    end

    texto = string(entrada);

    texto = replace( ...
        texto, ...
        ",", ...
        ".");

    texto = strtrim(texto);

    salida = str2double(texto);

end


function nombreEncontrado = buscarPrimeraColumna( ...
    tabla, ...
    candidatos)

    nombreEncontrado = "";

    nombresDisponibles = string( ...
        tabla.Properties.VariableNames);

    for k = 1:numel(candidatos)

        candidato = string(candidatos{k});

        if any(nombresDisponibles == candidato)
            nombreEncontrado = candidato;
            return;
        end

    end

end


function columna = obtenerColumnaTexto( ...
    tabla, ...
    nombre)

    if any(strcmp( ...
            tabla.Properties.VariableNames, ...
            nombre))

        columna = strtrim( ...
            string(tabla.(nombre)));

    else

        columna = strings( ...
            height(tabla), ...
            1);

    end

end


function [espectro, ultimoFrame] = obtenerUltimoEspectro( ...
    datosRF)

    ultimoFrame = NaN;

    if isempty(datosRF)

        espectro = datosRF;
        return;

    end

    if any(strcmp( ...
            datosRF.Properties.VariableNames, ...
            'frame'))

        framesValidos = ...
            datosRF.frame(~isnan(datosRF.frame));

    else

        framesValidos = [];

    end

    if ~isempty(framesValidos)

        ultimoFrame = max(framesValidos);

        espectro = datosRF( ...
            datosRF.frame == ultimoFrame, :);

    else

        espectro = sortrows( ...
            datosRF, ...
            'tiempo_ms');

        [~, indicesUltimos] = unique( ...
            espectro.frecuencia_MHz, ...
            'last');

        espectro = ...
            espectro(indicesUltimos, :);

    end

    espectro = espectro( ...
        ~isnan(espectro.frecuencia_MHz), :);

    espectro = sortrows( ...
        espectro, ...
        'frecuencia_MHz');

end


function limite = calcularLimiteEscalaRF( ...
    maximo)

    if isempty(maximo) || isnan(maximo)
        maximo = 0;
    end

    if maximo <= 5
        limite = 5;
    elseif maximo <= 10
        limite = 10;
    elseif maximo <= 20
        limite = 20;
    elseif maximo <= 50
        limite = 50;
    else
        limite = 100;
    end

end


function frecuenciaSeleccionada = seleccionarFrecuenciaAnalisis( ...
    datosRF, ...
    frecuenciaPreferida)

    frecuenciasDisponibles = unique( ...
        datosRF.frecuencia_MHz( ...
            ~isnan(datosRF.frecuencia_MHz)));

    if isempty(frecuenciasDisponibles)

        frecuenciaSeleccionada = NaN;
        return;

    end

    if any(frecuenciasDisponibles == frecuenciaPreferida)

        frecuenciaSeleccionada = frecuenciaPreferida;
        return;

    end

    mejorMedia = -Inf;
    frecuenciaSeleccionada = frecuenciasDisponibles(1);

    for k = 1:numel(frecuenciasDisponibles)

        frecuenciaActual = frecuenciasDisponibles(k);

        valores = datosRF.deteccion_filtrada_pct( ...
            datosRF.frecuencia_MHz == frecuenciaActual);

        mediaActual = mean( ...
            valores, ...
            'omitnan');

        if ~isnan(mediaActual) && mediaActual > mejorMedia

            mejorMedia = mediaActual;
            frecuenciaSeleccionada = frecuenciaActual;

        end

    end

end


function identificadores = obtenerIdentificadoresBLE( ...
    datosBLE)

    identificacion = strtrim( ...
        string(datosBLE.identificacion));

    direccion = strtrim( ...
        string(datosBLE.direccion));

    identificadores = identificacion;

    identificacionesGenericas = ...
        ismissing(identificadores) | ...
        identificadores == "" | ...
        identificadores == "BLE anónimo" | ...
        identificadores == "Sin nombre";

    identificadores(identificacionesGenericas) = ...
        direccion(identificacionesGenericas);

    indicesVacios = ...
        ismissing(identificadores) | ...
        identificadores == "";

    posicionesVacias = find(indicesVacios);

    for k = 1:numel(posicionesVacias)

        indice = posicionesVacias(k);

        identificadores(indice) = ...
            "BLE_" + string(indice);

    end

end