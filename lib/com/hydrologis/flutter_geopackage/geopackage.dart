part of flutter_geopackage;

/// A geopackage database.
///
/// @author Andrea Antonello (www.hydrologis.com)
class GeopackageDb {
  static const String HM_STYLES_TABLE = "hm_styles";

  static const String DATE_FORMAT_STRING = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

  static const String COL_TILES_ZOOM_LEVEL = "zoom_level";
  static const String COL_TILES_TILE_COLUMN = "tile_column";
  static const String COL_TILES_TILE_ROW = "tile_row";
  static const String COL_TILES_TILE_DATA = "tile_data";
  static const String SELECTQUERY_PRE = "SELECT $COL_TILES_TILE_DATA from ";
  static const String SELECTQUERY_POST =
      " where $COL_TILES_ZOOM_LEVEL=? AND $COL_TILES_TILE_COLUMN=? AND $COL_TILES_TILE_ROW=?";

  /// An ISO8601 date formatter (yyyy-MM-dd HH:mm:ss).
  static final DateFormat ISO8601_TS_FORMATTER = DateFormat(DATE_FORMAT_STRING);

  static const int MERCATOR_SRID = 3857;
  static const int WGS84LL_SRID = 4326;

  /// If true, this forces vector or raster mobile compatibility, which means that:
  ///
  ///  <ul>
  ///      <li>tiles: accept only srid 3857</li>
  ///      <li>vectors: accept only srid 4326</li>
  ///  </ul>
  ///
  /// Default on flutter is true. If you have a system that allows more
  /// than this, drop me an email :-)
  bool forceVectorMobileCompatibility =
      false; // with proj4dart this can be handled now, so default is false.
  bool forceRasterMobileCompatibility = true;

  // static final Pattern PROPERTY_PATTERN = Pattern.compile("\\$\\{(.+?)\\}");

  String _dbPath;
  SqliteDb _sqliteDb;

  bool _supportsRtree = false;
  bool _isGpgkInitialized = false;
  String _gpkgVersion;
  bool doRtreeTestCheck = true;

  GeopackageDb(this._dbPath) {
    _sqliteDb = SqliteDb(_dbPath);
  }

  GeopackageDb.memory() {
    _sqliteDb = SqliteDb.memory();
  }

  @override
  bool operator ==(other) {
    return other is GeopackageDb && _dbPath == other._dbPath;
  }

  @override
  int get hashCode => _dbPath.hashCode;

  openOrCreate({Function dbCreateFunction}) {
    _sqliteDb.open(dbCreateFunction: dbCreateFunction);

    // 1196444487 (the 32-bit integer value of 0x47504B47 or GPKG in ASCII) for GPKG 1.2 and
    // greater
    // 1196437808 (the 32-bit integer value of 0x47503130 or GP10 in ASCII) for GPKG 1.0 or
    // 1.1
    var res = _sqliteDb.select("PRAGMA application_id");
    int appId = res.first['application_id'];
    if (0x47503130 == appId) {
      _gpkgVersion = "1.0/1.1";
    } else if (0x47504B47 == appId) {
      _gpkgVersion = "1.2";
    }

    _isGpgkInitialized = _gpkgVersion != null;

    createFunctions();

    if (doRtreeTestCheck) {
      try {
        String checkTable = "rtree_test_check";
        String checkRtree = "CREATE VIRTUAL TABLE " +
            checkTable +
            " USING rtree(id, minx, maxx, miny, maxy)";
        _sqliteDb.execute(checkRtree);
        String drop = "DROP TABLE " + checkTable;
        _sqliteDb.execute(drop);
        _supportsRtree = true;
      } catch (e) {
        _supportsRtree = false;
      }
    }

    if (!_isGpgkInitialized) {
      _sqliteDb.transaction((_db) {
        _db.execute(GPKG_SPATIAL_REF_SYS);
        _db.execute(GPKG_GEOMETRY_COLUMNS);
        _db.execute(GPKG_CONTENTS);
        _db.execute(GPKG_TILE_MATRIX_SET);
        _db.execute(GPKG_TILE_MATRIX);
        _db.execute(GPKG_DATA_COLUMNS);
        _db.execute(GPKG_METADATA);
        _db.execute(GPKG_METADATA_REFERENCE);
        _db.execute(GPKG_DATA_COLUMN_CONSTRAINTS);
        _db.execute(GPKG_EXTENSIONS);
      });

      // var lines = sqlString.split("\n");
      // lines.removeWhere((line) => line.trim().startsWith("--"));
      // sqlString = lines.join(" ");
      // var split = sqlString.trim().split(";");
      // for (int i = 0; i < split.length; i++) {
      //   var sql = split[i].trim();
      //   if (sql.length > 0 && !sql.startsWith("--")) {
      //     print(sql);
      //     _sqliteDb.execute(sql);
      //   }
      // }

      addDefaultSpatialReferences();

      _sqliteDb.execute("PRAGMA application_id = 0x47503130;");
      _gpkgVersion = "1.0/1.1";
    }
  }

  bool isOpen() {
    return _sqliteDb != null && _sqliteDb.isOpen();
  }

  bool get supportsSpatialIndex => _supportsRtree;

  String get version => _gpkgVersion;

