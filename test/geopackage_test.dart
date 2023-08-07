import 'dart:io';

import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:dart_hydrologis_utils/dart_hydrologis_utils.dart';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/com/hydrologis/flutter_geopackage/core/queries.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import "package:test/test.dart";

void main() {
  GeopackageDb? vectorDb;
  GeopackageDb? rasterDb;
  GeopackageDb? earth4326Db;
  GeopackageDb? wrongGeomDb;

  setUpAll(() {
    var ch = ConnectionsHandler();
    File vectorDbFile = File("./test/gdal_sample.gpkg");
    vectorDb = ch.open(vectorDbFile.path);
    vectorDb!.openOrCreate();

    File rasterDbFile = File("./test/tiles_3857.gpkg");
    rasterDb = ch.open(rasterDbFile.path);
    rasterDb!.openOrCreate();

    File earthDbFile = File("./test/earth.gpkg");
    earth4326Db = ch.open(earthDbFile.path);
    earth4326Db!.openOrCreate();
    earth4326Db!.forceRasterMobileCompatibility = false;

    File wrongGeomDbFile = File("./test/test_jp.gpkg");
    wrongGeomDb = ch.open(wrongGeomDbFile.path);
    wrongGeomDb!.openOrCreate();
  });

  tearDownAll(() {
    vectorDb?.close();
    rasterDb?.close();
    earth4326Db?.close();
    wrongGeomDb?.close();
  });

  group("Geopackage Test Creation - ", () {
    test("test new db creation", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        expect(
            db.hasTable(
                TableName(TABLE_GEOPACKAGE_CONTENTS, schemaSupported: false)),
            true);
        expect(
            db.hasTable(
                TableName(TABLE_SPATIAL_REF_SYS, schemaSupported: false)),
            true);
        expect(
            db.hasTable(TableName(TABLE_DATA_COLUMN_CONSTRAINTS,
                schemaSupported: false)),
            true);
        expect(
            db.hasTable(TableName(TABLE_DATA_COLUMNS, schemaSupported: false)),
            true);
        expect(db.hasTable(TableName(TABLE_EXTENSIONS, schemaSupported: false)),
            true);
        expect(
            db.hasTable(
                TableName(TABLE_GEOMETRY_COLUMNS, schemaSupported: false)),
            true);
        expect(
            db.hasTable(
                TableName(TABLE_METADATA_REFERENCE, schemaSupported: false)),
            true);
        expect(db.hasTable(TableName(TABLE_METADATA, schemaSupported: false)),
            true);
        expect(
            db.hasTable(
                TableName(TABLE_TILE_MATRIX_SET, schemaSupported: false)),
            true);
        expect(
            db.hasTable(
                TableName(TABLE_TILE_MATRIX_METADATA, schemaSupported: false)),
            true);
      } finally {
        db.close();
      }
    });
    test("test new table creation, insert and update", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        var t1Name = TableName("table1", schemaSupported: false);
        db.createSpatialTable(
          t1Name,
          4326,
          "the_geom POINT",
          [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT NOT NULL",
          ],
          null,
          false,
        );

        expect(db.hasTable(t1Name), true);
        expect(db.hasSpatialIndex(t1Name), true);

        var result =
            db.select("select name from sqlite_master where type = 'trigger';");
        expect(result.length, 6);

        var gf = GeometryFactory.defaultPrecision();
        var point1 = gf.createPoint(Coordinate(1.0, 1.0));
        var geomBytes1 = GeoPkgGeomWriter().write(point1);
        var point2 = gf.createPoint(Coordinate(2.0, 2.0));
        var geomBytes2 = GeoPkgGeomWriter().write(point2);
        var point3 = gf.createPoint(Coordinate(100.0, 100.0));
        var geomBytes3 = GeoPkgGeomWriter().write(point3);

        var sql =
            "INSERT INTO ${t1Name.fixedName} (the_geom, name) VALUES (?,?);";

        db.execute(sql, arguments: [geomBytes1, 'the one']);
        db.execute(sql, arguments: [geomBytes2, 'the two']);
        db.execute(sql, arguments: [geomBytes3, 'the three']);

        var geometries =
            db.getGeometriesIn(t1Name, envelope: Envelope(0, 1.5, 0, 1.5));
        expect(geometries.length, 1);
        expect(geometries.first!.distance(point1), 0);

        var select = db.select("Select * from table1 where name='the two'");
        expect(select.length, 1);
        var row = select.first;

        var newRow = {
          'name': 'updated two',
          'the_geom': geomBytes1,
        };
        var changed = db.updateMap(t1Name, newRow, "id=${row.get('id')}");
        expect(changed, 1);

        geometries =
            db.getGeometriesIn(t1Name, envelope: Envelope(0, 1.5, 0, 1.5));
        expect(geometries.length, 2);

        var tableData = db.getTableData(t1Name, where: "name='updated two'");
        expect(tableData.features.length, 1);
        var geom = tableData.features[0].geometry;
        expect(geom!.equals(point1), true);

        geometries = db.getGeometriesIn(t1Name,
            envelope: Envelope(0, 1.5, 0, 1.5), limit: 1);
        expect(geometries.length, 1);
      } finally {
        db.close();
      }
    });

    test("test non spatial table creation and query", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        var t1Name = TableName("tablenonspatial", schemaSupported: false);
        var create = """create table ${t1Name.fixedName} (
            key TEXT,
            value TEXT
          )
          """;
        db.execute(create);

        expect(db.hasTable(t1Name), true);

        var sql =
            "INSERT INTO ${t1Name.fixedName} (key, value) VALUES ('dbversion','1');";
        db.execute(sql);
        sql =
            "INSERT INTO ${t1Name.fixedName} (key, value) VALUES ('parameter','bau');";
        db.execute(sql);

        var select = db.select(
            "Select value from ${t1Name.fixedName} where key='dbversion'");
        expect(select.length, 1);
        QueryResultRow first = select.first;
        var value = first.get("value");
        expect(value, "1");
      } finally {
        db.close();
      }
    });

    test("test new table creation, insert default values", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        var t1Name = TableName("table1", schemaSupported: false);
        db.createSpatialTable(
          t1Name,
          4326,
          "the_geom POINT",
          [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT",
          ],
          null,
          false,
        );
        var sql = "INSERT INTO ${t1Name.fixedName} DEFAULT VALUES;";
        db.execute(sql);

        var select = db.select("Select * from ${t1Name.fixedName}");
        expect(select.length, 1);
        var row = select.first;
        expect(row.get('id'), 1);
        expect(row.get('name') == null, true);
        expect(row.get('the_geom') == null, true);
      } finally {
        db.close();
      }
    });
  });

  group("Geopackage Vectors - ", () {
    test("testGeneralInfo", () {
      expect(vectorDb!.supportsSpatialIndex, true);
      expect(vectorDb!.version, "1.0/1.1");
    });
    test("testTables", () {
      Map<String, List<String>> tablesMap = vectorDb!.getTablesMap(false);
      List<String>? tables = tablesMap[GeopackageTableNames.USERDATA];
      expect(tables!.length, 16);
    });

    test("testEmptyLayer", () {
      File emptyDbFile = File("./test/empty_polygons.gpkg");
      var emptyLayerDb = GeopackageDb(emptyDbFile.path);
      emptyLayerDb.openOrCreate();

      Map<String, List<String>> tablesMap = emptyLayerDb.getTablesMap(false);
      List<String>? tables = tablesMap[GeopackageTableNames.USERDATA];
      expect(tables!.length, 1);

      var tableName = TableName("samplepolygon", schemaSupported: false);
      var emptyLayer = emptyLayerDb.feature(tableName);
      expect(emptyLayer!.srid, 4326);

      expect(emptyLayer.bounds == Envelope(0, 0, 0, 0), true);

      var tableData = emptyLayerDb.getTableData(tableName);
      expect(tableData.features.length, 0);

      var geometriesIn = emptyLayerDb.getGeometriesIn(tableName,
          envelope: Envelope(-180, 180, -90, 90));
      expect(geometriesIn.length, 0);
    });

    test("test2dPointTable", () {
      var point2DTable = TableName("point2d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(point2DTable);

      GeometryColumn? geometryColumn =
          vectorDb!.getGeometryColumnsForTable(point2DTable);

      List<Geometry?> geometries = vectorDb!.getGeometriesIn(point2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0]!.toText(), "POINT (10 20)");
      expect(hasSpatialIndex, true);
      expect(geometryColumn!.geometryColumnName, "geom");
      expect(geometryColumn.srid, 0);
    });

    test("test2dLineStringTable", () {
      var line2DTable = TableName("linestring2d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(line2DTable);
      GeometryColumn? geometryColumn =
          vectorDb!.getGeometryColumnsForTable(line2DTable);
      List<Geometry?> geometries = vectorDb!.getGeometriesIn(line2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0]!.toText(), "LINESTRING (1 2, 3 4)");
      expect(hasSpatialIndex, true);
      expect(geometryColumn!.geometryColumnName, "geom");
      expect(geometryColumn.srid, 4326);
    });

    test("test2dPolygonTable", () {
      var polygon2DTable = TableName("polygon2d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(polygon2DTable);
      GeometryColumn? geometryColumn =
          vectorDb!.getGeometryColumnsForTable(polygon2DTable);
      List<Geometry?> geometries = vectorDb!.getGeometriesIn(polygon2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0]!.toText(),
          "POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0), (1 1, 1 9, 9 9, 9 1, 1 1))");
      expect(hasSpatialIndex, true);
      expect(geometryColumn!.geometryColumnName, "geom");
      expect(geometryColumn.srid, 32631);
    });

    test("test2dMultiPointTable", () {
      var multipoint2DTable = TableName("multipoint2d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(multipoint2DTable);
      List<Geometry?> geometries = vectorDb!.getGeometriesIn(multipoint2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0]!.toText(), "MULTIPOINT ((0 1), (2 3))");
      expect(hasSpatialIndex, false);
    });

    test("test_geomcollection2d_bounds_geom_queries", () {
      var geomcollection2DTable =
          TableName("geomcollection2d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(geomcollection2DTable);
      expect(hasSpatialIndex, true);

      List<Geometry?> geometries =
          vectorDb!.getGeometriesIn(geomcollection2DTable);
      geometries.removeWhere((g) => g == null);
      expect(geometries.length, 4);

      // using the spatial index (or just bounds if no index supported)
      var env = Envelope(9, 11, 9, 11);
      List<Geometry?> geometriesE =
          vectorDb!.getGeometriesIn(geomcollection2DTable, envelope: env);
      expect(geometriesE.length, 2);

      Geometry? geom = WKTReader()
          .read("POLYGON ((2.65 5.3, 4.875 3.7, 2.9 5.65, 2.65 5.3))");
      var geomsPol = vectorDb!.getGeometriesIn(
        geomcollection2DTable,
        intersectionGeometry: geom,
      );
      expect(geomsPol.length, 1);
    });

    test("test3dPointTable", () {
      var point3DTable = TableName("point3d", schemaSupported: false);
      bool hasSpatialIndex = vectorDb!.hasSpatialIndex(point3DTable);

      List<Geometry?> geometries = vectorDb!.getGeometriesIn(point3DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0]!.toText(), "POINT (1 2)");
      expect(hasSpatialIndex, true);
    });

    test("testWrongGeomTable", () {
      var tables = wrongGeomDb?.getTables(true);

      var table = tables?[17];
      var geometryColumnsForTable =
          wrongGeomDb?.getGeometryColumnsForTable(table!);
      if (geometryColumnsForTable?.geometryType != EGeometryType.MULTIPOLYGON) {
        table = tables![18];
      }
      var geometries = wrongGeomDb!.getGeometriesIn(table!);
      expect(geometries.length, 1);
    });

    test("testIsEmptyfunction", () {
      String sql =
          "select * from point2d where geom NOT NULL AND NOT ST_IsEmpty(geom)";
      var result = vectorDb!.select(sql);
      expect(result.length, 1);
    });

    test("test_min_max_functions", () {
      String sql =
          "select ST_MinX(geom), ST_MaxX(geom),ST_MinY(geom),ST_MaxY(geom) from polygon2d where geom is not null";
      var result = vectorDb!.select(sql);
      var row = result.first;

      expect(row.getAt(0), 0.0);
      expect(row.getAt(1), 10.0);
      expect(row.getAt(2), 0.0);
      expect(row.getAt(3), 10.0);

      expect(result.length, 1);
    });

    // test("test_attributes_update", () {
    //   String sql = "select * from point2d where fid=1";
    //   var result = vectorDb!.select(sql);
    //   var row = result.first;

    //   var geomField = row.get('geom');
    //   var intField = row.get('intfield');
    //   var strField = row.get('strfield');
    //   var realField = row.get('realfield');
    //   var dateTimeField = row.get('datetimefield');
    //   var dateField = row.get('datefield');
    //   var binaryField = row.get('binaryfield');

    //   var geometry = GeoPkgGeomReader(geomField).get();
    //   expect(geometry.toText(), "POINT (10 20)");
    //   expect(intField, 5);
    //   expect(strField, "bau");
    //   expect(realField, -0.12345);
    //   expect(dateTimeField, "2014-06-07T14:20:00Z");
    //   expect(dateField, "2014-06-07");
    //   expect(binaryField.length, 3);

    //   String updateSql = """
    //       update point2d set geom=?, intfield=?, strField=?, realField=?, datetimefield=?, datefield=?
    //       where fid=1
    //       """;

    //   var newPoint =
    //       GeometryFactory.defaultPrecision().createPoint(Coordinate(10, 20));
    //   var geometryBytes = GeoPkgGeomWriter().write(newPoint);
    //   var arguments = [
    //     geometryBytes,
    //     5,
    //     "bau",
    //     -0.12345,
    //     "2014-06-23T23:23:00Z",
    //     "2014-06-23",
    //   ];
    //   var updated = vectorDb!.execute(updateSql, arguments: arguments);
    //   expect(updated, 1);

    //   result = vectorDb!.select(sql);
    //   row = result.first;

    //   geomField = row.get('geom');
    //   intField = row.get('intfield');
    //   strField = row.get('strfield');
    //   realField = row.get('realfield');
    //   dateTimeField = row.get('datetimefield');
    //   dateField = row.get('datefield');
    //   binaryField = row.get('binaryfield');

    //   geometry = GeoPkgGeomReader(geomField).get();
    //   expect(geometry.toText(), "POINT (10 20)");
    //   expect(intField, 5);
    //   expect(strField, "bau");
    //   expect(realField, -0.12345);
    //   expect(dateTimeField, "2014-06-23T23:23:00Z");
    //   expect(dateField, "2014-06-23");
    //   expect(binaryField.length, 3);
    // });

    test("test_style_io", () {
      var point2DTable = TableName("point2d", schemaSupported: false);

      var pointSld = vectorDb!.getSld(point2DTable);
      expect(pointSld, null);
      PointStyle pointStyle1 = PointStyle();
      String sldString = SldObjectBuilder("point2d")
          .addFeatureTypeStyle("fts1")
          .addRule("rule1")
          .addPointSymbolizer(pointStyle1)
          .build();
      vectorDb!.updateSld(point2DTable, sldString);
      pointSld = vectorDb!.getSld(point2DTable);
      var parser = SldObjectParser.fromString(pointSld!);
      parser.parse();
      var pointStyle2 = parser
          .featureTypeStyles.first.rules.first.pointSymbolizers.first.style;
      expect(pointStyle1, pointStyle2);
    });
  });
  group("Geopackage Rasters - ", () {
    test("testGeneralInfo", () {
      expect(rasterDb!.supportsSpatialIndex, true);
      expect(rasterDb!.version, "1.0/1.1");
    });

    test("testTables", () {
      List<TileEntry> tilesList = rasterDb!.tiles();
      expect(tilesList.length, 1);
    });

    test("testTileSettings", () {
      TileEntry? entry =
          rasterDb!.tile(TableName('tiles', schemaSupported: false));
      List<TileMatrix> tileMatricies = entry!.getTileMatricies();
      expect(tileMatricies.length, 5);
      tileMatricies.forEach((tm) {
        var zl = tm.zoomLevel;
        var cols = tm.matrixWidth;
        var rows = tm.matrixHeight;
        var tw = tm.tileWidth;
        var th = tm.tileHeight;
        var xPixelSize = tm.xPixelSize;
        var yPixelSize = tm.yPixelSize;
        if (zl == 1) {
          expect(cols, 2);
          expect(rows, 2);
          expect(tw, 256);
          expect(th, 256);
          expect(xPixelSize, 78271.51696402048);
          expect(yPixelSize, 78271.51696402048);
        } else if (zl == 5) {
          expect(cols, 32);
          expect(rows, 32);
          expect(tw, 256);
          expect(th, 256);
          expect(xPixelSize, 4891.96981025128);
          expect(yPixelSize, 4891.96981025128);
        }
      });
    });
    test("testGetTile", () {
      List<int>? tileBytes = rasterDb!
          .getTile(TableName('tiles', schemaSupported: false), 0, 0, 1);
      expect(tileBytes!.length, 3231);
    });
  });

  group("Geopackage Free Tiles Tests - ", () {
    test("test bounds", () {
      TileEntry? entry =
          earth4326Db!.tile(TableName('clouds', schemaSupported: false));
      TilesFetcher fetcher = TilesFetcher(entry!);
      var tile = fetcher.getLazyTile(earth4326Db!, 0, 0);
      expect(tile.tileBoundsLatLong!.getMinX(), -180);
      expect(tile.tileBoundsLatLong!.getMaxX(), -135);
      expect(tile.tileBoundsLatLong!.getMinY(), 45);
      expect(tile.tileBoundsLatLong!.getMaxY(), 90);

      tile = fetcher.getLazyTile(earth4326Db!, 2, 3);
      expect(tile.tileBoundsLatLong!.getMinX(), -90);
      expect(tile.tileBoundsLatLong!.getMaxX(), -45);
      expect(tile.tileBoundsLatLong!.getMinY(), -90);
      expect(tile.tileBoundsLatLong!.getMaxY(), -45);

      tile = fetcher.getLazyTile(earth4326Db!, 7, 7);
      expect(tile.tileBoundsLatLong!.getMinX(), 135);
      expect(tile.tileBoundsLatLong!.getMaxX(), 180);
      expect(tile.tileBoundsLatLong!.getMinY(), -270);
      expect(tile.tileBoundsLatLong!.getMaxY(), -225);

      expect(tile.xTile, 7);
      expect(tile.yTile, 7);
      expect(tile.xPixels, 256);
      expect(tile.yPixels, 256);
    });

    test("test tile fetching", () {
      TileEntry? entry =
          earth4326Db!.tile(TableName('clouds', schemaSupported: false));
      TilesFetcher fetcher = TilesFetcher(entry!);

      var tile = fetcher.getLazyTile(earth4326Db!, 0, 0);
      expect(tile.tileImageBytes != null, false);
      tile.fetch();
      expect(tile.tileImageBytes != null, true);

      tile = fetcher.getLazyTile(earth4326Db!, 2, 3);
      tile.fetch();
      expect(tile.tileImageBytes != null, true);

      tile = fetcher.getLazyTile(earth4326Db!, 7, 7);
      tile.fetch();
      expect(tile.tileImageBytes != null, false);
    });

    test("test dataset bounds", () {
      List<TileEntry> entryList = rasterDb!.tiles();
      expect(entryList.length, 1);

      var entry = entryList.first;
      expect(entry.srid, 3857);

      var bounds = entry.bounds;

      var minX = -2.0037508342789244E7;
      var minY = -2.0037508342789244E7;
      var maxX = 2.0037508342789244E7;
      var maxY = 2.0037508342789244E7;

      expect(minX.round(), bounds.getMinX().round());
      expect(minY.round(), bounds.getMinY().round());
      expect(maxX.round(), bounds.getMaxX().round());
      expect(maxY.round(), bounds.getMaxY().round());
    });
  });
}
