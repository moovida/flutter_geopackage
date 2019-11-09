part of flutter_geopackage;


/**
 * A spatialite database.
 *
 * @author Andrea Antonello (www.hydrologis.com)
 */
class GeopackageDb {
  static final String GEOPACKAGE_CONTENTS = "gpkg_contents";

  static final String GEOMETRY_COLUMNS = "gpkg_geometry_columns";

  static final String SPATIAL_REF_SYS = "gpkg_spatial_ref_sys";

  static final String RASTER_COLUMNS = "gpkg_data_columns";

  static final String TILE_MATRIX_METADATA = "gpkg_tile_matrix";

  static final String METADATA = "gpkg_metadata";

  static final String METADATA_REFERENCE = "gpkg_metadata_reference";

  static final String TILE_MATRIX_SET = "gpkg_tile_matrix_set";

  static final String DATA_COLUMN_CONSTRAINTS = "gpkg_data_column_constraints";

  static final String EXTENSIONS = "gpkg_extensions";

  static final String SPATIAL_INDEX = "gpkg_spatial_index";

  static final String DATE_FORMAT_STRING = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

  /// An ISO8601 date formatter (yyyy-MM-dd HH:mm:ss).
  static final DateFormat ISO8601_TS_FORMATTER = DateFormat(DATE_FORMAT_STRING);

  // static final Pattern PROPERTY_PATTERN = Pattern.compile("\\$\\{(.+?)\\}");

  String _dbPath;
  SqliteDb sqliteDb;

  bool supportsRtree = true;
  bool isGpgkInitialized = false;
  String gpkgVersion;

  GeopackageDb(this._dbPath) {
    sqliteDb = new SqliteDb(_dbPath);
  }

  openOrCreate({Function dbCreateFunction}) async {
    await sqliteDb.openOrCreate(dbCreateFunction: initSpatialMetadata);

    // 1196444487 (the 32-bit integer value of 0x47504B47 or GPKG in ASCII) for GPKG 1.2 and
// greater
// 1196437808 (the 32-bit integer value of 0x47503130 or GP10 in ASCII) for GPKG 1.0 or
// 1.1
    List<Map<String, dynamic>> res = await sqliteDb.query("PRAGMA application_id");
    int appId = res[0]['application_id'];
    if (0x47503130 == appId) {
      gpkgVersion = "1.0/1.1";
    } else if (0x47504B47 == appId) {
      gpkgVersion = "1.2";
    }
  }


  void initSpatialMetadata(Database db) async {
//Connection cx = sqliteDb.getJdbcConnection();
//createFunctions(cx);

    isGpgkInitialized = gpkgVersion != null;

    try {
      String checkTable = "rtree_test_check";
      String checkRtree = "CREATE VIRTUAL TABLE " + checkTable + " USING rtree(id, minx, maxx, miny, maxy)";
      sqliteDb.execute(checkRtree);
      String drop = "DROP TABLE " + checkTable;
      sqliteDb.execute(drop);
      supportsRtree = true;
    } catch (e) {
      supportsRtree = false;
    }

    if (!isGpgkInitialized) {
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


      await db.transaction((tx) async {
        var split = sqlString.replaceAll("\n", "").trim().split(";");
        for (int i = 0; i < split.length; i++) {
          var sql = split[i].trim();
          if (sql.length > 0 && !sql.startsWith("--")) {
            await tx.execute(sql);
          }
        }
      });


      sqliteDb.execute("PRAGMA application_id = 0x47503130;");
    }
  }

  /** Returns list of contents of the geopackage.
   * @ */
  Future<List<Entry>> contents() async {
    String sql = "SELECT c.*, g.column_name, g.geometry_type_name, g.z , g.m FROM " + GEOPACKAGE_CONTENTS + " c, "
        + GEOMETRY_COLUMNS + " g where c.table_name=g.table_name";

    List<Map<String, dynamic>> res = await sqliteDb.query(sql);

    List<Entry> contents = [];
    res.forEach((map) {
      String dt = map["data_type"];
      DataType type = DataType.of(dt);
      Entry e = null;
      switch (type) {
        case DataType.Feature:
          e = createFeatureEntry(map);
          break;
        case DataType.Tile:
//                        e = createTileEntry(rs, cx);
          break;
        default:
          throw new StateError("unexpected type in GeoPackage");
      }
      if (e != null) {
        contents.add(e);
      }
    });

    return contents;
  }