  /// Lists all the feature entries in the geopackage. */
  List<FeatureEntry> features() {
    String compat =
        forceVectorMobileCompatibility ? "and c.srs_id = $WGS84LL_SRID" : "";
    String sql = """
        SELECT a.*, b.column_name, b.geometry_type_name, b.z, b.m, c.organization_coordsys_id, c.definition
        FROM $TABLE_GEOPACKAGE_CONTENTS a, $TABLE_GEOMETRY_COLUMNS b, $TABLE_SPATIAL_REF_SYS c WHERE a.table_name = b.table_name
        AND a.srs_id = c.srs_id AND a.data_type = ? $compat
        """
        .trim();
    var res = _sqliteDb.select(sql, [DataType.Feature.value]);

    List<FeatureEntry> contents = [];
    res.forEach((row) {
      contents.add(createFeatureEntry(row));
    });

    return contents;
  }

  /// Looks up a feature entry by name.
  ///
  /// @param name THe name of the feature entry.
  /// @return The entry, or <code>null</code> if no such entry exists.
  FeatureEntry feature(String name) {
    if (!_sqliteDb.hasTable(TABLE_GEOMETRY_COLUMNS)) {
      return null;
    }
    String compat =
        forceVectorMobileCompatibility ? "and c.srs_id = $WGS84LL_SRID" : "";
    String sql = """
        SELECT a.*, b.column_name, b.geometry_type_name, b.m, b.z, c.organization_coordsys_id, c.definition
        FROM $TABLE_GEOPACKAGE_CONTENTS a, $TABLE_GEOMETRY_COLUMNS b, $TABLE_SPATIAL_REF_SYS c WHERE a.table_name = b.table_name
        AND a.srs_id = c.srs_id $compat AND lower(a.table_name) = lower(?)
        AND a.data_type = ?
        """;

    var res = _sqliteDb.select(sql, [name, DataType.Feature.value]);
    if (res.isNotEmpty) {
      return createFeatureEntry(res.first);
    }
    return null;
  }

  /// Lists all the tile entries in the geopackage. */
  List<TileEntry> tiles() {
    String compat =
        forceRasterMobileCompatibility ? "and c.srs_id = $MERCATOR_SRID" : "";
    var sql = """
    SELECT a.*, c.organization_coordsys_id, c.definition
    FROM $TABLE_TILE_MATRIX_SET a, $TABLE_SPATIAL_REF_SYS c
    WHERE a.srs_id = c.srs_id $compat
    """;

    var res = _sqliteDb.select(sql);
    List<TileEntry> contents = [];
    res.forEach((row) {
      var tableName = row["table_name"];
      var cSql = """
        SELECT  min_x, max_x,max_y,min_y,srs_id
        FROM gpkg_contents
        where  table_name=?
      """;
      var cRes = _sqliteDb.select(cSql, [tableName]);
      var cRow = cRes.first;

      var tileEntry = createTileEntry(row, cRow);

      contents.add(tileEntry);
    });
    return contents;
  }

  TileEntry createTileEntry(dynamic row, dynamic cRow) {
    TileEntry e = new TileEntry();
    e.setIdentifier(row["identifier"]);
    e.setDescription(row["description"]);
    e.setTableName(row["table_name"]);
    int srid = (row["srs_id"] as num).toInt();
    e.setSrid(srid);
    var matrixSetEnvelope = new Envelope(
      (row["min_x"] as num).toDouble(),
      (row["max_x"] as num).toDouble(),
      (row["min_y"] as num).toDouble(),
      (row["max_y"] as num).toDouble(),
    );

    e.setTileMatrixSetBounds(matrixSetEnvelope);

    int cSrid = (cRow["srs_id"] as num).toInt();
    var bounds = new Envelope(
      (cRow["min_x"] as num).toDouble(),
      (cRow["max_x"] as num).toDouble(),
      (cRow["min_y"] as num).toDouble(),
      (cRow["max_y"] as num).toDouble(),
    );
    if (cSrid != srid) {
      // need to reproject
      bounds = Proj.transformEnvelope(PROJ.Projection("EPSG:$cSrid"),
          PROJ.Projection("EPSG:$srid"), bounds);
    }
    e.setBounds(bounds);

    String sql = """
        SELECT *, exists(
            SELECT 1 FROM ${DbsUtilities.fixTableName(e.getTableName())} data 
            where data.zoom_level = tileMatrix.zoom_level
        ) as has_tiles
        FROM $TABLE_TILE_MATRIX_METADATA as tileMatrix 
        WHERE table_name = ? 
        ORDER BY zoom_level ASC
        """;
    // load all the tile matrix entries (and join with the data table to see if a certain level
    // has tiles available, given the indexes in the data table, it should be real quick)
    var res = _sqliteDb.select(sql, [e.getTableName()]);
    res.forEach((resRow) {
      var zl = (resRow["zoom_level"] as num).toInt();
      var mw = (resRow["matrix_width"] as num).toInt();
      var mh = (resRow["matrix_height"] as num).toInt();
      var tw = (resRow["tile_width"] as num).toInt();
      var th = (resRow["tile_height"] as num).toInt();
      var pxs = (resRow["pixel_x_size"] as num).toDouble();
      var pys = (resRow["pixel_y_size"] as num).toDouble();
      var has = resRow["has_tiles"];

      TileMatrix m = TileMatrix(zl, mw, mh, tw, th, pxs, pys)
        ..setTiles(has == 1 ? true : false);

      e.getTileMatricies().add(m);
    });

    return e;
  }

