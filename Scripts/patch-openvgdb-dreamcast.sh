#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  patch-openvgdb-dreamcast.sh [--db PATH] [--roms-csv PATH] [--covers-csv PATH]

Options:
  --db PATH         Path to openvgdb sqlite file.
                    Default: OpenEmu/Other Assets/openvgdb-custom.sqlite
  --roms-csv PATH   Optional CSV to import Dreamcast ROM match data.
  --covers-csv PATH Optional CSV to import/patch Dreamcast cover metadata.
  --help            Show this message.

CSV format: ROMs (--roms-csv)
  rom_hash_md5,rom_hash_crc,rom_hash_sha1,rom_size,rom_file_name,rom_extensionless_file_name,rom_parent,rom_serial,rom_header,rom_language,region_name,rom_dump_source

CSV format: Covers (--covers-csv)
  match_type,match_value,release_title,cover_front_url,region_name,description,developer,publisher,genre,release_date,reference_url,cover_back_url,cover_disc_url

match_type values:
  md5 | crc | sha1 | serial | header | filename
EOF
}

DB="OpenEmu/Other Assets/openvgdb-custom.sqlite"
ROMS_CSV=""
COVERS_CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      DB="$2"
      shift 2
      ;;
    --roms-csv)
      ROMS_CSV="$2"
      shift 2
      ;;
    --covers-csv)
      COVERS_CSV="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required but not found in PATH." >&2
  exit 1
fi

if [[ ! -f "$DB" ]]; then
  echo "Database not found: $DB" >&2
  exit 1
fi

if [[ -n "$ROMS_CSV" && ! -f "$ROMS_CSV" ]]; then
  echo "ROM CSV not found: $ROMS_CSV" >&2
  exit 1
fi

if [[ -n "$COVERS_CSV" && ! -f "$COVERS_CSV" ]]; then
  echo "Cover CSV not found: $COVERS_CSV" >&2
  exit 1
fi

SQLITE=(sqlite3 "$DB")

echo "Patching Dreamcast system mapping in: $DB"

"${SQLITE[@]}" <<'SQL'
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;

INSERT INTO SYSTEMS (
  systemName,
  systemShortName,
  systemHeaderSizeBytes,
  systemHashless,
  systemHeader,
  systemSerial,
  systemOEID
)
SELECT
  'Sega Dreamcast',
  'Dreamcast',
  0,
  0,
  0,
  '1',
  'openemu.system.dc'
WHERE NOT EXISTS (
  SELECT 1 FROM SYSTEMS WHERE lower(systemOEID) = 'openemu.system.dc'
);

-- Keep metadata up to date if row already exists.
UPDATE SYSTEMS
SET
  systemName = 'Sega Dreamcast',
  systemShortName = 'Dreamcast',
  systemHeaderSizeBytes = 0,
  systemHashless = 0,
  systemHeader = 0,
  systemSerial = '1'
WHERE lower(systemOEID) = 'openemu.system.dc';

COMMIT;
SQL

if [[ -n "$ROMS_CSV" ]]; then
  echo "Importing ROM metadata from: $ROMS_CSV"

  "${SQLITE[@]}" <<'SQL'
DROP TABLE IF EXISTS _dc_roms_import;
CREATE TABLE _dc_roms_import (
  rom_hash_md5 TEXT,
  rom_hash_crc TEXT,
  rom_hash_sha1 TEXT,
  rom_size TEXT,
  rom_file_name TEXT,
  rom_extensionless_file_name TEXT,
  rom_parent TEXT,
  rom_serial TEXT,
  rom_header TEXT,
  rom_language TEXT,
  region_name TEXT,
  rom_dump_source TEXT
);
SQL

  sqlite3 "$DB" ".mode csv" ".import '$ROMS_CSV' _dc_roms_import"

  "${SQLITE[@]}" <<'SQL'
BEGIN IMMEDIATE;

