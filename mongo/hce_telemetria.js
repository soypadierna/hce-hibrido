// hce_telemetria.js: crea la colección de telemetría (no toca las 9 colecciones clínicas)
(function () {
  db = db.getSiblingDB("hce_hospitalizacion");
  // Borrado previo solo de la colección nueva para poder re-ejecutar
  db.telemetria_eventos.drop();
  // Validador: ids de Supabase como int/long; sin additionalProperties:false para permitir pasos y bateria
  db.createCollection("telemetria_eventos", { validator: { $jsonSchema: {
    bsonType: "object",
    required: ["pg_paciente_id", "pg_encuentro_id", "pg_dispositivo_id", "tipo", "ts", "metricas"],
    properties: {
      pg_paciente_id: { bsonType: ["int", "long"] },
      pg_encuentro_id: { bsonType: ["int", "long"] },
      pg_dispositivo_id: { bsonType: ["int", "long"] },
      tipo: { enum: ["wearable", "monitor", "oximetro"] },
      ts: { bsonType: "date" },
      metricas: { bsonType: "object",
        properties: { fc: { bsonType: "number" }, spo2: { bsonType: "number" }, temp: { bsonType: "number" }, ta_sis: { bsonType: "number" }, ta_dia: { bsonType: "number" } } } } } } });
  // Índices por encuentro/tiempo y por paciente/tiempo
  db.telemetria_eventos.createIndex({ pg_encuentro_id: 1, ts: -1 });
  db.telemetria_eventos.createIndex({ pg_paciente_id: 1, ts: -1 });
  print("telemetria_eventos lista");
})();