  /** Lists all the feature entries in the geopackage. */
  Future<List<FeatureEntry>> features() async {
    String sql = "SELECT a.*, b.column_name, b.geometry_type_name, b.z, b.m, c.organization_coordsys_id, c.definition"
        + " FROM $GEOPACKAGE_CONTENTS a, $GEOMETRY_COLUMNS b, $SPATIAL_REF_SYS c WHERE a.table_name = b.table_name"
        + " AND a.srs_id = c.srs_id AND a.data_type = ?";
    var res = await sqliteDb.query(sql, [DataType.Feature.value]);

    List<FeatureEntry> contents = [];
    res.forEach((map) {
      contents.add(createFeatureEntry(map));
    });

    return contents;
  }

  /**
   * Looks up a feature entry by name.
   *
   * @param name THe name of the feature entry.
   * @return The entry, or <code>null</code> if no such entry exists.
   */
  Future<FeatureEntry> feature(String name) async {
    if (!await sqliteDb.hasTable(GEOMETRY_COLUMNS)) {
      return null;
    }

    String sql = "SELECT a.*, b.column_name, b.geometry_type_name, b.m, b.z, c.organization_coordsys_id, c.definition"
        + " FROM $GEOPACKAGE_CONTENTS a, $GEOMETRY_COLUMNS b, $SPATIAL_REF_SYS c WHERE a.table_name = b.table_name "
        + " AND a.srs_id = c.srs_id AND lower(a.table_name) = lower(?)" + " AND a.data_type = ?";

    var res = await sqliteDb.query(sql, [name, DataType.Feature.value]);
    if (res.isNotEmpty) {
      return createFeatureEntry(res[0]);
    }
    return null;
  }

  /**
   * Verifies if a spatial index is present
   *
   * @param entry The feature entry.
   * @return whether this feature entry has a spatial index available.
   * @throws IOException
   */
  Future<bool> hasSpatialIndex(String table) async {
    FeatureEntry featureEntry = await feature(table);

    String sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? ";
    var res = await sqliteDb.query(sql, [getSpatialIndexName(featureEntry)]);
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
    e.setZ(rs["z"]);
    e.setM(rs["m"]);
    return e;
  }