DELETE FROM _dc_roms_import
WHERE lower(trim(rom_hash_md5)) = 'rom_hash_md5';

INSERT INTO REGIONS (regionName)
SELECT DISTINCT trim(region_name)
FROM _dc_roms_import
WHERE trim(coalesce(region_name, '')) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM REGIONS r WHERE lower(r.regionName) = lower(trim(_dc_roms_import.region_name))
  );

WITH dc AS (
  SELECT systemID FROM SYSTEMS WHERE lower(systemOEID) = 'openemu.system.dc' LIMIT 1
), normalized AS (
  SELECT
    nullif(trim(rom_hash_md5), '')  AS rom_hash_md5,
    nullif(trim(rom_hash_crc), '')  AS rom_hash_crc,
    nullif(trim(rom_hash_sha1), '') AS rom_hash_sha1,
    CAST(nullif(trim(rom_size), '') AS INTEGER) AS rom_size,
    nullif(trim(rom_file_name), '') AS rom_file_name,
    nullif(trim(rom_extensionless_file_name), '') AS rom_extensionless_file_name,
    nullif(trim(rom_parent), '') AS rom_parent,
    nullif(trim(rom_serial), '') AS rom_serial,
    nullif(trim(rom_header), '') AS rom_header,
    nullif(trim(rom_language), '') AS rom_language,
    nullif(trim(region_name), '') AS region_name,
    nullif(trim(rom_dump_source), '') AS rom_dump_source
  FROM _dc_roms_import
)
INSERT INTO ROMs (
  systemID,
  regionID,
  romHashCRC,
  romHashMD5,
  romHashSHA1,
  romSize,
  romFileName,
  romExtensionlessFileName,
  romParent,
  romSerial,
  romHeader,
  romLanguage,
  romDumpSource
)
SELECT
  (SELECT systemID FROM dc),
  (
    SELECT r.regionID
    FROM REGIONS r
    WHERE lower(r.regionName) = lower(n.region_name)
    LIMIT 1
  ),
  upper(n.rom_hash_crc),
  upper(n.rom_hash_md5),
  upper(n.rom_hash_sha1),
  n.rom_size,
  n.rom_file_name,
  n.rom_extensionless_file_name,
  n.rom_parent,
  upper(n.rom_serial),
  upper(n.rom_header),
  n.rom_language,
  n.rom_dump_source
FROM normalized n
WHERE NOT EXISTS (
  SELECT 1
  FROM ROMs r
  WHERE r.systemID = (SELECT systemID FROM dc)
    AND (
      (n.rom_hash_md5 IS NOT NULL AND lower(r.romHashMD5) = lower(n.rom_hash_md5)) OR
      (n.rom_hash_crc IS NOT NULL AND lower(r.romHashCRC) = lower(n.rom_hash_crc)) OR
      (n.rom_hash_sha1 IS NOT NULL AND lower(r.romHashSHA1) = lower(n.rom_hash_sha1)) OR
      (n.rom_serial IS NOT NULL AND lower(r.romSerial) = lower(n.rom_serial)) OR
      (n.rom_header IS NOT NULL AND lower(r.romHeader) = lower(n.rom_header)) OR
      (n.rom_extensionless_file_name IS NOT NULL AND lower(r.romExtensionlessFileName) = lower(n.rom_extensionless_file_name))
    )
);

COMMIT;
SQL
fi

if [[ -n "$COVERS_CSV" ]]; then
  echo "Importing cover metadata from: $COVERS_CSV"

  "${SQLITE[@]}" <<'SQL'
DROP TABLE IF EXISTS _dc_covers_import;
CREATE TABLE _dc_covers_import (
  match_type TEXT,
  match_value TEXT,
  release_title TEXT,
  cover_front_url TEXT,
  region_name TEXT,
  description TEXT,
  developer TEXT,
  publisher TEXT,
  genre TEXT,
  release_date TEXT,
  reference_url TEXT,
  cover_back_url TEXT,
  cover_disc_url TEXT
);
SQL

  sqlite3 "$DB" ".mode csv" ".import '$COVERS_CSV' _dc_covers_import"

  "${SQLITE[@]}" <<'SQL'
