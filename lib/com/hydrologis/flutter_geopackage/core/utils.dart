part of flutter_geopackage;

class SQLException implements Exception {
  String msg;

  SQLException(this.msg);

  String toString() => "SQLException: " + msg;
}

/// A simple table info.
///
/// <p>If performance is needed, this should not be used.</p>
class GPQueryResult {
  String geomName;

  /// This can optionally be used to identify record sources
  /// in case of mixed data sources (ex. merging together
  /// QueryResults from different queries.
  List<String> ids;

  List<Geometry> geoms = [];

  List<Map<String, dynamic>> data = [];
}

/// Class representing a geometry_columns record.
class GeometryColumn {
  // VARIABLES
  SqlName tableName;
  String geometryColumnName;

  /// The type, as compatible with {@link EGeometryType#fromGeometryTypeCode(int)} and {@link ESpatialiteGeometryType#forValue(int)}.
  EGeometryType geometryType;
  int coordinatesDimension;
  int srid;
  int isSpatialIndexEnabled;
}

class GeometryUtilities {
  /// Create a polygon of the supplied [env].
  ///
  /// In case of [makeCircle] set to true, a buffer of half the width
  /// of the [env] is created in the center point.
  static Geometry fromEnvelope(Envelope env, {bool makeCircle = false}) {
    double w = env.getMinX();
    double e = env.getMaxX();
    double s = env.getMinY();
    double n = env.getMaxY();

    if (makeCircle) {
      var centre = env.centre();
      var point = GeometryFactory.defaultPrecision().createPoint(centre);
      var buffer = point.buffer(env.getWidth() / 2.0);
      return buffer;
    }
    return GeometryFactory.defaultPrecision().createPolygonFromCoords([
      Coordinate(w, s),
      Coordinate(w, n),
      Coordinate(e, n),
      Coordinate(e, s),
      Coordinate(w, s),
    ]);
  }
}

class GeopackageTableNames {
  static final String startsWithIndexTables = "rtree_";

  // METADATA
  static final List<String> metadataTables = [
    "gpkg_contents", //
    "gpkg_geometry_columns", //
    "gpkg_spatial_ref_sys", //
    "gpkg_data_columns", //
    "gpkg_tile_matrix", //
    "gpkg_metadata", //
    "gpkg_metadata_reference", //
    "gpkg_tile_matrix_set", //
    "gpkg_data_column_constraints", //
    "gpkg_extensions", //
    "gpkg_ogr_contents", //
    "gpkg_spatial_index", //
    "spatial_ref_sys", //
    "st_spatial_ref_sys", //
    "android_metadata", //
  ];

  // INTERNAL DATA
  static final List<String> internalDataTables = [
    //
    "sqlite_stat1", //
    "sqlite_stat3", //
    "sql_statements_log", //
    "sqlite_sequence" //
  ];

  static const USERDATA = "User Data";
  static const SYSTEM = "System tables";

  /// Sorts all supplied table names by type.
  ///
  /// <p>
  /// Supported types are:
  /// <ul>
  /// <li>{@value ISpatialTableNames#INTERNALDATA} </li>
  /// <li>{@value ISpatialTableNames#SYSTEM} </li>
  /// </ul>
  ///
  /// @param allTableNames list of all tables.
  /// @param doSort if <code>true</code>, table names are alphabetically sorted.
  /// @return the {@link LinkedHashMap}.
  static Map<String, List<String>> getTablesSorted(
      List<SqlName> allTableNames, bool doSort) {
    Map<String, List<String>> tablesMap = {};
    tablesMap[USERDATA] = [];
    tablesMap[SYSTEM] = [];

    for (SqlName name in allTableNames) {
      var tableName = name.name.toLowerCase();
      if (tableName.startsWith(startsWithIndexTables) ||
          metadataTables.contains(tableName) ||
          internalDataTables.contains(tableName)) {
        List<String> list = tablesMap[SYSTEM];
        list.add(tableName);
        continue;
      }
      List<String> list = tablesMap[USERDATA];
      list.add(tableName);
    }

    if (doSort) {
      for (List<String> values in tablesMap.values) {
        values.sort();
      }
    }

    return tablesMap;
  }
}

class Proj {
  static final PROJ.Projection EPSG4326 = PROJ.Projection.WGS84;
  static final int EPSG4326_INT = 4326;
  static final int EPSG3857_INT = 3857;
  static final PROJ.Projection EPSG3857 =
      PROJ.Projection.get('EPSG:$EPSG3857_INT');

  static PROJ.Projection fromSrid(int srid) {
    if (srid == EPSG3857_INT) return EPSG3857;
    if (srid == EPSG4326_INT) return EPSG4326;
    var prj = PROJ.Projection.get("EPSG:$srid");
    return prj;
  }

  static PROJ.Point transform(
      PROJ.Projection from, PROJ.Projection to, PROJ.Point point) {
    return from.transform(to, point);
  }

  static PROJ.Point transformToWgs84(PROJ.Projection from, PROJ.Point point) {
    return from.transform(EPSG4326, point);
  }

  static Envelope transformEnvelope(
      PROJ.Projection from, PROJ.Projection to, Envelope envelope) {
    PROJ.Point ll = PROJ.Point(x: envelope.getMinX(), y: envelope.getMinY());
    PROJ.Point ur = PROJ.Point(x: envelope.getMaxX(), y: envelope.getMaxY());
    var newLL = from.transform(to, ll);
    var newUR = from.transform(to, ur);
    return Envelope.fromCoordinates(
        Coordinate(newLL.x, newLL.y), Coordinate(newUR.x, newUR.y));
  }

  static Envelope transformEnvelopeToWgs84(
      PROJ.Projection from, Envelope envelope) {
    return transformEnvelope(from, EPSG4326, envelope);
  }
}
