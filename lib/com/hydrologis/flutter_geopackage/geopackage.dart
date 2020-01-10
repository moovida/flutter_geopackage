part of flutter_geopackage;

/// A geopackage database.
///
/// @author Andrea Antonello (www.hydrologis.com)
class GeopackageDb {
  static const String HM_STYLES_TABLE = "hm_styles";

  static const String GEOPACKAGE_CONTENTS = "gpkg_contents";

  static const String GEOMETRY_COLUMNS = "gpkg_geometry_columns";

  static const String SPATIAL_REF_SYS = "gpkg_spatial_ref_sys";

  static const String RASTER_COLUMNS = "gpkg_data_columns";

  static const String TILE_MATRIX_METADATA = "gpkg_tile_matrix";

  static const String METADATA = "gpkg_metadata";

  static const String METADATA_REFERENCE = "gpkg_metadata_reference";

  static const String TILE_MATRIX_SET = "gpkg_tile_matrix_set";

  static const String DATA_COLUMN_CONSTRAINTS = "gpkg_data_column_constraints";

  static const String EXTENSIONS = "gpkg_extensions";

  static const String SPATIAL_INDEX = "gpkg_spatial_index";

  static const String DATE_FORMAT_STRING = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

  static const String COL_TILES_ZOOM_LEVEL = "zoom_level";
  static const String COL_TILES_TILE_COLUMN = "tile_column";
  static const String COL_TILES_TILE_ROW = "tile_row";
  static const String COL_TILES_TILE_DATA = "tile_data";
  static const String SELECTQUERY_PRE = "SELECT $COL_TILES_TILE_DATA from ";
  static const String SELECTQUERY_POST = " where $COL_TILES_ZOOM_LEVEL=? AND $COL_TILES_TILE_COLUMN=? AND $COL_TILES_TILE_ROW=?";

  /// An ISO8601 date formatter (yyyy-MM-dd HH:mm:ss).
  static final DateFormat ISO8601_TS_FORMATTER = DateFormat(DATE_FORMAT_STRING);

  static const int MERCATOR_SRID = 3857;
  static const int WGS84LL_SRID = 4326;

  /// If true, this forces mobile compatibility, which means that:
  ///
  ///  <ul>
  ///      <li>tiles: accept only srid 3857</li>
  ///      <li>vectors: accept only srid 4326</li>
  ///  </ul>
  ///
  /// Default on flutter is true. If you have a system that allows more
  /// than this, drop me an email :-)
  bool forceMobileCompatibility = true;

  // static final Pattern PROPERTY_PATTERN = Pattern.compile("\\$\\{(.+?)\\}");

  String _dbPath;
  SqliteDb _sqliteDb;

  bool _supportsRtree = false;
  bool _isGpgkInitialized = false;
  String _gpkgVersion;
  bool doRtreeTestCheck = true;

  GeopackageDb(this._dbPath) {
    _sqliteDb = new SqliteDb(_dbPath);
  }

  @override
  bool operator ==(other) {
    return other is GeopackageDb && _dbPath == other._dbPath;
  }

  @override
  int get hashCode => _dbPath.hashCode;