  /// Looks up a tile entry by name.
  ///
  /// @param name THe name of the tile entry.
  /// @return The entry, or <code>null</code> if no such entry exists.
  TileEntry tile(String name) {
    if (!_sqliteDb.hasTable(TABLE_GEOMETRY_COLUMNS)) {
      return null;
    }
    String compat =
        forceRasterMobileCompatibility ? "and c.srs_id=$MERCATOR_SRID" : "";
    String sql = """
      SELECT a.*, c.organization_coordsys_id, c.definition
      FROM $TABLE_TILE_MATRIX_SET a, $TABLE_SPATIAL_REF_SYS c
      WHERE a.srs_id = c.srs_id $compat AND Lower(a.table_name) = Lower(?)
      """;

    var res = _sqliteDb.select(sql, [name]);
    if (res.isNotEmpty) {
      var cSql = """
        SELECT  min_x, max_x,max_y,min_y,srs_id
        FROM gpkg_contents
        where  table_name=?
      """;
      var cRes = _sqliteDb.select(cSql, [name]);
      return createTileEntry(res.first, cRes.first);
    }

    return null;
  }

  /// Verifies if a spatial index is present
  ///
  /// @param entry The feature entry.
  /// @return whether this feature entry has a spatial index available.
  /// @throws IOException
  bool hasSpatialIndex(String table) {
    if (!_supportsRtree) {
      return false;
    }
    FeatureEntry featureEntry = feature(table);

    String sql =
        "SELECT name FROM sqlite_master WHERE type='table' AND name=? ";
    var res = _sqliteDb.select(sql, [getSpatialIndexName(featureEntry)]);
    return res.isNotEmpty;
  }

  String getSpatialIndexName(FeatureEntry feature) {
    return "rtree_" + feature.tableName + "_" + feature.geometryColumn;
  }

  FeatureEntry createFeatureEntry(dynamic rs) {
    FeatureEntry e = new FeatureEntry();
    e.setIdentifier(rs["identifier"]);
    e.setDescription(rs["description"]);
    e.setTableName(rs["table_name"]);
//    try {
//      ISO8601_TS_FORMATTER.setTimeZone(TimeZone.getTimeZone("GMT"));
//      e.setLastChange(ISO8601_TS_FORMATTER.parse(rs.getString("last_change")));
//    } catch (ex) {
//      throw new IOException(ex);
//    }

    int srid = rs["srs_id"];
    e.setSrid(srid);
    e.setBounds(
        new Envelope(rs["min_x"], rs["max_x"], rs["min_y"], rs["max_y"]));

    e.setGeometryColumn(rs["column_name"]);
    e.setGeometryType(EGeometryType.forTypeName(rs["geometry_type_name"]));

    e.setZ(rs["z"] == 1 ? true : false);
    e.setM(rs["m"] == 1 ? true : false);
    return e;
  }

  void addDefaultSpatialReferences() {
    try {
      addCRS(-1, "Undefined cartesian SRS", "NONE", -1, "undefined",
          "undefined cartesian coordinate reference system");
      addCRS(0, "Undefined geographic SRS", "NONE", 0, "undefined",
          "undefined geographic coordinate reference system");
      addCRS(
          4326,
          "WGS 84 geodetic",
          "EPSG",
          4326,
          "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\"," +
              "6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],AUTHORITY[\"EPSG\",\"6326\"]]," +
              "PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433," +
              "AUTHORITY[\"EPSG\",\"9122\"]],AUTHORITY[\"EPSG\",\"4326\"]]",
          "longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid");
      addCRS(
          3857,
          "WGS 84 Pseudo-Mercator",
          "EPSG",
          4326,
          "PROJCS[\"WGS 84 / Pseudo-Mercator\", \n" +
              "  GEOGCS[\"WGS 84\", \n" +
              "    DATUM[\"World Geodetic System 1984\", \n" +
              "      SPHEROID[\"WGS 84\", 6378137.0, 298.257223563, AUTHORITY[\"EPSG\",\"7030\"]], \n" +
              "      AUTHORITY[\"EPSG\",\"6326\"]], \n" +
              "    PRIMEM[\"Greenwich\", 0.0, AUTHORITY[\"EPSG\",\"8901\"]], \n" +
              "    UNIT[\"degree\", 0.017453292519943295], \n" +
              "    AXIS[\"Geodetic longitude\", EAST], \n" +
              "    AXIS[\"Geodetic latitude\", NORTH], \n" +
              "    AUTHORITY[\"EPSG\",\"4326\"]], \n" +
              "  PROJECTION[\"Popular Visualisation Pseudo Mercator\", AUTHORITY[\"EPSG\",\"1024\"]], \n" +
              "  PARAMETER[\"semi-minor axis\", 6378137.0], \n" +
              "  PARAMETER[\"Latitude of false origin\", 0.0], \n" +
              "  PARAMETER[\"Longitude of natural origin\", 0.0], \n" +
              "  PARAMETER[\"Scale factor at natural origin\", 1.0], \n" +
              "  PARAMETER[\"False easting\", 0.0], \n" +
              "  PARAMETER[\"False northing\", 0.0], \n" +
              "  UNIT[\"m\", 1.0], \n" +
              "  AXIS[\"Easting\", EAST], \n" +
              "  AXIS[\"Northing\", NORTH], \n" +
              "  AUTHORITY[\"EPSG\",\"3857\"]]",
          "WGS 84 Pseudo-Mercator, often referred to as Webmercator.");
    } catch (ex) {
      throw new SQLException(
          "Unable to add default spatial references: ${ex.toString()}");
    }
  }