BEGIN IMMEDIATE;

DELETE FROM _dc_covers_import
WHERE lower(trim(match_type)) = 'match_type';

INSERT INTO REGIONS (regionName)
SELECT DISTINCT trim(region_name)
FROM _dc_covers_import
WHERE trim(coalesce(region_name, '')) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM REGIONS r WHERE lower(r.regionName) = lower(trim(_dc_covers_import.region_name))
  );

DROP TABLE IF EXISTS _dc_cover_matches;
CREATE TEMP TABLE _dc_cover_matches AS
WITH dc AS (
  SELECT systemID FROM SYSTEMS WHERE lower(systemOEID) = 'openemu.system.dc' LIMIT 1
), src AS (
  SELECT
    lower(trim(match_type)) AS match_type,
    trim(match_value) AS match_value,
    nullif(trim(release_title), '') AS release_title,
    nullif(trim(cover_front_url), '') AS cover_front_url,
    nullif(trim(region_name), '') AS region_name,
    nullif(trim(description), '') AS description,
    nullif(trim(developer), '') AS developer,
    nullif(trim(publisher), '') AS publisher,
    nullif(trim(genre), '') AS genre,
    nullif(trim(release_date), '') AS release_date,
    nullif(trim(reference_url), '') AS reference_url,
    nullif(trim(cover_back_url), '') AS cover_back_url,
    nullif(trim(cover_disc_url), '') AS cover_disc_url
  FROM _dc_covers_import
)
SELECT
  r.romID AS romID,
  COALESCE(
    (SELECT rr.regionID FROM REGIONS rr WHERE lower(rr.regionName) = lower(src.region_name) LIMIT 1),
    r.regionID
  ) AS regionLocalizedID,
  COALESCE(src.release_title, r.romExtensionlessFileName, r.romFileName, 'Unknown Dreamcast Title') AS releaseTitleName,
  src.cover_front_url AS releaseCoverFront,
  src.cover_back_url AS releaseCoverBack,
  src.cover_disc_url AS releaseCoverDisc,
  src.description AS releaseDescription,
  src.developer AS releaseDeveloper,
  src.publisher AS releasePublisher,
  src.genre AS releaseGenre,
  src.release_date AS releaseDate,
  src.reference_url AS releaseReferenceURL
FROM src
JOIN ROMs r ON r.systemID = (SELECT systemID FROM dc)
WHERE (
  (src.match_type = 'md5'      AND lower(r.romHashMD5) = lower(src.match_value)) OR
  (src.match_type = 'crc'      AND lower(r.romHashCRC) = lower(src.match_value)) OR
  (src.match_type = 'sha1'     AND lower(r.romHashSHA1) = lower(src.match_value)) OR
  (src.match_type = 'serial'   AND lower(r.romSerial) = lower(src.match_value)) OR
  (src.match_type = 'header'   AND lower(r.romHeader) = lower(src.match_value)) OR
  (src.match_type = 'filename' AND lower(r.romExtensionlessFileName) = lower(src.match_value))
);

