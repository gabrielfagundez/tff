require 'httparty'

# Sleep entre requests
SLEEP_TIME = 0

# URLs
TFF_ENTITY  = 'http://api.taxifarefinder.com/entity?key=d6apr3UDROuv&location='
TFF_CALCULO = 'http://api.taxifarefinder.com/fare?key=d6apr3UDROuv&'

# Este es el archivo de entrada
ENTRADA_TXT = 'coord.txt'

# Este es el archivo de salida
COSTOS_TXT = 'costos.txt'
DURACIONES_TXT = 'duraciones.txt'
SUMMARY_TXT = 'summary.txt'
BANDERA_TXT = 'bandera.txt'
INSTANCIA_TXT = 'instancia.txt'

def log(message)
  puts "> #{Time.now} - #{message}"
end

def folder(first_folder, snd_folder)
  "../#{first_folder}/#{snd_folder}/"
end

def delete_old_files(first_folder, snd_folder)
  log('Borrando archivos viejos')

  # Borramos ejecucion previa del algoritmo si existe
  [COSTOS_TXT, DURACIONES_TXT, BANDERA_TXT, INSTANCIA_TXT].each do |file|
    begin
      FileUtils.rm("../#{first_folder}/#{snd_folder}/#{file}")
    rescue
    end
  end
end

def obtener_entity(lat_lng)
  url = TFF_ENTITY + lat_lng
  log("Obteniendo entity de #{url}")
  http_response = HTTParty.get(url)
  json_response = JSON.parse(http_response.body)

  log("JSON obtenido del entity: #{json_response.inspect}")

  return json_response['handle']
end

def procesar_lat_lng(lat_lng, costos, duraciones, destinos, bandera, entity)
  costo = []
  duracion = []

  destinos.each do |destino|

    # *** *** ***
    # IDA
    parametros = "entity_handle=#{entity}&origin=#{destino}&destination=#{lat_lng}"
    http_response = HTTParty.get(TFF_CALCULO + parametros)
    json_response_ida = JSON[http_response.body]

    # Agrego un sleep para no saturar la API
    sleep(SLEEP_TIME)
    log("JSON obtenido de la consulta para la ida: #{json_response_ida.inspect}")

    # *** *** ***
    # VUELTA
    parametros = "entity_handle=#{entity}&origin=#{lat_lng}&destination=#{destino}"
    http_response = HTTParty.get(TFF_CALCULO + parametros)
    json_response_vuelta = JSON[http_response.body]

    # Agrego un sleep para no saturar la API
    sleep(SLEEP_TIME)
    log("JSON obtenido de la consulta para la vuelta: #{json_response_vuelta.inspect}")


    # Actualizo costos, duracion y bandera
    costo.push({ida: json_response_ida['metered_fare'], vuelta: json_response_vuelta['metered_fare']})
    duracion.push({ida: json_response_ida['duration'], vuelta: json_response_vuelta['duration']})
    bandera = json_response_ida['initial_fare'] if bandera.nil?
  end

  costos.push(costo)
  duraciones.push(duracion)
  destinos.push(lat_lng)

  return {
      costos: costos,
      duraciones: duraciones,
      destinos: destinos,
      bandera: bandera,
      entity: entity
  }
end