  /// Adds a crs to the geopackage, registering it in the spatial_ref_sys table.
  void addCRSSimple(String auth, int srid, String wkt) {
    addCRS(srid, auth + ":$srid", auth, srid, wkt, auth + ":$srid");
  }

  void addCRS(int srid, String srsName, String organization,
      int organizationCoordSysId, String definition, String description) {
    bool hasAlready = hasCrs(srid);
    if (hasAlready) return;

    String sql =
        "INSERT INTO $TABLE_SPATIAL_REF_SYS (srs_id, srs_name, organization, organization_coordsys_id, definition, description) VALUES (?,?,?,?,?,?)";

    int insertedCount = _sqliteDb.execute(sql, arguments: [
      srid,
      srsName,
      organization,
      organizationCoordSysId,
      definition,
      description
    ]);

    if (insertedCount != 1) {
      throw new IOException("Unable to insert CRS: $srid");
    }
  }

  bool hasCrs(int srid) {
    String sqlPrep =
        "SELECT srs_id FROM $TABLE_SPATIAL_REF_SYS WHERE srs_id = ?";
    var res = _sqliteDb.select(sqlPrep, [srid]);
    return res.length > 0;
  }

  void close() {
    _sqliteDb?.close();
  }

  Map<String, List<String>> getTablesMap(bool doOrder) {
    List<String> tableNames = getTables(doOrder);
    var tablesMap = GeopackageTableNames.getTablesSorted(tableNames, doOrder);
    return tablesMap;
  }

  void createSpatialTable(
      String tableName,
      int tableSrid,
      String geometryFieldData,
      List<String> fieldData,
      List<String> foreignKeys,
      bool avoidIndex) {
    StringBuffer sb = new StringBuffer();
    sb.write("CREATE TABLE ");
    sb.write(tableName);
    sb.write("(");
    for (int i = 0; i < fieldData.length; i++) {
      if (i != 0) sb.write(",");
      sb.write(fieldData[i]);
    }
    sb.write(",");
    sb.write(geometryFieldData);
    if (foreignKeys != null) {
      for (int i = 0; i < foreignKeys.length; i++) {
        sb.write(",");
        sb.write(foreignKeys[i]);
      }
    }
    sb.write(")");

    _sqliteDb.execute(sb.toString());

    List<String> g = geometryFieldData.split(RegExp(r"\s+"));
    addGeoPackageContentsEntry(tableName, tableSrid, null, null);
    addGeometryColumnsEntry(tableName, g[0], g[1], tableSrid, false, false);

    if (!avoidIndex) {
      createSpatialIndex(tableName, g[0]);
    }
  }

  Envelope getTableBounds(String tableName) {
// TODO
    throw new RuntimeException("Not implemented yet...");
  }

  String getSpatialindexBBoxWherePiece(String tableName, String alias,
      double x1, double y1, double x2, double y2) {
    if (!_supportsRtree) return null;
    FeatureEntry featureItem = feature(tableName);
    String spatial_index = getSpatialIndexName(featureItem);

    String pk = _sqliteDb.getPrimaryKey(tableName);
    if (pk == null) {
// can't use spatial index
      return null;
    }

    String check =
        "($x1 <= maxx and $x2 >= minx and $y1 <= maxy and $y2 >= miny)";
// Make Sure the table name is escaped
    String sql = pk +
        " IN ( SELECT id FROM \"" +
        spatial_index +
        "\"  WHERE " +
        check +
        ")";
    return sql;
  }

  String getSpatialindexGeometryWherePiece(
      String tableName, String alias, Geometry geometry) {
// this is not possible in gpkg, backing on envelope intersection
    Envelope env = geometry.getEnvelopeInternal();
    return getSpatialindexBBoxWherePiece(tableName, alias, env.getMinX(),
        env.getMinY(), env.getMaxX(), env.getMaxY());
  }

  GeometryColumn getGeometryColumnsForTable(String tableName) {
    FeatureEntry featureEntry = feature(tableName);
    if (featureEntry == null) return null;
    GeometryColumn gc = new GeometryColumn();
    gc.tableName = tableName;
    gc.geometryColumnName = featureEntry.geometryColumn;
    gc.geometryType = featureEntry.geometryType;
    int dim = 2;
    if (featureEntry.z) dim++;
    if (featureEntry.m) dim++;
    gc.coordinatesDimension = dim;
    gc.srid = featureEntry.srid;
    gc.isSpatialIndexEnabled = hasSpatialIndex(tableName) ? 1 : 0;
    return gc;
  }

