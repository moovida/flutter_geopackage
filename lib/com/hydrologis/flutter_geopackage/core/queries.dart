const GPKG_CONTENTS = """
    CREATE TABLE IF NOT EXISTS gpkg_contents (
      table_name TEXT NOT NULL PRIMARY KEY,
      data_type TEXT NOT NULL,
      identifier TEXT UNIQUE,
      description TEXT DEFAULT '',
      last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
      min_x DOUBLE,
      min_y DOUBLE,
      max_x DOUBLE,
      max_y DOUBLE,
      srs_id INTEGER,
      CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    );
""";

const GPKG_DATA_COLUMN_CONSTRAINTS = """
    CREATE TABLE IF NOT EXISTS gpkg_data_column_constraints (
      constraint_name TEXT NOT NULL,
      constraint_type TEXT NOT NULL,
      value TEXT,
      min NUMERIC,
      min_is_inclusive BOOLEAN,
      max NUMERIC,
      max_is_inclusive BOOLEAN,
      description TEXT,
      CONSTRAINT gdcc_ntv UNIQUE (constraint_name, constraint_type, value)
    );
""";

const GPKG_DATA_COLUMNS = """
  CREATE TABLE IF NOT EXISTS gpkg_data_columns (
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    name TEXT,
    title TEXT,
    description TEXT,
    mime_type TEXT,
    constraint_name TEXT,
    CONSTRAINT pk_gdc PRIMARY KEY (table_name, column_name),
    CONSTRAINT fk_gdc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name)
  );
""";

const GPKG_EXTENSIONS = """
  CREATE TABLE IF NOT EXISTS gpkg_extensions (
    table_name TEXT,
    column_name TEXT,
    extension_name TEXT NOT NULL,
    definition TEXT NOT NULL,
    scope TEXT NOT NULL,
    CONSTRAINT ge_tce UNIQUE (table_name, column_name, extension_name)
  );
""";

const GPKG_GEOMETRY_COLUMNS = """
  CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    geometry_type_name TEXT NOT NULL,
    srs_id INTEGER NOT NULL,
    z TINYINT NOT NULL,
    m TINYINT NOT NULL,
    CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
    CONSTRAINT uk_gc_table_name UNIQUE (table_name),
    CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
    CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id)
  );
""";

const GPKG_METADATA_REFERENCE = """
  CREATE TABLE IF NOT EXISTS gpkg_metadata_reference (
    reference_scope TEXT NOT NULL,
    table_name TEXT,
    column_name TEXT,
    row_id_value INTEGER,
    timestamp DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    md_file_id INTEGER NOT NULL,
    md_parent_id INTEGER,
    CONSTRAINT crmr_mfi_fk FOREIGN KEY (md_file_id) REFERENCES gpkg_metadata(id),
    CONSTRAINT crmr_mpi_fk FOREIGN KEY (md_parent_id) REFERENCES gpkg_metadata(id)
  );
""";

const GPKG_METADATA = """
  CREATE TABLE IF NOT EXISTS gpkg_metadata (
    id INTEGER CONSTRAINT m_pk PRIMARY KEY ASC NOT NULL,
    md_scope TEXT NOT NULL DEFAULT 'dataset',
    md_standard_uri TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'text/xml',
    metadata TEXT NOT NULL DEFAULT ''
  );
""";

const GPKG_SPATIAL_REF_SYS = """
  CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
    srs_name TEXT NOT NULL,
    srs_id INTEGER NOT NULL PRIMARY KEY,
    organization TEXT NOT NULL,
    organization_coordsys_id INTEGER NOT NULL,
    definition  TEXT NOT NULL,
    description TEXT
  );
""";

const GPKG_TILE_MATRIX_SET = """
  CREATE TABLE IF NOT EXISTS gpkg_tile_matrix_set (
    table_name TEXT NOT NULL PRIMARY KEY,
    srs_id INTEGER NOT NULL,
    min_x DOUBLE NOT NULL,
    min_y DOUBLE NOT NULL,
    max_x DOUBLE NOT NULL,
    max_y DOUBLE NOT NULL,
    CONSTRAINT fk_gtms_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
    CONSTRAINT fk_gtms_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id)
  );
""";

const GPKG_TILE_MATRIX = """
  CREATE TABLE IF NOT EXISTS gpkg_tile_matrix (
    table_name TEXT NOT NULL,
    zoom_level INTEGER NOT NULL,
    matrix_width INTEGER NOT NULL,
    matrix_height INTEGER NOT NULL,
    tile_width INTEGER NOT NULL,
    tile_height INTEGER NOT NULL,
    pixel_x_size DOUBLE NOT NULL,
    pixel_y_size DOUBLE NOT NULL,
    CONSTRAINT pk_ttm PRIMARY KEY (table_name, zoom_level),
    CONSTRAINT fk_tmm_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name)
  );
""";