  void addDefaultSpatialReferences() {
    try {
      addCRS(-1, "Undefined cartesian SRS", "NONE", -1, "undefined", "undefined cartesian coordinate reference system");
      addCRS(0, "Undefined geographic SRS", "NONE", 0, "undefined", "undefined geographic coordinate reference system");
      addCRS(4326, "WGS 84 geodetic", "EPSG", 4326,
          "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\","
              + "6378137,298.257223563,AUTHORITY[\"EPSG\",\"7030\"]],AUTHORITY[\"EPSG\",\"6326\"]],"
              + "PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,"
              + "AUTHORITY[\"EPSG\",\"9122\"]],AUTHORITY[\"EPSG\",\"4326\"]]",
          "longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid");
      addCRS(3857, "WGS 84 Pseudo-Mercator", "EPSG", 4326, "PROJCS[\"WGS 84 / Pseudo-Mercator\", \n"
          + "  GEOGCS[\"WGS 84\", \n" + "    DATUM[\"World Geodetic System 1984\", \n"
          + "      SPHEROID[\"WGS 84\", 6378137.0, 298.257223563, AUTHORITY[\"EPSG\",\"7030\"]], \n"
          + "      AUTHORITY[\"EPSG\",\"6326\"]], \n"
          + "    PRIMEM[\"Greenwich\", 0.0, AUTHORITY[\"EPSG\",\"8901\"]], \n"
          + "    UNIT[\"degree\", 0.017453292519943295], \n" + "    AXIS[\"Geodetic longitude\", EAST], \n"
          + "    AXIS[\"Geodetic latitude\", NORTH], \n" + "    AUTHORITY[\"EPSG\",\"4326\"]], \n"
          + "  PROJECTION[\"Popular Visualisation Pseudo Mercator\", AUTHORITY[\"EPSG\",\"1024\"]], \n"
          + "  PARAMETER[\"semi-minor axis\", 6378137.0], \n" + "  PARAMETER[\"Latitude of false origin\", 0.0], \n"
          + "  PARAMETER[\"Longitude of natural origin\", 0.0], \n"
          + "  PARAMETER[\"Scale factor at natural origin\", 1.0], \n" + "  PARAMETER[\"False easting\", 0.0], \n"
          + "  PARAMETER[\"False northing\", 0.0], \n" + "  UNIT[\"m\", 1.0], \n" + "  AXIS[\"Easting\", EAST], \n"
          + "  AXIS[\"Northing\", NORTH], \n" + "  AUTHORITY[\"EPSG\",\"3857\"]]",
          "WGS 84 Pseudo-Mercator, often referred to as Webmercator.");
    }
    catch
    (
    ex) {
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

  Future<void> addCRS(int srid, String srsName, String organization, int organizationCoordSysId, String definition,
      String description) async {
    bool hasAlready = await hasCrs(srid);
    if (hasAlready)
      return;

    String sql = "INSERT INTO $SPATIAL_REF_SYS (srs_id, srs_name, organization, organization_coordsys_id, definition, description) VALUES (?,?,?,?,?,?)";


    int inserted = await sqliteDb.insert(sql, [srid, srsName, organization, organizationCoordSysId, definition, description]);

    if (inserted != 1) {
      throw new IOException("Unable to insert CRS: $srid");
    }
  }

  Future<bool> hasCrs(int srid) async {
    String sqlPrep = "SELECT srs_id FROM $SPATIAL_REF_SYS WHERE srs_id = ?";
    List<Map<String, dynamic>> res = await sqliteDb.query(sqlPrep, [srid]);
    return res.length > 0;
  }



  void close() {
    sqliteDb.close();
  }


  void createSpatialTable(String tableName, int tableSrid, String geometryFieldData, List<String> fieldData, List<String> foreignKeys, bool avoidIndex) {
    StringBuffer sb = new StringBuffer();
    sb.write("CREATE TABLE ");
    sb.write(tableName);
    sb.write("(");
    for (int i = 0; i < fieldData.length; i++) {
      if (i != 0)
        sb.write(",");
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

    sqliteDb.execute(sb.toString());

    List<String> g = geometryFieldData.split("\\s+");
    addGeoPackageContentsEntry(tableName, tableSrid, null, null);
    addGeometryColumnsEntry(tableName, g[0], g[1], tableSrid, false, false);

    addGeometryXYColumnAndIndex(tableName, g[0], g[1], tableSrid.toString(), avoidIndex);
  }


  Envelope getTableBounds(String tableName) {
// TODO
    throw new RuntimeException("Not implemented yet...");
  }

  Future<QueryResult> getTableRecordsMapIn(String tableName, Envelope envelope, int limit, int reprojectSrid, String whereStr) async{
    QueryResult queryResult = new QueryResult();
    GeometryColumn gCol = null;
    String geomColLower = null;
    try {
      gCol = getGeometryColumnsForTable(tableName);
      if (gCol != null)
        geomColLower = gCol.geometryColumnName.toLowerCase();
    }
    catch
    (e) {
// ignore
    }

    List<List<String>> tableColumnsInfo = getTableColumns(tableName);
    int columnCount = tableColumnsInfo.length;

    int index = 0;
    List<String> items = new ArrayList<>();
    List<ResultSetToObjectFunction> funct = new ArrayList<>();
    for (List < String > columnInfo : tableColumnsInfo) {
      String columnName = columnInfo[0];
      if (DbsUtilities.isReservedName(columnName)) {
        columnName = DbsUtilities.fixReservedNameForQuery(columnName);
      }

      String columnTypeName = columnInfo[1];

      queryResult.names.add(columnName);
      queryResult.types.add(columnTypeName);

      String isPk = columnInfo[2];
      if (isPk.equals("1")) {
        queryResult.pkIndex = index;
      }
      if (geomColLower != null && columnName.toLowerCase().equals(geomColLower)) {
        queryResult.geometryIndex = index;

        if (reprojectSrid == -1 || reprojectSrid == gCol.srid) {
          items.add(geomColLower);
        } else {
          items.add("ST_Transform(" + geomColLower + "," + reprojectSrid + ") AS " + geomColLower);
        }
      } else {
        items.add(columnName);
      }
      index++;

      EDataType type = EDataType.getType4Name(columnTypeName);
      switch (type) {
        case TEXT:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getString(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case INTEGER:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getInt(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case BOOLEAN:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getInt(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case FLOAT:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getFloat(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case DOUBLE:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getDouble(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case LONG:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getLong(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case BLOB:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            return resultSet.getBytes(index);
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        case DATETIME:
        case DATE:
          {
            funct.add(new ResultSetToObjectFunction(){

            Object getObject( IHMResultSet resultSet, int index ) {
            try {
            String date = resultSet.getString(index);
            return date;
            } catch (Exception e) {
            e.printStackTrace();
            return null;
            }
            }
            });
            break;
          }
        default:
          funct.add(null);
          break;
      }
    }

    String sql = "SELECT ";
    sql += DbsUtilities.joinByComma(items);
    sql += " FROM " + tableName;

    List<String> whereStrings = new ArrayList<>();
    if (envelope != null) {
      double x1 = envelope.getMinX();
      double y1 = envelope.getMinY();
      double x2 = envelope.getMaxX();
      double y2 = envelope.getMaxY();
      String spatialindexBBoxWherePiece = getSpatialindexBBoxWherePiece(tableName, null, x1, y1, x2, y2);
      if (spatialindexBBoxWherePiece != null)
        whereStrings.add(spatialindexBBoxWherePiece);
    }
    if (whereStr != null) {
      whereStrings.add(whereStr);
    }
    if (whereStrings.size() > 0) {
      sql += " WHERE "; //
      sql += DbsUtilities.joinBySeparator(whereStrings, " AND ");
    }

    if (limit > 0) {
      sql += " LIMIT " + limit;
    }

    IGeometryParser gp = getType().getGeometryParser();
    String _sql = sql;
    return execOnConnection(connection -> {
    long start = System.currentTimeMillis();
    try (IHMStatement stmt = connection.createStatement(); IHMResultSet rs = stmt.executeQuery(_sql)) {
    while( rs.next() ) {
    Object[] rec = new Object[columnCount];
    for( int j = 1; j <= columnCount; j++ ) {
    if (queryResult.geometryIndex == j - 1) {
    Geometry geometry = gp.fromResultSet(rs, j);
    if (geometry != null) {
    rec[j - 1] = geometry;
    }
    } else {
    ResultSetToObjectFunction function = funct.get(j - 1);
    Object object = function.getObject(rs, j);
    if (object instanceof Clob) {
    object = rs.getString(j);
    }
    rec[j - 1] = object;
    }
    }
    queryResult.data.add(rec);
    }
    long end = System.currentTimeMillis();
    queryResult.queryTimeMillis = end - start;
    return queryResult;
    }
    });
  }


  protected

  void logWarn(String message) {
    Logger.INSTANCE.insertWarning(null, message);
  }


  protected

  void logInfo(String message) {
    Logger.INSTANCE.insertInfo(null, message);
  }


  protected

  void logDebug(String message) {
    Logger.INSTANCE.insertDebug(null, message);
  }

  HashMap<String, List<String>> getTablesMap(bool doOrder) {
    List<String> tableNames = getTables(doOrder);
    HashMap<String, List<String>> tablesMap = GeopackageTableNames.getTablesSorted(tableNames, doOrder);
    return tablesMap;
  }

  String getSpatialindexBBoxWherePiece(String tableName, String alias, double x1, double y1, double x2, double y2) {
    if (!supportsRtree)
      return null;
    FeatureEntry feature = feature(tableName);
    String spatial_index = getSpatialIndexName(feature);

    String pk = SpatialiteCommonMethods.getPrimaryKey(sqliteDb, tableName);
    if (pk == null) {
// can't use spatial index
      return null;
    }

    String check = "(" + x1 + " <= maxx and " + x2 + " >= minx and " + y1 + " <= maxy and " + y2 + " >= miny)";
// Make Sure the table name is escaped
    String sql = pk + " IN ( SELECT id FROM \"" + spatial_index + "\"  WHERE " + check + ")";
    return sql;
  }

  String getSpatialindexGeometryWherePiece(String tableName, String alias, Geometry geometry) {
// this is not possible in gpkg, backing on envelope intersection
    Envelope env = geometry.getEnvelopeInternal();
    return getSpatialindexBBoxWherePiece(tableName, alias, env.getMinX(), env.getMinY(), env.getMaxX(), env.getMaxY());
  }

  Future<GeometryColumn> getGeometryColumnsForTable(String tableName) async {
    FeatureEntry featureEntry = await feature(tableName);
    if (featureEntry == null)
      return null;
    GeometryColumn gc = new GeometryColumn();
    gc.tableName = tableName;
    gc.geometryColumnName = featureEntry.geometryColumn;
    gc.geometryType = featureEntry.geometryType;
    int dim = 2;
    if (featureEntry.z)
      dim++;
    if (featureEntry.m)
      dim++;
    gc.coordinatesDimension = dim;
    gc.srid = featureEntry.srid;
    gc.isSpatialIndexEnabled = await hasSpatialIndex(tableName) ? 1 : 0;
    return gc;
  }


  Future<List<String>> getTables(bool doOrder) async {
    return sqliteDb.getTables(doOrder);
  }


  Future<bool> hasTable(String tableName) async {
    return await sqliteDb.hasTable(tableName);
  }


  List <List<String>> getTableColumns(String tableName) {
    List <List<String>> tableColumns = SpatialiteCommonMethods.getTableColumns(this, tableName);
    return tableColumns;
  }

  void deleteGeoTable(String tableName) {
    String sql = getType().getSqlTemplates().dropTable(tableName, null);
    sqliteDb.executeInsertUpdateDeleteSql(sql);
  }

  void addGeometryXYColumnAndIndex(String tableName, String geomColName, String geomType, String epsg,
      bool avoidIndex) {
    if (!avoidIndex)
      createSpatialIndex(tableName, geomColName);
  }

  void addGeometryXYColumnAndIndex(String tableName, String geomColName, String geomType, String epsg) {
    createSpatialIndex(tableName, geomColName);
  }

//  QueryResult getTableRecordsMapFromRawSql(String sql, int limit) {
//    QueryResult queryResult = new QueryResult();
//    try
//    (IHMStatement stmt = sqliteDb.getConnectionInternal().createStatement();
//    IHMResultSet rs = stmt.executeQuery(sql)
//    ) {
//    IHMResultSetMetaData rsmd = rs.getMetaData();
//    int columnCount = rsmd.getColumnCount();
//    int geometryIndex = -1;
//    for( int i = 1; i <= columnCount; i++ ) {
//    String columnName = rsmd.getColumnName(i);
//    queryResult.names.add(columnName);
//    String columnTypeName = rsmd.getColumnTypeName(i);
//    queryResult.types.add(columnTypeName);
//    if (ESpatialiteGeometryType.isGeometryName(columnTypeName)) {
//    geometryIndex = i;
//    queryResult.geometryIndex = i - 1;
//    }
//    }
//    int count = 0;
//    IGeometryParser gp = getType().getGeometryParser();
//    long start = System.currentTimeMillis();
//    while( rs.next() ) {
//    Object[] rec = new Object[columnCount];
//    for( int j = 1; j <= columnCount; j++ ) {
//    if (j == geometryIndex) {
//    Geometry geometry = gp.fromResultSet(rs, j);
//    if (geometry != null) {
//    rec[j - 1] = geometry;
//    }
//    } else {
//    Object object = rs.getObject(j);
//    if (object instanceof Clob) {
//    object = rs.getString(j);
//    }
//    rec[j - 1] = object;
//    }
//    }
//    queryResult.data.add(rec);
//    if (limit > 0 && ++count > (limit - 1)) {
//    break;
//    }
//    }
//    long end = System.currentTimeMillis();
//    queryResult.queryTimeMillis = end - start;
//    return queryResult;
//    }
//  }

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
  void createSpatialIndex(String tableName, String geometryName) {
    Map<String, String> properties = new HashMap<String, String>();

    String pk = SpatialiteCommonMethods.getPrimaryKey(sqliteDb, tableName);
    if (pk == null) {
      throw new IOException("Spatial index only supported for primary key of single column.");
    }
    properties.put("t", tableName);
    properties.put("c", geometryName);
    properties.put("i", pk);

    InputStream resourceAsStream = GeopackageDb
    .class.getResourceAsStream(SPATIAL_INDEX + ".sql");
    runScript(resourceAsStream, getJdbcConnection(), properties);
  }

  void addGeoPackageContentsEntry(String tableName, int srid, String description, Envelope crsBounds) {
    if (!hasCrs(srid))
      throw new IOException("The srid is not yet present in the package. Please add it before proceeding.");

    final SimpleDateFormat DATE_FORMAT = new SimpleDateFormat(DATE_FORMAT_STRING);
    DATE_FORMAT.setTimeZone(TimeZone.getTimeZone("GMT"));

    StringBuilder sb = new StringBuilder();
    StringBuilder vals = new StringBuilder();

    sb.append(format("INSERT INTO %s (table_name, data_type, identifier", GEOPACKAGE_CONTENTS));
    vals.append("VALUES (?,?,?");

    if (description != null) {
      sb.append(", description");
      vals.append(",?");
    }

    sb.append(", min_x, min_y, max_x, max_y");
    vals.append(",?,?,?,?");

    sb.append(", srs_id");
    vals.append(",?");
    sb.append(") ").append(vals.append(")").toString());

    sqliteDb.execOnConnection(connection -> {
    try (IHMPreparedStatement pStmt = connection.prepareStatement(sb.toString())) {
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

    int i = 1;
    pStmt.setString(i++, tableName);
    pStmt.setString(i++, Entry.DataType.Feature.value());
    pStmt.setString(i++, tableName);
    if (description != null)
    pStmt.setString(i++, description);
    pStmt.setDouble(i++, minx);
    pStmt.setDouble(i++, miny);
    pStmt.setDouble(i++, maxx);
    pStmt.setDouble(i++, maxy);
    pStmt.setInt(i++, srid);

    pStmt.executeUpdate();
    return null;
    }
    });
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
  void addGeometryColumnsEntry(String tableName, String geometryName, String geometryType, int srid, bool hasZ,
      bool hasM) {
// geometryless tables should not be inserted into this table.
    String sql = format("INSERT INTO %s VALUES (?, ?, ?, ?, ?, ?);", GEOMETRY_COLUMNS);

    sqliteDb.execOnConnection(connection -> {
    try (IHMPreparedStatement pStmt = connection.prepareStatement(sql)) {
    int i = 1;
    pStmt.setString(i++, tableName);
    pStmt.setString(i++, geometryName);
    pStmt.setString(i++, geometryType);
    pStmt.setInt(i++, srid);
    pStmt.setInt(i++, hasZ ? 1 : 0);
    pStmt.setInt(i++, hasM ? 1 : 0);

    pStmt.executeUpdate();
    return null;
    }
    });
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