  /// Get the geometries of a table inside a given envelope.
  ///
  /// Note that the primary key value is put inside the geom's userdata.
  ///
  /// @param tableName
  ///            the table name.
  /// @param envelope
  ///            the envelope to check.
  /// @param prePostWhere an optional set of 3 parameters. The parameters are: a
  ///          prefix wrapper for geom, a postfix for the same and a where string
  ///          to apply. They all need to be existing if the parameter is passed.
  /// @param limit an optional limit to apply.
  /// @return The list of geometries intersecting the envelope.
  /// @throws Exception
  List<Geometry> getGeometriesIn(String tableName,
      {Envelope envelope,
      List<String> prePostWhere,
      int limit = -1,
      String userDataField}) {
    List<String> wheres = [];
    String pre = "";
    String post = "";
    String where = "";
    if (prePostWhere != null && prePostWhere.length == 3) {
      if (prePostWhere[0] != null) pre = prePostWhere[0];
      if (prePostWhere[1] != null) post = prePostWhere[1];
      if (prePostWhere[2] != null) {
        where = prePostWhere[2];
        wheres.add(where);
      }
    }

    String userDataSql = userDataField != null ? ", $userDataField " : "";

    String pk = _sqliteDb.getPrimaryKey(tableName);
    GeometryColumn gCol = getGeometryColumnsForTable(tableName);
    String sql = "SELECT " +
        pre +
        gCol.geometryColumnName +
        post +
        " as the_geom, $pk $userDataSql FROM " +
        DbsUtilities.fixTableName(tableName);

    if (envelope != null) {
      double x1 = envelope.getMinX();
      double y1 = envelope.getMinY();
      double x2 = envelope.getMaxX();
      double y2 = envelope.getMaxY();
      String spatialindexBBoxWherePiece =
          getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
      if (spatialindexBBoxWherePiece != null)
        wheres.add(spatialindexBBoxWherePiece);
    }

    if (wheres.length > 0) {
      sql += " WHERE " + wheres.join(" AND ");
    }

    if (limit > 0) {
      sql += " limit $limit";
    }

    List<Geometry> geoms = [];
    var res = _sqliteDb.select(sql);
    res.forEach((map) {
      var geomBytes = map.columnAt(0);
      if (geomBytes != null) {
        Geometry geom = GeoPkgGeomReader(geomBytes).get();
        var pkValue = map.columnAt(1);
        if (userDataField != null) {
          geom.setUserData(map.columnAt(2));
        } else {
          geom.setUserData(pkValue);
        }
        if (_supportsRtree || envelope == null) {
          geoms.add(geom);
        } else if (envelope != null &&
            geom.getEnvelopeInternal().intersectsEnvelope(envelope)) {
          // if no spatial index is available, filter the geoms manually
          // print(pkValue.toString() + ": ${geom.getEnvelopeInternal()}");
          geoms.add(geom);
        }
      }
    });
    return geoms;
  }

  /// Get the geometries of a [tableName] intersecting a given [geometry].
  ///
  /// Note that sqlite geopackage only supports RTree index, therefore
  /// the exact intersection is done after the [getGeometriesIn] call
  /// on the resulting geometries. This is NOT done on the db side.
  ///
  /// @return The list of geometries intersecting the geometry.
  List<Geometry> getGeometriesIntersecting(String tableName,
      {Geometry geometry,
      List<String> prePostWhere,
      int limit = -1,
      String userDataField}) {
    if (geometry == null) {
      return getGeometriesIn(tableName,
          prePostWhere: prePostWhere,
          limit: limit,
          userDataField: userDataField);
    } else {
      var geometriesList = getGeometriesIn(
        tableName,
        envelope: geometry.getEnvelopeInternal(),
        prePostWhere: prePostWhere,
        limit: limit,
      );
      geometriesList.removeWhere((geom) => !geom.intersects(geometry));
      return geometriesList;
    }
  }

  List<String> getTables(bool doOrder) {
    return _sqliteDb.getTables(doOrder: doOrder);
  }

  bool hasTable(String tableName) {
    return _sqliteDb.hasTable(tableName);
  }

  /// Get the [tableName] columns as array of name, type and isPrimaryKey.
  List<List<dynamic>> getTableColumns(String tableName) {
    return _sqliteDb.getTableColumns(tableName);
  }

  void addGeometryXYColumnAndIndex(
      String tableName, String geomColName, String geomType, String epsg) {
    createSpatialIndex(tableName, geomColName);
  }

  String getPrimaryKey(String tableName) {
    return _sqliteDb.getPrimaryKey(tableName);
  }