const GPKG_SPATIAL_INDEX = [
"""
    CREATE VIRTUAL TABLE rtree_TTT_CCC USING rtree(id, minx, maxx, miny, maxy);

    INSERT OR REPLACE INTO rtree_TTT_CCC
      SELECT III, ST_MinX(CCC), ST_MaxX(CCC), ST_MinY(CCC), ST_MaxY(CCC) FROM TTT
      WHERE NOT ST_IsEmpty(CCC);

    -- Conditions: Insertion of non-empty geometry
    --   Actions   : Insert record into rtree 
    CREATE TRIGGER rtree_TTT_CCC_insert AFTER INSERT ON TTT
      WHEN (new.CCC NOT NULL AND NOT ST_IsEmpty(NEW.CCC))
    BEGIN
      INSERT OR REPLACE INTO rtree_TTT_CCC VALUES (
        NEW.III,
        ST_MinX(NEW.CCC), ST_MaxX(NEW.CCC),
        ST_MinY(NEW.CCC), ST_MaxY(NEW.CCC)
      );
    END;

    -- Conditions: Update of geometry column to non-empty geometry
    --               No row ID change
    --   Actions   : Update record in rtree 
    CREATE TRIGGER rtree_TTT_CCC_update1 AFTER UPDATE OF CCC ON TTT
      WHEN OLD.III = NEW.III AND
          (NEW.CCC NOTNULL AND NOT ST_IsEmpty(NEW.CCC))
    BEGIN
      INSERT OR REPLACE INTO rtree_TTT_CCC VALUES (
        NEW.III,
        ST_MinX(NEW.CCC), ST_MaxX(NEW.CCC),
        ST_MinY(NEW.CCC), ST_MaxY(NEW.CCC)
      );
    END;

    -- Conditions: Update of geometry column to empty geometry
    --               No row ID change
    --   Actions   : Remove record from rtree 
    CREATE TRIGGER rtree_TTT_CCC_update2 AFTER UPDATE OF CCC ON TTT
      WHEN OLD.III = NEW.III AND
          (NEW.CCC ISNULL OR ST_IsEmpty(NEW.CCC))
    BEGIN
      DELETE FROM rtree_TTT_CCC WHERE id = OLD.III;
    END;

    -- Conditions: Update of any column
    --               Row ID change
    --              Non-empty geometry
    --   Actions   : Remove record from rtree for old III
    --               Insert record into rtree for new III
    CREATE TRIGGER rtree_TTT_CCC_update3 AFTER UPDATE OF CCC ON TTT
      WHEN OLD.III != NEW.III AND
          (NEW.CCC NOTNULL AND NOT ST_IsEmpty(NEW.CCC))
    BEGIN
      DELETE FROM rtree_TTT_CCC WHERE id = OLD.III;
      INSERT OR REPLACE INTO rtree_TTT_CCC VALUES (
        NEW.III,
        ST_MinX(NEW.CCC), ST_MaxX(NEW.CCC),
        ST_MinY(NEW.CCC), ST_MaxY(NEW.CCC)
      );
    END;

    -- Conditions: Update of any column
    --               Row ID change
    --               Empty geometry
    --   Actions   : Remove record from rtree for old and new III 
    CREATE TRIGGER rtree_TTT_CCC_update4 AFTER UPDATE ON TTT
      WHEN OLD.III != NEW.III AND
          (NEW.CCC ISNULL OR ST_IsEmpty(NEW.CCC))
    BEGIN
      DELETE FROM rtree_TTT_CCC WHERE id IN (OLD.III, NEW.III);
    END;

    -- Conditions: Row deleted
    --   Actions   : Remove record from rtree for old III 
    CREATE TRIGGER rtree_TTT_CCC_delete AFTER DELETE ON TTT
      WHEN old.CCC NOT NULL
    BEGIN
      DELETE FROM rtree_TTT_CCC WHERE id = OLD.III;
    END;

    -- Register the spatial index extension for this table/column
    INSERT INTO gpkg_extensions(table_name, column_name, extension_name, definition, scope) 
      VALUES('TTT', 'CCC', 'gpkg_rtree_index', 'GeoPackage 1.0 Specification Annex L', 'write-only');
"""
];