UPDATE RELEASES
SET
  releaseTitleName = COALESCE((SELECT m.releaseTitleName FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseTitleName),
  releaseCoverFront = COALESCE((SELECT m.releaseCoverFront FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseCoverFront),
  releaseCoverBack = COALESCE((SELECT m.releaseCoverBack FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseCoverBack),
  releaseCoverDisc = COALESCE((SELECT m.releaseCoverDisc FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseCoverDisc),
  releaseDescription = COALESCE((SELECT m.releaseDescription FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseDescription),
  releaseDeveloper = COALESCE((SELECT m.releaseDeveloper FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseDeveloper),
  releasePublisher = COALESCE((SELECT m.releasePublisher FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releasePublisher),
  releaseGenre = COALESCE((SELECT m.releaseGenre FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseGenre),
  releaseDate = COALESCE((SELECT m.releaseDate FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseDate),
  releaseReferenceURL = COALESCE((SELECT m.releaseReferenceURL FROM _dc_cover_matches m WHERE m.romID = RELEASES.romID AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1) LIMIT 1), releaseReferenceURL)
WHERE EXISTS (
  SELECT 1 FROM _dc_cover_matches m
  WHERE m.romID = RELEASES.romID
    AND COALESCE(m.regionLocalizedID, -1) = COALESCE(RELEASES.regionLocalizedID, -1)
);

INSERT INTO RELEASES (
  romID,
  releaseTitleName,
  regionLocalizedID,
  releaseCoverFront,
  releaseCoverBack,
  releaseCoverDisc,
  releaseDescription,
  releaseDeveloper,
  releasePublisher,
  releaseGenre,
  releaseDate,
  releaseReferenceURL
)
SELECT
  m.romID,
  m.releaseTitleName,
  m.regionLocalizedID,
  m.releaseCoverFront,
  m.releaseCoverBack,
  m.releaseCoverDisc,
  m.releaseDescription,
  m.releaseDeveloper,
  m.releasePublisher,
  m.releaseGenre,
  m.releaseDate,
  m.releaseReferenceURL
FROM _dc_cover_matches m
WHERE NOT EXISTS (
  SELECT 1 FROM RELEASES r
  WHERE r.romID = m.romID
    AND COALESCE(r.regionLocalizedID, -1) = COALESCE(m.regionLocalizedID, -1)
);

COMMIT;
SQL

  echo "Unmatched cover rows (no matching Dreamcast ROM in DB):"
  "${SQLITE[@]}" <<'SQL'
WITH dc AS (
  SELECT systemID FROM SYSTEMS WHERE lower(systemOEID) = 'openemu.system.dc' LIMIT 1
), src AS (
  SELECT lower(trim(match_type)) AS match_type, trim(match_value) AS match_value
  FROM _dc_covers_import
), matched AS (
  SELECT DISTINCT src.rowid AS rid
  FROM src
  JOIN _dc_covers_import orig ON orig.rowid = src.rowid
  JOIN ROMs r ON r.systemID = (SELECT systemID FROM dc)
  WHERE (
    (src.match_type = 'md5'      AND lower(r.romHashMD5) = lower(src.match_value)) OR
    (src.match_type = 'crc'      AND lower(r.romHashCRC) = lower(src.match_value)) OR
    (src.match_type = 'sha1'     AND lower(r.romHashSHA1) = lower(src.match_value)) OR
    (src.match_type = 'serial'   AND lower(r.romSerial) = lower(src.match_value)) OR
    (src.match_type = 'header'   AND lower(r.romHeader) = lower(src.match_value)) OR
    (src.match_type = 'filename' AND lower(r.romExtensionlessFileName) = lower(src.match_value))
  )
)
SELECT count(*)
FROM _dc_covers_import i
WHERE i.rowid NOT IN (SELECT rid FROM matched);
SQL
fi

echo "Done. Current Dreamcast system rows:"
"${SQLITE[@]}" "select systemID, systemOEID, systemName, systemSerial from SYSTEMS where lower(systemOEID) = 'openemu.system.dc';"

echo "Dreamcast ROM count in DB:"
"${SQLITE[@]}" "select count(*) from ROMs where systemID = (select systemID from SYSTEMS where lower(systemOEID) = 'openemu.system.dc' limit 1);"

echo "Dreamcast release count in DB:"
"${SQLITE[@]}" "select count(*) from RELEASES where romID in (select romID from ROMs where systemID = (select systemID from SYSTEMS where lower(systemOEID) = 'openemu.system.dc' limit 1));"