  QueryResult getTableData(String tableName,
      {Envelope envelope, Geometry geometry, int limit}) {
    QueryResult queryResult = new QueryResult();

    GeometryColumn geometryColumn = getGeometryColumnsForTable(tableName);
    queryResult.geomName = geometryColumn.geometryColumnName;

    String sql = "select * from " + tableName;

    if (envelope != null && geometry != null) {
      throw ArgumentError("Only one of envelope and geometry have to be set.");
    }

    if (envelope != null) {
      double x1 = envelope.getMinX();
      double y1 = envelope.getMinY();
      double x2 = envelope.getMaxX();
      double y2 = envelope.getMaxY();
      String spatialindexBBoxWherePiece =
          getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
      if (spatialindexBBoxWherePiece != null) {
        sql += " WHERE " + spatialindexBBoxWherePiece;
      }
    }
    if (geometry != null) {
      String spatialindexBBoxWherePiece =
          getSpatialindexGeometryWherePiece(tableName, null, geometry);
      if (spatialindexBBoxWherePiece != null) {
        sql += " WHERE " + spatialindexBBoxWherePiece;
      }
    }
    bool hasBoundsfilter = envelope != null || geometry != null;

    if (limit != null) {
      sql += "limit $limit";
    }
    var result = _sqliteDb.select(sql);
    result.forEach((map) {
      Map<String, dynamic> newMap = {};
      bool doAdd = true;
      var geomBytes = map[queryResult.geomName];
      if (geomBytes != null) {
        Geometry geom = GeoPkgGeomReader(geomBytes).get();
        if (_supportsRtree && geometry == null) {
          queryResult.geoms.add(geom);
        } else {
          // if no spatial index is available, filter the geoms manually
          if (!hasBoundsfilter) {
            // no filter, take them all
            queryResult.geoms.add(geom);
          } else if (envelope != null &&
              geom.getEnvelopeInternal().intersectsEnvelope(envelope)) {
            queryResult.geoms.add(geom);
          } else if (geometry != null &&
              geom
                  .getEnvelopeInternal()
                  .intersectsEnvelope(geometry.getEnvelopeInternal()) &&
              geom.intersects(geometry)) {
            queryResult.geoms.add(geom);
          } else {
            doAdd = false;
          }
        }
      }
      if (doAdd) {
        map.forEach((k, v) {
          if (k != queryResult.geomName) {
            newMap[k] = v;
          }
        });
        queryResult.data.add(newMap);
      }
    });

    return queryResult;
  }

  /// Create a spatial index
  ///
  /// @param e feature entry to create spatial index for
  void createSpatialIndex(String tableName, String geometryName) {
    if (!_supportsRtree) {
      // if no rtree is supported, the spatial index can't work.
      return;
    }
    String pk = _sqliteDb.getPrimaryKey(tableName);
    if (pk == null) {
      throw new IOException(
          "Spatial index only supported for primary key of single column.");
    }

    var sqlList = GPKG_SPATIAL_INDEX;

    _sqliteDb.transaction((_db) {
      for (var sqlString in sqlList) {
        sqlString = sqlString.replaceAll("TTT", tableName);
        sqlString = sqlString.replaceAll("CCC", geometryName);
        sqlString = sqlString.replaceAll("III", pk);
        _sqliteDb.execute(sqlString);
      }
    });
  }

  void addGeoPackageContentsEntry(
      String tableName, int srid, String description, Envelope crsBounds) {
    if (!hasCrs(srid))
      throw new IOException(
          "The srid is not yet present in the package. Please add it before proceeding.");

//    final SimpleDateFormat DATE_FORMAT = new SimpleDateFormat(DATE_FORMAT_STRING);
//    DATE_FORMAT.setTimeZone(TimeZone.getTimeZone("GMT"));

    StringBuffer sb = new StringBuffer();
    StringBuffer vals = new StringBuffer();

    sb.write(
        "INSERT INTO $TABLE_GEOPACKAGE_CONTENTS (table_name, data_type, identifier");
    vals.write("VALUES (?,?,?");

    if (description == null) {
      description = "";
    }
    sb.write(", description");
    vals.write(",?");

    sb.write(", min_x, min_y, max_x, max_y");
    vals.write(",?,?,?,?");

    sb.write(", srs_id");
    vals.write(",?");
    sb.write(") ");
    vals.write(")");
    sb.write(vals.toString());

    double minx = 0;
    double miny = 0;
    double maxx = 0;
    double maxy = 0;
    if (crsBounds != null) {
      minx = crsBounds.getMinX();
      miny = crsBounds.getMinY();
      maxx = crsBounds.getMaxX();
      maxy = crsBounds.getMaxY();
    }

    _sqliteDb.execute(sb.toString(), arguments: [
      tableName,
      DataType.Feature.value,
      tableName,
      description,
      minx,
      miny,
      maxx,
      maxy,
      srid
    ]);
  }

//    void deleteGeoPackageContentsEntry( Entry e ) throws IOException {
//        String sql = format("DELETE FROM %s WHERE table_name = ?", GEOPACKAGE_CONTENTS);
//        try {
//            Connection cx = connPool.getConnection();
//            try {
//                PreparedStatement ps = prepare(cx, sql).set(e.getTableName()).log(Level.FINE).statement();
//                try {
//                    ps.execute();
//                } finally {
//                    close(ps);
//                }
//            } finally {
//                close(cx);
//            }
//        } catch (SQLException ex) {
//            throw new IOException(ex);
//        }
//    }
//
  void addGeometryColumnsEntry(String tableName, String geometryName,
      String geometryType, int srid, bool hasZ, bool hasM) {
// geometryless tables should not be inserted into this table.
    String sql =
        "INSERT INTO $TABLE_GEOMETRY_COLUMNS VALUES (?, ?, ?, ?, ?, ?);";

    _sqliteDb.execute(sql, arguments: [
      tableName,
      geometryName,
      geometryType,
      srid,
      hasZ ? 1 : 0,
      hasM ? 1 : 0
    ]);
  }

