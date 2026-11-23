# HCE Híbrida: PostgreSQL (ACID) + MongoDB (BASE)

Actividad de Bases de Datos II. Arquitectura de persistencia híbrida para la Historia Clínica Electrónica de hospitalización: identidad y datos maestros en PostgreSQL (Supabase), telemetría masiva de wearables en MongoDB (Compass). Todos los datos son ficticios.

## Arquitectura

Diagrama en [`esquema/arquitectura.md`](esquema/arquitectura.md).

| Capa | Motor | Qué guarda | Por qué |
|---|---|---|---|
| ACID | PostgreSQL (Supabase) | `paciente`, `profesional_salud`, `encuentro_clinico`, `dispositivos` y `telemetria_pg` (para el benchmark) | Integridad referencial y transacciones sobre identidad y datos maestros |
| BASE | MongoDB (Compass) | `telemetria_eventos`: eventos JSON de sensores | Ingesta rápida y esquema flexible (los wearables añaden `pasos` y `bateria`) |

**Puente entre motores:** cada evento de MongoDB guarda `pg_paciente_id`, `pg_encuentro_id` y `pg_dispositivo_id` (ids de Supabase). MongoDB no guarda identidad del paciente.

## Estructura

```text
hce_hibrida/
├── sql/03_telemetria.sql          Supabase: dispositivos y telemetria_pg
├── scripts/
│   ├── hce_telemetria.js          Compass (mongosh): colección, validador e índices
│   ├── ingesta.py                 Misma carga en ambos motores, con tiempos
│   ├── benchmark.py               Q1 a Q4 y gráfico
│   └── verificacion.py            Integridad entre motores
├── resultados/                    ingesta.json, benchmark.json, latencia.png
├── esquema/                       Diagramas Mermaid
├── capturas/  ia/  informe/  video/
├── .env.example  requirements.txt  docker-compose.yml
```

## Requisitos

- Proyecto Supabase con el HCE de la actividad anterior (tablas `paciente` y `encuentro_clinico`)
- MongoDB Compass con una instancia local (`docker compose up -d`) o Atlas
- Python 3.13 y PowerShell

## Instalación y ejecución

1. Variables de entorno:
```powershell
Copy-Item .env.example .env
```
Completa `PG_URL` con el **Session pooler** de Supabase (Connect → Session pooler; la conexión directa usa IPv6 y puede fallar) y `MONGO_URI` con la URI de Compass.

2. Supabase → SQL Editor: pegar y ejecutar `sql/03_telemetria.sql` (resultado esperado: 200 dispositivos).

3. Compass → mongosh: pegar completo `scripts/hce_telemetria.js` (imprime `telemetria_eventos lista`).

4. Entorno Python:
```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

5. Ingesta, benchmark y verificación:
```powershell
python scripts/ingesta.py
python scripts/benchmark.py
python scripts/verificacion.py
```

## Resultados

100 000 eventos ficticios, misma data insertada en ambos motores.

**Ingesta**

| Motor | Segundos | Eventos/s |
|---|---|---|
| MongoDB | 1.282 | 78 021 |
| PostgreSQL | 14.377 | 6 955 |

MongoDB ingiere unas 11 veces más rápido. Conteos finales: 100 000 en ambos motores.

**Latencia por operación** (mediana, ms)

| Op. | Descripción | PostgreSQL | MongoDB | Relación |
|---|---|---|---|---|
| Q1 | Eventos de 1 encuentro en 1 día | 204.48 | 21.92 | 9.3x más rápido en MongoDB |
| Q2 | Promedio de FC por encuentro | 159.45 | 50.60 | 3.2x |
| Q3 | Promedio de FC por paciente con nombre | 169.90 | 160.04 | 1.1x (paridad) |
| Q4 | Agregar el campo `glucosa` | 247.62 | 0.84 | 294x |

Gráfico: [`resultados/latencia.png`](resultados/latencia.png).

## División ACID vs BASE

| Propiedad | ACID (PostgreSQL) | BASE (MongoDB) | Evidencia aquí |
|---|---|---|---|
| Consistencia | Fuerte e inmediata | Eventual | La identidad vive solo en PostgreSQL |
| Disponibilidad | Se prioriza la consistencia | Alta, responde siempre | La ingesta masiva va a MongoDB |
| Esquema | Rígido (`ALTER TABLE`) | Flexible | Q4: 247.62 ms frente a 0.84 ms |
| Uso típico | Sistema de registro | Sistema de interacción (telemetría) | Datos maestros frente a eventos |

Q3 muestra el costo de la arquitectura híbrida: para obtener el nombre del paciente hay que consultar los dos motores (agregación en MongoDB y búsqueda por `id_paciente` en PostgreSQL), y el tiempo se acerca al del JOIN relacional.

## Limitaciones

- PostgreSQL está en Supabase (nube) y MongoDB en [LOCAL o ATLAS: completar], por lo que la latencia de PostgreSQL incluye red. Para una comparación estricta, usar Atlas o declarar esta diferencia.
- Una sola corrida por operación (mediana de 20 ejecuciones; 5 en Q4). Los valores varían con la red y la carga.
- MongoDB no impone integridad referencial: `scripts/verificacion.py` comprueba que los ids de Supabase referenciados existan.

## Uso de IA

Herramienta: Claude. El diseño se revisó críticamente y se corrigió manualmente. Registro en [`ia/`](ia/).

| Problema detectado | Corrección |
|---|---|
| Conexión directa a Supabase falló (IPv6) | Usar el Session pooler |
| `GRANT` a roles inexistentes detuvo el script SQL | Bloque `DO $$` que otorga permisos solo si el rol existe |
| `&&` no funciona en PowerShell 5 | Encadenar con `;` |

## Integrantes

Santiago Padierna Suarez