  openOrCreate({Function dbCreateFunction}) async {
    await _sqliteDb.openOrCreate();

    // 1196444487 (the 32-bit integer value of 0x47504B47 or GPKG in ASCII) for GPKG 1.2 and
    // greater
    // 1196437808 (the 32-bit integer value of 0x47503130 or GP10 in ASCII) for GPKG 1.0 or
    // 1.1
    List<Map<String, dynamic>> res = await _sqliteDb.query("PRAGMA application_id");
    int appId = res[0]['application_id'];
    if (0x47503130 == appId) {
      _gpkgVersion = "1.0/1.1";
    } else if (0x47504B47 == appId) {
      _gpkgVersion = "1.2";
    }

    _isGpgkInitialized = _gpkgVersion != null;

    if (doRtreeTestCheck) {
      try {
        String checkTable = "rtree_test_check";
        String checkRtree = "CREATE VIRTUAL TABLE " + checkTable + " USING rtree(id, minx, maxx, miny, maxy)";
        await _sqliteDb.execute(checkRtree);
        String drop = "DROP TABLE " + checkTable;
        await _sqliteDb.execute(drop);
        _supportsRtree = true;
      } catch (e) {
        _supportsRtree = false;
      }
    }

    if (!_isGpgkInitialized) {
      String sqlString = await rootBundle.loadString("assets/" + SPATIAL_REF_SYS + ".sql");
      sqlString += await rootBundle.loadString("assets/" + GEOMETRY_COLUMNS + ".sql");
      sqlString += await rootBundle.loadString("assets/" + GEOPACKAGE_CONTENTS + ".sql");
      sqlString += await rootBundle.loadString("assets/" + TILE_MATRIX_SET + ".sql");
      sqlString += await rootBundle.loadString("assets/" + TILE_MATRIX_METADATA + ".sql");
      sqlString += await rootBundle.loadString("assets/" + RASTER_COLUMNS + ".sql");
      sqlString += await rootBundle.loadString("assets/" + METADATA + ".sql");
      sqlString += await rootBundle.loadString("assets/" + METADATA_REFERENCE + ".sql");
      sqlString += await rootBundle.loadString("assets/" + DATA_COLUMN_CONSTRAINTS + ".sql");
      sqlString += await rootBundle.loadString("assets/" + EXTENSIONS + ".sql");

      addDefaultSpatialReferences();

      await _sqliteDb.transaction((tx) async {
        var split = sqlString.replaceAll("\n", "").trim().split(";");
        for (int i = 0; i < split.length; i++) {
          var sql = split[i].trim();
          if (sql.length > 0 && !sql.startsWith("--")) {
            await tx.execute(sql);
          }
        }
      });

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
  Future<List<FeatureEntry>> features() async {
    String compat = forceMobileCompatibility ? "and c.srs_id = $WGS84LL_SRID" : "";
    String sql = "SELECT a.*, b.column_name, b.geometry_type_name, b.z, b.m, c.organization_coordsys_id, c.definition" +
        " FROM $GEOPACKAGE_CONTENTS a, $GEOMETRY_COLUMNS b, $SPATIAL_REF_SYS c WHERE a.table_name = b.table_name" +
        " AND a.srs_id = c.srs_id AND a.data_type = ? $compat";
    var res = await _sqliteDb.query(sql, [DataType.Feature.value]);

    List<FeatureEntry> contents = [];
    res.forEach((map) {
      contents.add(createFeatureEntry(map));
    });

    return contents;
  }

  /// Looks up a feature entry by name.
  ///
  /// @param name THe name of the feature entry.
  /// @return The entry, or <code>null</code> if no such entry exists.
  Future<FeatureEntry> feature(String name) async {
    if (!await _sqliteDb.hasTable(GEOMETRY_COLUMNS)) {
      return null;
    }
    String compat = forceMobileCompatibility ? "and c.srs_id = $WGS84LL_SRID" : "";
    String sql = "SELECT a.*, b.column_name, b.geometry_type_name, b.m, b.z, c.organization_coordsys_id, c.definition" +
        " FROM $GEOPACKAGE_CONTENTS a, $GEOMETRY_COLUMNS b, $SPATIAL_REF_SYS c WHERE a.table_name = b.table_name " +
        " AND a.srs_id = c.srs_id $compat AND lower(a.table_name) = lower(?)" +
        " AND a.data_type = ?";

    var res = await _sqliteDb.query(sql, [name, DataType.Feature.value]);
    if (res.isNotEmpty) {
      return createFeatureEntry(res[0]);
    }
    return null;
  }

  /// Lists all the tile entries in the geopackage. */
  Future<List<TileEntry>> tiles() async {
    String compat = forceMobileCompatibility ? "and c.srs_id = $MERCATOR_SRID" : "";
    String sql = "SELECT a.*, c.organization_coordsys_id, c.definition" +
        " FROM $GEOPACKAGE_CONTENTS a, $SPATIAL_REF_SYS c" +
        " WHERE a.srs_id = c.srs_id $compat AND a.data_type = ?";

    var res = await _sqliteDb.query(sql, [DataType.Tile.value]);
    List<TileEntry> contents = [];
    for (int i = 0; i < res.length; i++) {
      var map = res[i];
      var tileEntry = await createTileEntry(map);
      contents.add(tileEntry);
    }
    return contents;
  }

  Future<TileEntry> createTileEntry(Map<String, dynamic> map) async {
    TileEntry e = new TileEntry();
    e.setIdentifier(map["identifier"]);
    e.setDescription(map["description"]);
    e.setTableName(map["table_name"]);
    int srid = (map["srs_id"] as num).toInt();
    e.setSrid(srid);
    e.setBounds(new Envelope(
      (map["min_x"] as num).toDouble(),
      (map["max_x"] as num).toDouble(),
      (map["min_y"] as num).toDouble(),
      (map["max_y"] as num).toDouble(),
    ));

    String sql =
        "SELECT *, exists(SELECT 1 FROM ${DbsUtilities.fixTableName(e.getTableName())} data where data.zoom_level = tileMatrix.zoom_level) as has_tiles" +
            " FROM $TILE_MATRIX_METADATA as tileMatrix WHERE table_name = ? ORDER BY zoom_level ASC";
    // load all the tile matrix entries (and join with the data table to see if a certain level
    // has tiles available, given the indexes in the data table, it should be real quick)
    var res = await _sqliteDb.query(sql, [e.getTableName()]);
    for (int i = 0; i < res.length; i++) {
      var resMap = res[i];
      var zl = (resMap["zoom_level"] as num).toInt();
      var mw = (resMap["matrix_width"] as num).toInt();
      var mh = (resMap["matrix_height"] as num).toInt();
      var tw = (resMap["tile_width"] as num).toInt();
      var th = (resMap["tile_height"] as num).toInt();
      var pxs = (resMap["pixel_x_size"] as num).toDouble();
      var pys = (resMap["pixel_y_size"] as num).toDouble();
      var has = resMap["has_tiles"];

      TileMatrix m = TileMatrix(zl, mw, mh, tw, th, pxs, pys)..setTiles(has == 1 ? true : false);

      e.getTileMatricies().add(m);
    }

    // use the tile matrix set bounds rather that gpkg_contents bounds
    // per spec, the tile matrix set bounds should be exact and used to calculate tile
    // coordinates and in contrast the gpkg_contents is "informational" only
    sql = "SELECT * FROM $TILE_MATRIX_SET a, $SPATIAL_REF_SYS b WHERE lower(a.table_name) = lower(?) AND a.srs_id = b.srs_id LIMIT 1";
    res = await _sqliteDb.query(sql, [e.getTableName()]);
    if (res.isNotEmpty) {
      var map = res.first;
      var srid = (map["organization_coordsys_id"] as num).toInt();
      e.setSrid(srid);
      e.setTileMatrixSetBounds(Envelope(
        (map["min_x"] as num).toDouble(),
        (map["max_x"] as num).toDouble(),
        (map["min_y"] as num).toDouble(),
        (map["max_y"] as num).toDouble(),
      ));
    }
    return e;
  }

  /// Looks up a tile entry by name.
  ///
  /// @param name THe name of the tile entry.
  /// @return The entry, or <code>null</code> if no such entry exists.
  Future<TileEntry> tile(String name) async {
    if (!await _sqliteDb.hasTable(GEOMETRY_COLUMNS)) {
      return null;
    }
    String compat = forceMobileCompatibility ? "and c.srs_id=$MERCATOR_SRID" : "";
    String sql = "SELECT a.*, c.organization_coordsys_id, c.definition" +
        " FROM $GEOPACKAGE_CONTENTS a, $SPATIAL_REF_SYS c" +
        " WHERE a.srs_id = c.srs_id $compat AND Lower(a.table_name) = Lower(?)" +
        " AND a.data_type = ?";

    var res = await _sqliteDb.query(sql, [name, DataType.Tile.value]);
    if (res.isNotEmpty) {
      return createTileEntry(res.first);
    }

    return null;
  }

  /// Verifies if a spatial index is present
  ///
  /// @param entry The feature entry.
  /// @return whether this feature entry has a spatial index available.
  /// @throws IOException
  Future<bool> hasSpatialIndex(String table) async {
    FeatureEntry featureEntry = await feature(table);

    String sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? ";
    var res = await _sqliteDb.query(sql, [getSpatialIndexName(featureEntry)]);
    return res.isNotEmpty;
  }

  String getSpatialIndexName(FeatureEntry feature) {
    return "rtree_" + feature.tableName + "_" + feature.geometryColumn;
  }

  FeatureEntry createFeatureEntry(Map<String, dynamic> rs) {
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
    e.setBounds(new Envelope(rs["min_x"], rs["max_x"], rs["min_y"], rs["max_y"]));

    e.setGeometryColumn(rs["column_name"]);
    e.setGeometryType(EGeometryType.forTypeName(rs["geometry_type_name"]));

    e.setZ(rs["z"] == 1 ? true : false);
    e.setM(rs["m"] == 1 ? true : false);
    return e;
  }

  void addDefaultSpatialReferences() {
    try {
      addCRS(-1, "Undefined cartesian SRS", "NONE", -1, "undefined", "undefined cartesian coordinate reference system");
      addCRS(0, "Undefined geographic SRS", "NONE", 0, "undefined", "undefined geographic coordinate reference system");
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
      throw new SQLException("Unable to add default spatial references: ${ex.toString()}");
    }
  }

  /**
   * Adds a crs to the geopackage, registering it in the spatial_ref_sys table.
   * @
   */
  void addCRSSimple(String auth, int srid, String wkt) {
    addCRS(srid, auth + ":$srid", auth, srid, wkt, auth + ":$srid");
  }

  Future<void> addCRS(int srid, String srsName, String organization, int organizationCoordSysId, String definition, String description) async {
    bool hasAlready = await hasCrs(srid);
    if (hasAlready) return;

    String sql = "INSERT INTO $SPATIAL_REF_SYS (srs_id, srs_name, organization, organization_coordsys_id, definition, description) VALUES (?,?,?,?,?,?)";

    int inserted = await _sqliteDb.insert(sql, [srid, srsName, organization, organizationCoordSysId, definition, description]);

    if (inserted != 1) {
      throw new IOException("Unable to insert CRS: $srid");
    }
  }

  Future<bool> hasCrs(int srid) async {
    String sqlPrep = "SELECT srs_id FROM $SPATIAL_REF_SYS WHERE srs_id = ?";
    List<Map<String, dynamic>> res = await _sqliteDb.query(sqlPrep, [srid]);
    return res.length > 0;
  }

  Future<void> close() async {
    await _sqliteDb?.close();
  }

  Future<Map<String, List<String>>> getTablesMap(bool doOrder) async {
    List<String> tableNames = await getTables(doOrder);
    var tablesMap = GeopackageTableNames.getTablesSorted(tableNames, doOrder);
    return tablesMap;
  }

  void createSpatialTable(String tableName, int tableSrid, String geometryFieldData, List<String> fieldData, List<String> foreignKeys, bool avoidIndex) {
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

    List<String> g = geometryFieldData.split("\\s+");
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

//  Future<QueryResult> getTableRecordsMapIn(String tableName, Envelope envelope, int limit, int reprojectSrid, String whereStr) async {
//    QueryResult queryResult = new QueryResult();
//    GeometryColumn gCol = null;
//    String geomColLower = null;
//    try {
//      gCol = await getGeometryColumnsForTable(tableName);
//      if (gCol != null)
//        geomColLower = gCol.geometryColumnName.toLowerCase();
//    }
//    catch
//    (e) {
//// ignore
//    }
//
//    List<List<String>> tableColumnsInfo = await getTableColumns(tableName);
//    int columnCount = tableColumnsInfo.length;
//
//    int index = 0;
//    List<String> items = [];
//    List<ResultSetToObjectFunction> funct = new ArrayList<>();
//    for (List < String > columnInfo : tableColumnsInfo) {
//      String columnName = columnInfo[0];
//      if (DbsUtilities.isReservedName(columnName)) {
//        columnName = DbsUtilities.fixReservedNameForQuery(columnName);
//      }
//
//      String columnTypeName = columnInfo[1];
//
//      queryResult.names.add(columnName);
//      queryResult.types.add(columnTypeName);
//
//      String isPk = columnInfo[2];
//      if (isPk.equals("1")) {
//        queryResult.pkIndex = index;
//      }
//      if (geomColLower != null && columnName.toLowerCase().equals(geomColLower)) {
//        queryResult.geometryIndex = index;
//
//        if (reprojectSrid == -1 || reprojectSrid == gCol.srid) {
//          items.add(geomColLower);
//        } else {
//          items.add("ST_Transform(" + geomColLower + "," + reprojectSrid + ") AS " + geomColLower);
//        }
//      } else {
//        items.add(columnName);
//      }
//      index++;
//
//      EDataType type = EDataType.getType4Name(columnTypeName);
//      switch (type) {
//        case TEXT:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getString(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case INTEGER:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getInt(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case BOOLEAN:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getInt(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case FLOAT:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getFloat(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case DOUBLE:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getDouble(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case LONG:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getLong(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case BLOB:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            return resultSet.getBytes(index);
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        case DATETIME:
//        case DATE:
//          {
//            funct.add(new ResultSetToObjectFunction(){
//
//            Object getObject( IHMResultSet resultSet, int index ) {
//            try {
//            String date = resultSet.getString(index);
//            return date;
//            } catch (Exception e) {
//            e.printStackTrace();
//            return null;
//            }
//            }
//            });
//            break;
//          }
//        default:
//          funct.add(null);
//          break;
//      }
//    }
//
//    String sql = "SELECT ";
//    sql += DbsUtilities.joinByComma(items);
//    sql += " FROM " + tableName;
//
//    List<String> whereStrings = new ArrayList<>();
//    if (envelope != null) {
//      double x1 = envelope.getMinX();
//      double y1 = envelope.getMinY();
//      double x2 = envelope.getMaxX();
//      double y2 = envelope.getMaxY();
//      String spatialindexBBoxWherePiece = getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
//      if (spatialindexBBoxWherePiece != null)
//        whereStrings.add(spatialindexBBoxWherePiece);
//    }
//    if (whereStr != null) {
//      whereStrings.add(whereStr);
//    }
//    if (whereStrings.size() > 0) {
//      sql += " WHERE "; //
//      sql += DbsUtilities.joinBySeparator(whereStrings, " AND ");
//    }
//
//    if (limit > 0) {
//      sql += " LIMIT " + limit;
//    }
//
//    IGeometryParser gp = getType().getGeometryParser();
//    String _sql = sql;
//    return execOnConnection(connection -> {
//    long start = System.currentTimeMillis();
//    try (IHMStatement stmt = connection.createStatement(); IHMResultSet rs = stmt.executeQuery(_sql)) {
//    while( rs.next() ) {
//    Object[] rec = new Object[columnCount];
//    for( int j = 1; j <= columnCount; j++ ) {
//    if (queryResult.geometryIndex == j - 1) {
//    Geometry geometry = gp.fromResultSet(rs, j);
//    if (geometry != null) {
//    rec[j - 1] = geometry;
//    }
//    } else {
//    ResultSetToObjectFunction function = funct.get(j - 1);
//    Object object = function.getObject(rs, j);
//    if (object instanceof Clob) {
//    object = rs.getString(j);
//    }
//    rec[j - 1] = object;
//    }
//    }
//    queryResult.data.add(rec);
//    }
//    long end = System.currentTimeMillis();
//    queryResult.queryTimeMillis = end - start;
//    return queryResult;
//    }
//    });
//  }

  Future<String> getSpatialindexBBoxWherePiece(String tableName, String alias, double x1, double y1, double x2, double y2) async {
    if (!_supportsRtree) return null;
    FeatureEntry featureItem = await feature(tableName);
    String spatial_index = getSpatialIndexName(featureItem);

    String pk = await getPrimaryKey(tableName);
    if (pk == null) {
// can't use spatial index
      return null;
    }

    String check = "($x1 <= maxx and $x2 >= minx and $y1 <= maxy and $y2 >= miny)";
// Make Sure the table name is escaped
    String sql = pk + " IN ( SELECT id FROM \"" + spatial_index + "\"  WHERE " + check + ")";
    return sql;
  }

  Future<String> getSpatialindexGeometryWherePiece(String tableName, String alias, Geometry geometry) async {
// this is not possible in gpkg, backing on envelope intersection
    Envelope env = geometry.getEnvelopeInternal();
    return await getSpatialindexBBoxWherePiece(tableName, alias, env.getMinX(), env.getMinY(), env.getMaxX(), env.getMaxY());
  }

  Future<GeometryColumn> getGeometryColumnsForTable(String tableName) async {
    FeatureEntry featureEntry = await feature(tableName);
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
    gc.isSpatialIndexEnabled = await hasSpatialIndex(tableName) ? 1 : 0;
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
  /// @return The list of geometries intersecting the envelope.
  /// @throws Exception
  Future<List<Geometry>> getGeometriesIn(String tableName, {Envelope envelope, List<String> prePostWhere}) async {
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

    String pk = await getPrimaryKey(tableName);
    GeometryColumn gCol = await getGeometryColumnsForTable(tableName);
    String sql = "SELECT " + pre + gCol.geometryColumnName + post + " as the_geom, $pk FROM " + DbsUtilities.fixTableName(tableName);

    if (envelope != null) {
      double x1 = envelope.getMinX();
      double y1 = envelope.getMinY();
      double x2 = envelope.getMaxX();
      double y2 = envelope.getMaxY();
      String spatialindexBBoxWherePiece = await getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
      if (spatialindexBBoxWherePiece != null) wheres.add(spatialindexBBoxWherePiece);
    }

    if (wheres.length > 0) {
      sql += " WHERE " + wheres.join(" AND ");
    }

    List<Geometry> geoms = [];
    var res = await _sqliteDb.query(sql);
    res.forEach((map) {
      var geomBytes = map["the_geom"];
      if (geomBytes != null) {
        Geometry geom = GeoPkgGeomReader(geomBytes).get();
        var pkValue = map[pk];
        geom.setUserData(pkValue);
        if (_supportsRtree || envelope == null) {
          geoms.add(geom);
        } else if (envelope != null && geom.getEnvelopeInternal().intersectsEnvelope(envelope)) {
          // if no spatial index is available, filter the geoms manually
          geoms.add(geom);
        }
      }
    });
    return geoms;
  }

  /// Get the geometries of a table intersecting a given geometry.
  ///
  /// @param tableName
  ///            the table name.
  /// @param envelope
  ///            the envelope to check.
  /// @param prePostWhere an optional set of 3 parameters. The parameters are: a
  ///          prefix wrapper for geom, a postfix for the same and a where string
  ///          to apply. They all need to be existing if the parameter is passed.
  /// @return The list of geometries intersecting the envelope.
  /// @throws Exception
  Future<List<Geometry>> getGeometriesIntersecting(String tableName, {Geometry geometry, List<String> prePostWhere}) async {
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

    GeometryColumn gCol = await getGeometryColumnsForTable(tableName);
    String sql = "SELECT " + pre + gCol.geometryColumnName + post + " as the_geom FROM " + DbsUtilities.fixTableName(tableName);

    if (supportsSpatialIndex && geometry != null) {
      var envelope = geometry.getEnvelopeInternal();
      double x1 = envelope.getMinX();
      double y1 = envelope.getMinY();
      double x2 = envelope.getMaxX();
      double y2 = envelope.getMaxY();
      String spatialindexBBoxWherePiece = await getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
      if (spatialindexBBoxWherePiece != null) wheres.add(spatialindexBBoxWherePiece);
    }

    if (wheres.length > 0) {
      sql += " WHERE " + wheres.join(" AND ");
    }

    List<Geometry> geoms = [];
    var res = await _sqliteDb.query(sql);
    res.forEach((map) {
      var geomBytes = map["the_geom"];
      if (geomBytes != null) {
        var geom = GeoPkgGeomReader(geomBytes).get();
        if (_supportsRtree || geometry == null) {
          geoms.add(geom);
        } else if (geometry != null && geom.getEnvelopeInternal().intersectsEnvelope(geometry.getEnvelopeInternal()) && geom.intersects(geometry)) {
          // if no spatial index is available, filter the geoms manually
          geoms.add(geom);
        }
      }
    });
    return geoms;
  }

  Future<List<String>> getTables(bool doOrder) async {
    return _sqliteDb.getTables(doOrder);
  }

  Future<bool> hasTable(String tableName) async {
    return await _sqliteDb.hasTable(tableName);
  }

  /// Get the table columns from a non spatial db.
  ///
  /// @param tableName the name of the table to get the columns for.
  /// @return the list of table column information. See {@link ADb#getTableColumns(String)}
  Future<List<List<String>>> getTableColumns(String tableName) async {
    List<List<String>> columnsInfo = [];

    String sql = "PRAGMA table_info(" + tableName + ")";
    var res = await _sqliteDb.query(sql);
    res.forEach((map) {
      var name = map["name"];
      var type = map["type"];
      var pk = map["pk"];

      columnsInfo.add([name, type, pk]);
    });
    return columnsInfo;
  }

  /// Get the primary key from a non spatial db.
  Future<String> getPrimaryKey(String tableName) async {
    String sql = "PRAGMA table_info(" + tableName + ")";
    var res = await _sqliteDb.query(sql);
    for (Map map in res) {
      var pk = map["pk"];
      if (pk == 1) {
        return map["name"];
      }
    }
    return null;
  }

  void addGeometryXYColumnAndIndex(String tableName, String geomColName, String geomType, String epsg) {
    createSpatialIndex(tableName, geomColName);
  }

  Future<QueryResult> getTableData(String tableName, [int limit]) async {
    QueryResult queryResult = new QueryResult();

    GeometryColumn geometryColumn = await getGeometryColumnsForTable(tableName);
    queryResult.geomName = geometryColumn.geometryColumnName;

    String sql = "select * from " + tableName;
    if (limit != null) {
      sql += "limit $limit";
    }
    List<Map<String, dynamic>> result = await _sqliteDb.query(sql);
    result.forEach((map) {
      Map<String, dynamic> newMap = {};
      map.forEach((k, v) {
        if (k == queryResult.geomName) {
          var geomBytes = map[queryResult.geomName];
          Geometry geom = GeoPkgGeomReader(geomBytes).get();
          queryResult.geoms.add(geom);
        } else {
          newMap[k] = v;
        }
      });
      queryResult.data.add(newMap);
    });

    return queryResult;
  }

  /**
   * Execute a query from raw sql and put the result in a csv file.
   *
   * @param sql
   *            the sql to run.
   * @param csvFile
   *            the output file.
   * @param doHeader
   *            if <code>true</code>, the header is written.
   * @param separator
   *            the separator (if null, ";" is used).
   * @
   */
//  void runRawSqlToCsv(String sql, File csvFile, bool doHeader, String separator) {
//    try
//    (BufferedWriter bw = new BufferedWriter(new FileWriter(csvFile))) {
//    SpatialiteWKBReader wkbReader = new SpatialiteWKBReader();
//    try (IHMStatement stmt = sqliteDb.getConnectionInternal().createStatement();
//    IHMResultSet rs = stmt.executeQuery(sql)) {
//    IHMResultSetMetaData rsmd = rs.getMetaData();
//    int columnCount = rsmd.getColumnCount();
//    int geometryIndex = -1;
//    for( int i = 1; i <= columnCount; i++ ) {
//    if (i > 1) {
//    bw.write(separator);
//    }
//    String columnTypeName = rsmd.getColumnTypeName(i);
//    String columnName = rsmd.getColumnName(i);
//    bw.write(columnName);
//    if (ESpatialiteGeometryType.isGeometryName(columnTypeName)) {
//    geometryIndex = i;
//    }
//    }
//    bw.write("\n");
//    while( rs.next() ) {
//    for( int j = 1; j <= columnCount; j++ ) {
//    if (j > 1) {
//    bw.write(separator);
//    }
//    byte[] geomBytes = null;
//    if (j == geometryIndex) {
//    geomBytes = rs.getBytes(j);
//    }
//    if (geomBytes != null) {
//    try {
//    Geometry geometry = wkbReader.read(geomBytes);
//    bw.write(geometry.toText());
//    } catch (Exception e) {
//// write it as it comes
//    Object object = rs.getObject(j);
//    if (object instanceof Clob) {
//    object = rs.getString(j);
//    }
//    if (object != null) {
//    bw.write(object.toString());
//    } else {
//    bw.write("");
//    }
//    }
//    } else {
//    Object object = rs.getObject(j);
//    if (object instanceof Clob) {
//    object = rs.getString(j);
//    }
//    if (object != null) {
//    bw.write(object.toString());
//    } else {
//    bw.write("");
//    }
//    }
//    }
//    bw.write("\n");
//    }
//    }
//    }
//  }

  /**
   * Create a spatial index
   *
   * @param e feature entry to create spatial index for
   */
  Future<void> createSpatialIndex(String tableName, String geometryName) async {
    String pk = await getPrimaryKey(tableName);
    if (pk == null) {
      throw new IOException("Spatial index only supported for primary key of single column.");
    }

    String sqlString = await rootBundle.loadString("assets/" + SPATIAL_INDEX + ".sql");

    sqlString = sqlString.replaceAll("\$\{t\}", tableName);
    sqlString = sqlString.replaceAll("\$\{c\}", geometryName);
    sqlString = sqlString.replaceAll("\$\{i\}", pk);

    await _sqliteDb.execute(sqlString);
  }

  Future<void> addGeoPackageContentsEntry(String tableName, int srid, String description, Envelope crsBounds) async {
    if (!await hasCrs(srid)) throw new IOException("The srid is not yet present in the package. Please add it before proceeding.");

//    final SimpleDateFormat DATE_FORMAT = new SimpleDateFormat(DATE_FORMAT_STRING);
//    DATE_FORMAT.setTimeZone(TimeZone.getTimeZone("GMT"));

    StringBuffer sb = new StringBuffer();
    StringBuffer vals = new StringBuffer();

    sb.write("INSERT INTO $GEOPACKAGE_CONTENTS (table_name, data_type, identifier");
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

    _sqliteDb.insert(sb.toString(), [tableName, DataType.Feature.value, tableName, description, minx, miny, maxx, maxy, srid]);
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
  Future<void> addGeometryColumnsEntry(String tableName, String geometryName, String geometryType, int srid, bool hasZ, bool hasM) async {
// geometryless tables should not be inserted into this table.
    String sql = "INSERT INTO $GEOMETRY_COLUMNS VALUES (?, ?, ?, ?, ?, ?);";

    _sqliteDb.insert(sql, [tableName, geometryName, geometryType, srid, hasZ ? 1 : 0, hasM ? 1 : 0]);
  }

  Future<BasicStyle> getBasicStyle(String tableName) async {
    await checkStyleTable();
    String sql = "select simplified from " + HM_STYLES_TABLE + " where lower(tablename)='" + tableName.toLowerCase() + "'";
    var res = await _sqliteDb.query(sql);
    BasicStyle style = BasicStyle();
    if (res.length == 1) {
      Map<String, dynamic> map = res[0];
      String jsonStyle = map['simplified'];
      style.setFromJson(jsonStyle);
    }
    return style;
  }

  Future<void> checkStyleTable() async {
    if (!await _sqliteDb.hasTable(HM_STYLES_TABLE)) {
      var createTablesQuery = '''
      CREATE TABLE $HM_STYLES_TABLE (  
        tablename TEXT NOT NULL,
        sld TEXT,
        simplified TEXT
      );
      CREATE INDEX ${HM_STYLES_TABLE}_tablename_idx ON $HM_STYLES_TABLE (tablename);
    ''';
      await _sqliteDb.transaction((tx) async {
        var split = createTablesQuery.replaceAll("\n", "").trim().split(";");
        for (int i = 0; i < split.length; i++) {
          var sql = split[i].trim();
          if (sql.length > 0 && !sql.startsWith("--")) {
            await tx.execute(sql);
          }
        }
      });
    }
  }

  /// Get a Tile's image bytes from the database for a given table.
  ///
  /// @param tableName the table name to get the image from.
  /// @param tx the x tile index.
  /// @param ty the y tile index, the osm way.
  /// @param zoom the zoom level.
  /// @return the tile image bytes.
  Future<List<int>> getTile(String tableName, int tx, int ty, int zoom) async {
//     if (tileRowType.equals("tms")) { // if it is not OSM way
    var tmsTileXY = osmTile2TmsTile(tx, ty, zoom);
    ty = tmsTileXY[1];
//     }
    String sql = SELECTQUERY_PRE + DbsUtilities.fixTableName(tableName) + SELECTQUERY_POST;
    var res = await _sqliteDb.query(sql, [zoom, tx, ty]);
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
  Future<List<int>> getTileZoomLevelsWithData(String tableName) async {
    String sql = "select distinct " + COL_TILES_ZOOM_LEVEL + " from " + DbsUtilities.fixTableName(tableName) + " order by " + COL_TILES_ZOOM_LEVEL;

    List<int> list = [];
    var res = await _sqliteDb.query(sql);
    res.forEach((map) {
      var zoomLevel = (map[COL_TILES_ZOOM_LEVEL] as num).toInt();
      list.add(zoomLevel);
    });
    return list;
  }

//
//    void deleteGeometryColumnsEntry( FeatureEntry e ) throws IOException {
//        String sql = format("DELETE FROM %s WHERE table_name = ?", GEOMETRY_COLUMNS);
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
//    /**
//     * Create a spatial index
//     *
//     * @param e feature entry to create spatial index for
//     */
//     void createSpatialIndex( FeatureEntry e ) throws IOException {
//        Map<String, String> properties = new HashMap<String, String>();
//
//        PrimaryKey pk = ((JDBCFeatureStore) (dataStore.getFeatureSource(e.getTableName()))).getPrimaryKey();
//        if (pk.getColumns().size() != 1) {
//            throw new IOException("Spatial index only supported for primary key of single column.");
//        }
//
//        properties.put("t", e.getTableName());
//        properties.put("c", e.getGeometryColumn());
//        properties.put("i", pk.getColumns().get(0).getName());
//
//        Connection cx;
//        try {
//            cx = connPool.getConnection();
//            try {
//                runScript(SPATIAL_INDEX + ".sql", cx, properties);
//            } finally {
//                cx.close();
//            }
//
//        } catch (SQLException ex) {
//            throw new IOException(ex);
//        }
//    }

//  static void createFunctions(Connection cx)
//
//  throws SQLException
//
//  {
//
//// minx
//  Function.create
//
//  (
//
//  cx
//
//  ,
//
//  "
//
//  ST_MinX
//
//  "
//
//  ,
//
//  new
//
//  GeometryFunction() {
//    Object execute(GeoPkgGeomReader reader)
//    throws IOException {
//      return reader.getEnvelope().getMinX();
//    }
//  }
//
//  );
//
//// maxx
//  Function.create
//
//  (
//
//  cx
//
//  ,
//
//  "
//
//  ST_MaxX
//
//  "
//
//  ,
//
//  new
//
//  GeometryFunction() {
//    Object execute(GeoPkgGeomReader reader)
//    throws IOException {
//      return reader.getEnvelope().getMaxX();
//    }
//  }
//
//  );
//
//// miny
//  Function.create
//
//  (
//
//  cx
//
//  ,
//
//  "
//
//  ST_MinY
//
//  "
//
//  ,
//
//  new
//
//  GeometryFunction() {
//    Object execute(GeoPkgGeomReader reader)
//    throws IOException {
//      return reader.getEnvelope().getMinY();
//    }
//  }
//
//  );
//
//// maxy
//  Function.create
//
//  (
//
//  cx
//
//  ,
//
//  "
//
//  ST_MaxY
//
//  "
//
//  ,
//
//  new
//
//  GeometryFunction() {
//    Object execute(GeoPkgGeomReader reader)
//    throws IOException {
//      return reader.getEnvelope().getMaxY();
//    }
//  }
//
//  );
//
//// empty
//  Function.create
//
//  (
//
//  cx
//
//  ,
//
//  "
//
//  ST_IsEmpty
//
//  "
//
//  ,
//
//  new
//
//  GeometryFunction() {
//    Object execute(GeoPkgGeomReader reader)
//    throws IOException {
//      return reader.getHeader().getFlags().isEmpty();
//    }
//  }
//
//  );
//}
}

class ConnectionsHandler {
  bool DO_RTREE_CHECK = false;
  bool FORCE_MOBILE_COMPATIBILITY = true;

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
  Future<GeopackageDb> open(String path, {String tableName}) async {
    GeopackageDb db = _connectionsMap[path];
    if (db == null) {
      db = GeopackageDb(path);
      db.doRtreeTestCheck = DO_RTREE_CHECK;
      db.forceMobileCompatibility = FORCE_MOBILE_COMPATIBILITY;
      await db.openOrCreate();

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
  Future<void> close(String path, {String tableName}) async {
    var tableNamesList = _tableNamesMap[path];
    if (tableName != null && tableNamesList.contains(tableName)) {
      tableNamesList.remove(tableName);
    }
    if (tableNamesList.length == 0) {
      // ok to close db and remove the connection
      _tableNamesMap.remove(path);
      GeopackageDb db = _connectionsMap.remove(path);
      await db?.close();
    }
  }

  Future<void> closeAll() async {
    _tableNamesMap.clear();
    Iterable<GeopackageDb> values = _connectionsMap.values;
    await values.forEach((c) async {
      await c.close();
    });
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
