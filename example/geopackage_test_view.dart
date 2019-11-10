import 'package:flutter/material.dart';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'dart:io';

class GeopackageTestView extends StatefulWidget {
  GeopackageTestView({Key key}) : super(key: key);

  @override
  _GeopackageTestViewState createState() => _GeopackageTestViewState();
}

class _GeopackageTestViewState extends State<GeopackageTestView> {
  Widget _addInfoTile(String title, String message, {color: Colors.white}) {
    return Container(
      color: color,
      child: ListTile(
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }

  Future<List<Widget>> getWidgets() async {
    var path = "/storage/emulated/0/gdal_sample.gpkg";

    List<Widget> tiles = [];

    tiles.add(_addInfoTile("Open db", "Try opening: " + path));
    GeopackageDb db = GeopackageDb(path);
    try {
      await db.openOrCreate();
      tiles.add(_addInfoTile("Open db", "Done"));
    } catch (e) {
      tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}", color: Colors.red));
      return tiles;
    }

    tiles.add(_addInfoTile("Check tables", "Gather tables."));
    try {
      Map<String, List<String>> tablesMap = await db.getTablesMap(false);
      List<String> tables = tablesMap[GeopackageTableNames.USERDATA];
      assert(tables.length == 16);
      tiles.add(_addInfoTile("Open db", "Found ${tables.length} tables."));
    } catch (e) {
      tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}", color: Colors.red));
      return tiles;
    }

    return tiles;

//      String point2DTable = "point2d";
//      assertTrue(db.hasSpatialIndex(point2DTable));
//      GeometryColumn geometryColumn = db.getGeometryColumnsForTable(point2DTable);
//      assertEquals("geom", geometryColumn.geometryColumnName);
//      assertEquals(0, geometryColumn.srid);
//      List<Geometry> geometries = db.getGeometriesIn(point2DTable, (Envelope) null);
//      geometries.removeIf(g -> g == null);
//      assertEquals(1, geometries.size());
//      assertEquals("POINT (1 2)", geometries.get(0).toText());
//
//      String line2DTable = "linestring2d";
//      assertTrue(db.hasSpatialIndex(line2DTable));
//      geometryColumn = db.getGeometryColumnsForTable(line2DTable);
//      assertEquals("geom", geometryColumn.geometryColumnName);
//      assertEquals(4326, geometryColumn.srid);
//      geometries = db.getGeometriesIn(line2DTable, (Envelope) null);
//      geometries.removeIf(g -> g == null);
//      assertEquals(1, geometries.size());
//      assertEquals("LINESTRING (1 2, 3 4)", geometries.get(0).toText());
//
//      // with spatial index
//      String polygon2DTable = "polygon2d";
//      assertTrue(db.hasSpatialIndex(polygon2DTable));
//      geometryColumn = db.getGeometryColumnsForTable(polygon2DTable);
//      assertEquals("geom", geometryColumn.geometryColumnName);
//      assertEquals(32631, geometryColumn.srid);
//      geometries = db.getGeometriesIn(polygon2DTable, new Envelope(-1, 11, -1, 11));
//      geometries.removeIf(g -> g == null);
//      assertEquals(1, geometries.size());
//      assertEquals("POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0), (1 1, 1 9, 9 9, 9 1, 1 1))", geometries.get(0).toText());
//
//      // has no spatial index
//      String multipoint2DTable = "multipoint2d";
//      assertFalse(db.hasSpatialIndex(multipoint2DTable));
//      geometries = db.getGeometriesIn(multipoint2DTable, (Envelope) null);
//      geometries.removeIf(g -> g == null);
//      assertEquals(1, geometries.size());
//      assertEquals("MULTIPOINT ((0 1), (2 3))", geometries.get(0).toText());
//
//      String geomcollection2DTable = "geomcollection2d";
//      assertTrue(db.hasSpatialIndex(geomcollection2DTable));
//      geometries = db.getGeometriesIn(geomcollection2DTable, (Envelope) null);
//      geometries.removeIf(g -> g == null);
//      assertEquals(4, geometries.size());
//
//      // with spatial index
//      geometries = db.getGeometriesIn(geomcollection2DTable, new Envelope(9, 11, 9, 11));
//      assertEquals(2, geometries.size());
//
//      String point3DTable = "point3d";
//      assertTrue(db.hasSpatialIndex(point3DTable));
//      FeatureEntry feature = db.feature(point3DTable);
//      assertEquals("POINT".toLowerCase(), feature.getGeometryType().getTypeName().toLowerCase());
//      geometries = db.getGeometriesIn(point3DTable, (Envelope) null);
//      geometries.removeIf(g -> g == null);
//      assertEquals(1, geometries.size());
//
//      // 3D geoms not supported by JTS WKBReader at the time being
//      assertEquals("POINT (1 2)", geometries.get(0).toText());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Test App Geopackage"),
      ),
      body: FutureBuilder<List<Widget>>(
        future: getWidgets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return ListView(
              children: snapshot.data,
            );
          } else {
            // Otherwise, display a loading indicator.
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