  /// Get the basic style for a table.
  ///
  /// This should not be used, since there is sld support. Use [getSld(tableName)].
  BasicStyle getBasicStyle(String tableName) {
    checkStyleTable();
    String sql = "select simplified from " +
        HM_STYLES_TABLE +
        " where lower(tablename)='" +
        tableName.toLowerCase() +
        "'";
    var res = _sqliteDb.select(sql);
    BasicStyle style = BasicStyle();
    if (res.length == 1) {
      var row = res.first;
      String jsonStyle = row['simplified'];
      style.setFromJson(jsonStyle);
    }
    return style;
  }

  /// Get the SLD xml for a given table.
  String getSld(String tableName) {
    checkStyleTable();
    String sql = "select sld from " +
        HM_STYLES_TABLE +
        " where lower(tablename)='" +
        tableName.toLowerCase() +
        "'";
    var res = _sqliteDb.select(sql);
    if (res.length == 1) {
      var row = res.first;
      String sldString = row['sld'];
      return sldString;
    }
    return null;
  }

  /// Update the sld string in the geopackage
  void updateSld(String tableName, String sldString) {
    checkStyleTable();
    String sql = """update $HM_STYLES_TABLE 
        set sld=? where lower(tablename)='${tableName.toLowerCase()}'
        """;
    var updated = _sqliteDb.execute(sql, arguments: [sldString]);
    if (updated == 0) {
      // need to insert
      String sql = """insert into $HM_STYLES_TABLE 
      (tablename, sld) values
        ('${tableName}', ?);
        """;
      _sqliteDb.execute(sql, arguments: [sldString]);
    }
  }

  void checkStyleTable() {
    if (!_sqliteDb.hasTable(HM_STYLES_TABLE)) {
      var createTablesQuery = '''
      CREATE TABLE $HM_STYLES_TABLE (  
        tablename TEXT NOT NULL,
        sld TEXT,
        simplified TEXT
      );
      CREATE UNIQUE INDEX ${HM_STYLES_TABLE}_tablename_idx ON $HM_STYLES_TABLE (tablename);
    ''';
      var split = createTablesQuery.replaceAll("\n", "").trim().split(";");
      for (int i = 0; i < split.length; i++) {
        var sql = split[i].trim();
        if (sql.length > 0 && !sql.startsWith("--")) {
          _sqliteDb.execute(sql);
        }
      }
    }
  }

  /// Get a Tile's image bytes from the database for a given table.
  ///
  /// @param tableName the table name to get the image from.
  /// @param tx the x tile index.
  /// @param ty the y tile index, the osm way.
  /// @param zoom the zoom level.
  /// @return the tile image bytes.
  List<int> getTile(String tableName, int tx, int ty, int zoom) {
//     if (tileRowType.equals("tms")) { // if it is not OSM way
    var tmsTileXY = osmTile2TmsTile(tx, ty, zoom);
    ty = tmsTileXY[1];
//     }
    String sql = SELECTQUERY_PRE +
        DbsUtilities.fixTableName(tableName) +
        SELECTQUERY_POST;
    var res = _sqliteDb.select(sql, [zoom, tx, ty]);
    if (res.isNotEmpty) {
      return res.first[COL_TILES_TILE_DATA];
    }
    return null;
  }

  List<int> getTileDirect(String tableName, int tx, int ty, int zoom) {
    String sql = SELECTQUERY_PRE +
        DbsUtilities.fixTableName(tableName) +
        SELECTQUERY_POST;
    var res = _sqliteDb.select(sql, [zoom, tx, ty]);
    if (res.isNotEmpty) {
      return res.first[COL_TILES_TILE_DATA];
    }
    return null;
  }

  /// Converts Osm slippy map tile coordinates to TMS Tile coordinates.
  ///
  /// @param tx   the x tile number.
  /// @param ty   the y tile number.
  /// @param zoom the current zoom level.
  /// @return the converted values.
  static List<int> osmTile2TmsTile(int tx, int ty, int zoom) {
    return [tx, (math.pow(2, zoom) - 1).round() - ty];
  }

  /// Get the list of zoomlevels that contain data.
  ///
  /// @param tableName the name of the table.
  /// @return the list of zoom levels.
  /// @throws Exception
  List<int> getTileZoomLevelsWithData(String tableName) {
    String sql = "select distinct " +
        COL_TILES_ZOOM_LEVEL +
        " from " +
        DbsUtilities.fixTableName(tableName) +
        " order by " +
        COL_TILES_ZOOM_LEVEL;

    List<int> list = [];
    var res = _sqliteDb.select(sql);
    res.forEach((map) {
      var zoomLevel = (map[COL_TILES_ZOOM_LEVEL] as num).toInt();
      list.add(zoomLevel);
    });
    return list;
  }

  /// Execute a insert, update or delete using [sql] in normal
  /// or prepared mode using [arguments].
  ///
  /// This returns the number of affected rows. Only if [getLastInsertId]
  /// is set to true, the id of the last inserted row is returned.
  int execute(String sql,
      {List<dynamic> arguments, bool getLastInsertId = false}) {
    return _sqliteDb.execute(sql,
        arguments: arguments, getLastInsertId: getLastInsertId);
  }

  /// Update a new record using a map and a where condition.
  ///
  /// This returns the number of rows affected.
  int updateMap(String table, Map<String, dynamic> values, String where) {
    return _sqliteDb.updateMap(table, values, where);
  }

  Iterable<dynamic> select(String sql) {
    return _sqliteDb.select(sql);
  }

