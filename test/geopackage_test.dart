import 'dart:io';

import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import "package:test/test.dart";

void main() async {
  GeopackageDb vectorDb;

  setUp(() async {
    File dbFile = File("./test/gdal_sample.gpkg");
    var ch = ConnectionsHandler();
    vectorDb = await ch.open(dbFile.path);
    vectorDb.openOrCreate();
  });

  tearDown(() {
    vectorDb?.close();
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

      List<Geometry> geometries = vectorDb.getGeometriesIn(geomcollection2DTable);
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
  });
}
