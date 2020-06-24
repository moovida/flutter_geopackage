import 'dart:io';

import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/com/hydrologis/flutter_geopackage/core/queries.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import "package:test/test.dart";

void main() {
  GeopackageDb vectorDb;
  GeopackageDb rasterDb;
  GeopackageDb earth4326Db;

  setUpAll(() {
    var ch = ConnectionsHandler();
    File vectorDbFile = File("./test/gdal_sample.gpkg");
    vectorDb = ch.open(vectorDbFile.path);
    vectorDb.openOrCreate();

    File rasterDbFile = File("./test/tiles_3857.gpkg");
    rasterDb = ch.open(rasterDbFile.path);
    rasterDb.openOrCreate();

    File earthDbFile = File("./test/earth.gpkg");
    earth4326Db = ch.open(earthDbFile.path);
    earth4326Db.openOrCreate();
    earth4326Db.forceRasterMobileCompatibility = false;
  });

  tearDownAll(() {
    vectorDb?.close();
    rasterDb?.close();
    earth4326Db?.close();
  });

  group("Geopackage Test Creation - ", () {
    test("test new db creation", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        expect(db.hasTable(TABLE_GEOPACKAGE_CONTENTS), true);
        expect(db.hasTable(TABLE_SPATIAL_REF_SYS), true);
        expect(db.hasTable(TABLE_DATA_COLUMN_CONSTRAINTS), true);
        expect(db.hasTable(TABLE_DATA_COLUMNS), true);
        expect(db.hasTable(TABLE_EXTENSIONS), true);
        expect(db.hasTable(TABLE_GEOMETRY_COLUMNS), true);
        expect(db.hasTable(TABLE_METADATA_REFERENCE), true);
        expect(db.hasTable(TABLE_METADATA), true);
        expect(db.hasTable(TABLE_TILE_MATRIX_SET), true);
        expect(db.hasTable(TABLE_TILE_MATRIX_METADATA), true);
      } finally {
        db.close();
      }
    });
    test("test new table creation", () {
      var db = GeopackageDb.memory();
      try {
        db.openOrCreate();

        db.createSpatialTable(
          "table1",
          4326,
          "the_geom POINT",
          [
            "id INTEGER PRIMARY KEY AUTOINCREMENT",
            "name TEXT NOT NULL",
          ],
          null,
          false,
        );

        expect(db.hasTable("table1"), true);
        expect(db.hasSpatialIndex("table1"), true);

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

        var sql = "INSERT INTO table1 (the_geom, name) VALUES (?,?);";

        db.execute(sql, [geomBytes1, 'the one']);
        db.execute(sql, [geomBytes2, 'the two']);
        db.execute(sql, [geomBytes3, 'the three']);

        var geometries =
            db.getGeometriesIn("table1", envelope: Envelope(0, 1.5, 0, 1.5));
        expect(geometries.length, 1);
        expect(geometries.first.distance(point1), 0);
      } finally {
        db.close();
      }
    });
  });

  group("Geopackage Vectors - ", () {
    test("testGeneralInfo", () {
      expect(vectorDb.supportsSpatialIndex, true);
      expect(vectorDb.version, "1.0/1.1");
    });
    test("testTables", () {
      Map<String, List<String>> tablesMap = vectorDb.getTablesMap(false);
      List<String> tables = tablesMap[GeopackageTableNames.USERDATA];
      expect(tables.length, 16);
    });
    test("test2dPointTable", () {
      String point2DTable = "point2d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(point2DTable);

      GeometryColumn geometryColumn =
          vectorDb.getGeometryColumnsForTable(point2DTable);

      List<Geometry> geometries = vectorDb.getGeometriesIn(point2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0].toText(), "POINT (1 2)");
      expect(hasSpatialIndex, true);
      expect(geometryColumn.geometryColumnName, "geom");
      expect(geometryColumn.srid, 0);
    });

    test("test2dLineStringTable", () {
      String line2DTable = "linestring2d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(line2DTable);
      GeometryColumn geometryColumn =
          vectorDb.getGeometryColumnsForTable(line2DTable);
      List<Geometry> geometries = vectorDb.getGeometriesIn(line2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0].toText(), "LINESTRING (1 2, 3 4)");
      expect(hasSpatialIndex, true);
      expect(geometryColumn.geometryColumnName, "geom");
      expect(geometryColumn.srid, 4326);
    });

    test("test2dPolygonTable", () {
      String polygon2DTable = "polygon2d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(polygon2DTable);
      GeometryColumn geometryColumn =
          vectorDb.getGeometryColumnsForTable(polygon2DTable);
      List<Geometry> geometries = vectorDb.getGeometriesIn(polygon2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0].toText(),
          "POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0), (1 1, 1 9, 9 9, 9 1, 1 1))");
      expect(hasSpatialIndex, true);
      expect(geometryColumn.geometryColumnName, "geom");
      expect(geometryColumn.srid, 32631);
    });

    test("test2dMultiPointTable", () {
      String multipoint2DTable = "multipoint2d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(multipoint2DTable);
      List<Geometry> geometries = vectorDb.getGeometriesIn(multipoint2DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0].toText(), "MULTIPOINT ((0 1), (2 3))");
      expect(hasSpatialIndex, false);
    });

    test("test_geomcollection2d_bounds_geom_queries", () {
      String geomcollection2DTable = "geomcollection2d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(geomcollection2DTable);
      expect(hasSpatialIndex, true);

      List<Geometry> geometries =
          vectorDb.getGeometriesIn(geomcollection2DTable);
      geometries.removeWhere((g) => g == null);
      expect(geometries.length, 4);

      // using the spatial index (or just bounds if no index supported)
      var env = Envelope(9, 11, 9, 11);
      List<Geometry> geometriesE =
          vectorDb.getGeometriesIn(geomcollection2DTable, envelope: env);
      expect(geometriesE.length, 2);

      Geometry geom = WKTReader()
          .read("POLYGON ((2.65 5.3, 4.875 3.7, 2.9 5.65, 2.65 5.3))");
      var geomsPol = vectorDb.getGeometriesIntersecting(
        geomcollection2DTable,
        geometry: geom,
      );
      expect(geomsPol.length, 1);
    });

    test("test3dPointTable", () {
      String point3DTable = "point3d";
      bool hasSpatialIndex = vectorDb.hasSpatialIndex(point3DTable);

      List<Geometry> geometries = vectorDb.getGeometriesIn(point3DTable);
      geometries.removeWhere((g) => g == null);

      expect(geometries.length, 1);
      expect(geometries[0].toText(), "POINT (1 2)");
      expect(hasSpatialIndex, true);
    });

    test("testIsEmptyfunction", () {
      String sql =
          "select * from point2d where geom NOT NULL AND NOT ST_IsEmpty(geom)";
      var result = vectorDb.select(sql);
      expect(result.length, 1);
    });

    test("test_min_max_functions", () {
      String sql =
          "select ST_MinX(geom), ST_MaxX(geom),ST_MinY(geom),ST_MaxY(geom) from polygon2d where geom is not null";
      var result = vectorDb.select(sql);
      var row = result.first;

      expect(row.columnAt(0), 0.0);
      expect(row.columnAt(1), 10.0);
      expect(row.columnAt(2), 0.0);
      expect(row.columnAt(3), 10.0);

      expect(result.length, 1);
    });

    test("test_attributes_update", () {
      String sql = "select * from point2d where fid=1";
      var result = vectorDb.select(sql);
      var row = result.first;

      var geomField = row['geom'];
      var intField = row['intfield'];
      var strField = row['strfield'];
      var realField = row['realfield'];
      var dateTimeField = row['datetimefield'];
      var dateField = row['datefield'];
      var binaryField = row['binaryfield'];

      var geometry = GeoPkgGeomReader(geomField).get();
      expect(geometry.toText(), "POINT (1 2)");
      expect(intField, 1);
      expect(strField, "foo");
      expect(realField, 1.23456);
      expect(dateTimeField, "2014-06-07T14:20:00Z");
      expect(dateField, "2014-06-07");
      expect(binaryField.length, 3);

      String updateSql = """
          update point2d set geom=?, intfield=?, strField=?, realField=?, datetimefield=?, datefield=?
          where fid=1
          """;

      var newPoint =
          GeometryFactory.defaultPrecision().createPoint(Coordinate(10, 20));
      var geometryBytes = GeoPkgGeomWriter().write(newPoint);
      var arguments = [
        geometryBytes,
        5,
        "bau",
        -0.12345,
        "2014-06-23T23:23:00Z",
        "2014-06-23",
      ];
      var updated = vectorDb.execute(updateSql, arguments);
      expect(updated, 1);

      result = vectorDb.select(sql);
      row = result.first;

      geomField = row['geom'];
      intField = row['intfield'];
      strField = row['strfield'];
      realField = row['realfield'];
      dateTimeField = row['datetimefield'];
      dateField = row['datefield'];
      binaryField = row['binaryfield'];

      geometry = GeoPkgGeomReader(geomField).get();
      expect(geometry.toText(), "POINT (10 20)");
      expect(intField, 5);
      expect(strField, "bau");
      expect(realField, -0.12345);
      expect(dateTimeField, "2014-06-23T23:23:00Z");
      expect(dateField, "2014-06-23");
      expect(binaryField.length, 3);
    });
  });
  group("Geopackage Rasters - ", () {
    test("testGeneralInfo", () {
      expect(rasterDb.supportsSpatialIndex, true);
      expect(rasterDb.version, "1.0/1.1");
    });

    test("testTables", () {
      List<TileEntry> tilesList = rasterDb.tiles();
      expect(tilesList.length, 1);
    });

    test("testTileSettings", () {
      TileEntry entry = rasterDb.tile('tiles');
      List<TileMatrix> tileMatricies = entry.getTileMatricies();
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
      List<int> tileBytes = rasterDb.getTile('tiles', 0, 0, 1);
      expect(tileBytes.length, 3231);
    });
  });

  group("Geopackage Free Tiles Tests - ", () {
    test("test bounds", () {
      TileEntry entry = earth4326Db.tile('clouds');
      TilesFetcher fetcher = TilesFetcher(entry);
      var tile = fetcher.getLazyTile(earth4326Db, 0, 0);
      expect(tile.tileBoundsLatLong.getMinX(), -180);
      expect(tile.tileBoundsLatLong.getMaxX(), -135);
      expect(tile.tileBoundsLatLong.getMinY(), 45);
      expect(tile.tileBoundsLatLong.getMaxY(), 90);

      tile = fetcher.getLazyTile(earth4326Db, 2, 3);
      expect(tile.tileBoundsLatLong.getMinX(), -90);
      expect(tile.tileBoundsLatLong.getMaxX(), -45);
      expect(tile.tileBoundsLatLong.getMinY(), -90);
      expect(tile.tileBoundsLatLong.getMaxY(), -45);

      tile = fetcher.getLazyTile(earth4326Db, 7, 7);
      expect(tile.tileBoundsLatLong.getMinX(), 135);
      expect(tile.tileBoundsLatLong.getMaxX(), 180);
      expect(tile.tileBoundsLatLong.getMinY(), -270);
      expect(tile.tileBoundsLatLong.getMaxY(), -225);

      expect(tile.xTile, 7);
      expect(tile.yTile, 7);
      expect(tile.xPixels, 256);
      expect(tile.yPixels, 256);
    });

    test("test tile fetching", () {
      TileEntry entry = earth4326Db.tile('clouds');
      TilesFetcher fetcher = TilesFetcher(entry);

      var tile = fetcher.getLazyTile(earth4326Db, 0, 0);
      expect(tile.tileImageBytes != null, false);
      tile.fetch();
      expect(tile.tileImageBytes != null, true);

      tile = fetcher.getLazyTile(earth4326Db, 2, 3);
      tile.fetch();
      expect(tile.tileImageBytes != null, true);

      tile = fetcher.getLazyTile(earth4326Db, 7, 7);
      tile.fetch();
      expect(tile.tileImageBytes != null, false);
    });
  });
}