  void createFunctions() {
    _sqliteDb.createFunction(
        functionName: 'ST_MinX',
        function: (args) {
          final value = args[0];
          if (value is List<int>) {
            var minX = GeoPkgGeomReader(value).getEnvelope().getMinX();
            return minX;
          } else {
            return null;
          }
        },
        argumentCount: 1,
        deterministic: false,
        directOnly: false);
    _sqliteDb.createFunction(
        functionName: 'ST_MaxX',
        function: (args) {
          final value = args[0];
          if (value is List<int>) {
            var maxX = GeoPkgGeomReader(value).getEnvelope().getMaxX();
            return maxX;
          } else {
            return null;
          }
        },
        argumentCount: 1,
        deterministic: false,
        directOnly: false);
    _sqliteDb.createFunction(
        functionName: 'ST_MinY',
        function: (args) {
          final value = args[0];
          if (value is List<int>) {
            var minY = GeoPkgGeomReader(value).getEnvelope().getMinY();
            return minY;
          } else {
            return null;
          }
        },
        argumentCount: 1,
        deterministic: false,
        directOnly: false);
    _sqliteDb.createFunction(
        functionName: 'ST_MaxY',
        function: (args) {
          final value = args[0];
          if (value is List<int>) {
            var maxY = GeoPkgGeomReader(value).getEnvelope().getMaxY();
            return maxY;
          } else {
            return null;
          }
        },
        argumentCount: 1,
        deterministic: false,
        directOnly: false);
    _sqliteDb.createFunction(
        functionName: 'ST_IsEmpty',
        function: (args) {
          final value = args[0];
          if (value is List<int>) {
            Geometry geom = GeoPkgGeomReader(value).get();
            return geom.isEmpty();
          } else {
            return null;
          }
        },
        argumentCount: 1,
        deterministic: false,
        directOnly: false);

    // moorDb.createFunction('ST_MinX', 1, Pointer.fromFunction(minxFunction),
    //     isDeterministic: true, directOnly: false);
    // moorDb.createFunction('ST_MaxX', 1, Pointer.fromFunction(maxxFunction),
    //     isDeterministic: true, directOnly: false);
    // moorDb.createFunction('ST_MinY', 1, Pointer.fromFunction(minyFunction),
    //     isDeterministic: true, directOnly: false);
    // moorDb.createFunction('ST_MaxY', 1, Pointer.fromFunction(maxyFunction),
    //     isDeterministic: true, directOnly: false);
    // moorDb.createFunction(
    //     'ST_IsEmpty', 1, Pointer.fromFunction(isEmptyFunction),
    //     isDeterministic: true, directOnly: false);
  }
}

class ConnectionsHandler {
  // bool doRtreeCheck = false;
  bool forceVectorMobileCompatibility = false;
  bool forceRasterMobileCompatibility = true;

  static final ConnectionsHandler _singleton = ConnectionsHandler._internal();

  factory ConnectionsHandler() {
    return _singleton;
  }

  ConnectionsHandler._internal();

  /// Map containing a mapping of db paths and db connections.
  Map<String, GeopackageDb> _connectionsMap = {};

  /// Map containing a mapping of db paths opened tables.
  ///
  /// The db can be closed only when all tables have been removed.
  Map<String, List<String>> _tableNamesMap = {};

  /// Open a new db or retrieve it from the cache.
  ///
  /// The [tableName] can be added to keep track of the tables that
  /// still need an open connection boudn to a given [path].
  GeopackageDb open(String path, {String tableName}) {
    GeopackageDb db = _connectionsMap[path];
    if (db == null) {
      db = GeopackageDb(path);
      // db.doRtreeTestCheck = doRtreeCheck;
      db.forceVectorMobileCompatibility = forceVectorMobileCompatibility;
      db.forceRasterMobileCompatibility = forceRasterMobileCompatibility;
      db.openOrCreate();

      _connectionsMap[path] = db;
    }
    var namesList = _tableNamesMap[path];
    if (namesList == null) {
      namesList = List<String>();
      _tableNamesMap[path] = namesList;
    }
    if (tableName != null && !namesList.contains(tableName)) {
      namesList.add(tableName);
    }
    return db;
  }

  /// Close an existing db connection, if all tables bound to it were released.
  void close(String path, {String tableName}) {
    var tableNamesList = _tableNamesMap[path];
    if (tableNamesList != null && tableNamesList.contains(tableName)) {
      tableNamesList.remove(tableName);
    }
    if (tableNamesList == null || tableNamesList.length == 0) {
      // ok to close db and remove the connection
      _tableNamesMap.remove(path);
      GeopackageDb db = _connectionsMap.remove(path);
      db?.close();
    }
  }

  void closeAll() {
    _tableNamesMap.clear();
    Iterable<GeopackageDb> values = _connectionsMap.values;
    for (GeopackageDb c in values) {
      c.close();
    }
  }

  List<String> getOpenDbReport() {
    List<String> msgs = [];
    if (_tableNamesMap.length > 0) {
      _tableNamesMap.forEach((p, n) {
        msgs.add("Database: $p");
        if (n != null && n.length > 0) {
          msgs.add("-> with tables: ${n.join("; ")}");
        }
      });
    } else {
      msgs.add("No database connection.");
    }
    return msgs;
  }
}