def main
  log('Iniciando proceso..')

  %w(1-Chicas).each do |first_folder|
    %w(1).each do |snd_folder|
      log("Analizando carpeta #{first_folder}/#{snd_folder}")

      # Borramos archivos viejos
      delete_old_files(first_folder, snd_folder)

      contador      = 1
      costos        = []
      duraciones    = []
      destinos      = []
      bandera       = nil
      entity        = nil
      hash_response = nil

      # Leemos el archivo linea a linea
      File.open("../#{first_folder}/#{snd_folder}/#{ENTRADA_TXT}", 'r').each_line do |line|
        lat_lng = line.split("\n")[0]

        if destinos.empty?
          entity = obtener_entity(lat_lng)
          destinos.push(lat_lng)
          costos.push([])
          duraciones.push([])
        else
          hash_response = procesar_lat_lng(lat_lng, costos, duraciones, destinos, bandera, entity)
          log("Informacion hasta el momento: #{hash_response.inspect}")
          bandera = hash_response[:bandera]
        end

        log("Linea #{contador} procesada..")

        # Actualizamos el contador
        contador = contador + 1
      end

      log('Procesamiento finalizando, armando archivos')
      fld = folder(first_folder, snd_folder)
      armar_matriz_costos(fld, costos)
      armar_matriz_duraciones(fld, duraciones)
      crear_archivo_de_resumen(fld, hash_response)
      crear_archivo_de_bandera(fld, bandera, entity)
    end
  end

end

def armar_matriz_costos(fld, costos)
  cantidad_marcadores = costos.size
  log('Creando matriz de costos con ' + cantidad_marcadores.to_s + ' marcadores.')

  # Matriz de costos
  matriz_costos = Array.new(cantidad_marcadores) { Array.new(cantidad_marcadores) }

  # Rellenamos la matriz de costos
  for i in 0..(cantidad_marcadores - 1) do
    for j in 0..(cantidad_marcadores - 1) do
      if i == j
        matriz_costos[i][j] = 0
      else
        if i>j
          matriz_costos[i][j] = costos[i][j][:ida]
        else
          matriz_costos[i][j] = costos[j][i][:vuelta]
        end
      end
    end
  end

  `touch #{fld + COSTOS_TXT}`
  File.open(fld + COSTOS_TXT, 'w') do |file|
    for i in 0..(cantidad_marcadores - 1) do
      for j in 0..(cantidad_marcadores - 1) do
        file.write matriz_costos[i][j]
        file.write ' '
      end
      file.write "\n"
    end
  end

  log('Matriz de costos correctamente creada')
  matriz_costos
end

def armar_matriz_duraciones(fld, duraciones)
  cantidad_marcadores = duraciones.size
  log('Creando matriz de duraciones con ' + cantidad_marcadores.to_s + ' marcadores.')

  # Matriz de duraciones
  matriz_duraciones = Array.new(cantidad_marcadores) { Array.new(cantidad_marcadores) }

  # Rellenamos la matriz de duraciones
  for i in 0..(cantidad_marcadores - 1) do
    for j in 0..(cantidad_marcadores - 1) do
      if i == j
        matriz_duraciones[i][j] = 0
      else
        if i>j
          matriz_duraciones[i][j] = duraciones[i][j][:ida]
        else
          matriz_duraciones[i][j] = duraciones[j][i][:vuelta]
        end
      end
    end
  end

  `touch #{fld + DURACIONES_TXT}`
  File.open(fld + DURACIONES_TXT, 'w') do |file|
    for i in 0..(cantidad_marcadores - 1) do
      for j in 0..(cantidad_marcadores - 1) do
        file.write matriz_duraciones[i][j]
        file.write ' '
      end
      file.write "\n"
    end
  end

  log('Matriz de duraciones correctamente creada')
  matriz_duraciones
end

def crear_archivo_de_bandera(fld, bandera, entity)
  log('Creando archivo de bandera')

  `touch #{fld + '/' + BANDERA_TXT}`
  File.open(fld + BANDERA_TXT, 'w') do |file|
    file.write entity.to_s
    file.write "\n"
    file.write bandera.to_s
    file.write "\n"
  end

  log('Archivo de bandera finalizado')
end

def crear_archivo_de_resumen(fld, hash)
  log('Creando archivo de resumen')

  `touch #{fld + '/' + SUMMARY_TXT}`
  File.open(fld + SUMMARY_TXT, 'w') do |file|
    file.write hash.inspect
    file.write "\n"
  end

  log('Archivo de resumen finalizado')
end

# Ejecucion principal
main