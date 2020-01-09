import 'package:flutter/material.dart';
import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'dart:io';

const VECTORPATH = "/storage/emulated/0/gdal_sample.gpkg";
const TILESPATH = "/storage/emulated/0/tiles_3857.gpkg";

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
    List<Widget> widgets= [];

    List<Widget> vector = await getVectorWidgets();
    widgets.addAll(vector);

    List<Widget> tiles = await getTilesWidgets();
    widgets.addAll(tiles);

    return widgets;
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

  Future<List<Widget>> getTilesWidgets() async {
    List<Widget> tiles = [];

    GeopackageDb db;
    try {
      db = GeopackageDb(TILESPATH);
      db.doRtreeTestCheck = false;
      db.forceMobileCompatibility = false;
      try {
        tiles.add(_addInfoTile("Open db", "Try opening: " + TILESPATH));
        await db.openOrCreate();
        tiles.add(_addInfoTile("Open db", "Done"));
      } catch (e) {
        tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }
      try {
        List<TileEntry> tilesList = await db.tiles();
        tiles.add(_addInfoTile("Tiles tables count", "found tiles tables: ${tilesList.length}"));
      } catch (e) {
        tiles.add(_addInfoTile("Tiles tables count", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }
      try {
        TileEntry entry = await db.tile('tiles');
        List<TileMatrix> tileMatricies = entry.getTileMatricies();
        tiles.add(_addInfoTile("Tile matrix levels", "level count: ${tileMatricies.length}"));
        tileMatricies.forEach((tm){
          var zl = tm.zoomLevel;
          var cols = tm.matrixWidth;
          var rows = tm.matrixHeight;
          var tw = tm.tileWidth;
          var th = tm.tileHeight;
          var xPixelSize = tm.xPixelSize;
          var yPixelSize = tm.yPixelSize;

          tiles.add(_addInfoTile("Tile level Z=$zl", "cols=$cols; rows=$rows; tw=$tw; th=$th; xres=$xPixelSize; yres=$yPixelSize"));
        });

      } catch (e) {
        tiles.add(_addInfoTile("Tile matrix levels", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }
      try {
        List<int> tileBytes = await db.getTile('tiles', 0, 0, 1);
        tiles.add(_addInfoTile("Read tile image", "tile bytes size at 0,0,1: ${tileBytes.length}"));
      } catch (e) {
        tiles.add(_addInfoTile("Read tile image", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }
    } finally {
      db?.close();
    }

    return tiles;
  }

  Future<List<Widget>> getVectorWidgets() async {
    List<Widget> tiles = [];

    GeopackageDb db;
    try {
      db = GeopackageDb(VECTORPATH);
      db.doRtreeTestCheck = false;
      db.forceMobileCompatibility = false;
      try {
        tiles.add(_addInfoTile("Open db", "Try opening: " + VECTORPATH));
        await db.openOrCreate();
        tiles.add(_addInfoTile("Open db", "Done"));
      } catch (e) {
        tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      tiles.add(_addInfoTile("General info", "Sqlite version supports spatial index (rtree): ${db.supportsSpatialIndex}\nGeopackage version: ${db.version}"));

      try {
        Map<String, List<String>> tablesMap = await db.getTablesMap(false);
        List<String> tables = tablesMap[GeopackageTableNames.USERDATA];
        assert(tables.length == 16);
        tiles.add(_addInfoTile("Check tables", "Found ${tables.length} tables."));
      } catch (e) {
        tiles.add(_addInfoTile("Check tables", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        String point2DTable = "point2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(point2DTable);

        GeometryColumn geometryColumn = await db.getGeometryColumnsForTable(point2DTable);

        List<Geometry> geometries = await db.getGeometriesIn(point2DTable);
        geometries.removeWhere((g) => g == null);

        assert(1 == geometries.length);
        assert("POINT (1 2)" == geometries[0].toText());

        tiles.add(_addInfoTile(
            "Table point2d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Geometry col name (expected: geom): ${geometryColumn.geometryColumnName} \n" + //
                "SRID (expected 0): ${geometryColumn.srid} \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table point2d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        String line2DTable = "linestring2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(line2DTable);

        GeometryColumn geometryColumn = await db.getGeometryColumnsForTable(line2DTable);
        assert(4326 == geometryColumn.srid);
        List<Geometry> geometries = await db.getGeometriesIn(line2DTable);
        geometries.removeWhere((g) => g == null);
        assert(1 == geometries.length);
        assert("LINESTRING (1 2, 3 4)" == geometries[0].toText());

        tiles.add(_addInfoTile(
            "Table linestring2d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Geometry col name (expected: geom): ${geometryColumn.geometryColumnName} \n" + //
                "SRID (expected 4326): ${geometryColumn.srid} \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table linestring2d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        // with spatial index
        String polygon2DTable = "polygon2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(polygon2DTable);
        GeometryColumn geometryColumn = await db.getGeometryColumnsForTable(polygon2DTable);
        assert(32631 == geometryColumn.srid);
        List<Geometry> geometries = await db.getGeometriesIn(polygon2DTable);
        geometries.removeWhere((g) => g == null);

        assert(1 == geometries.length);
        assert("POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0), (1 1, 1 9, 9 9, 9 1, 1 1))" == geometries[0].toText());

        tiles.add(_addInfoTile(
            "Table polygon2d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Geometry col name (expected: geom): ${geometryColumn.geometryColumnName} \n" + //
                "SRID (expected 32631): ${geometryColumn.srid} \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table polygon2d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        // no spatial index
        String multipoint2DTable = "multipoint2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(multipoint2DTable);
        assert(!hasSpatialIndex);
        List<Geometry> geometries = await db.getGeometriesIn(multipoint2DTable);
        geometries.removeWhere((g) => g == null);

        assert(1 == geometries.length);
        assert("MULTIPOINT ((0 1), (2 3))" == geometries[0].toText());

        tiles.add(_addInfoTile(
            "Table multipoint2d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table multipoint2d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        String geomcollection2DTable = "geomcollection2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(geomcollection2DTable);
        assert(hasSpatialIndex);

        List<Geometry> geometries = await db.getGeometriesIn(geomcollection2DTable);
        geometries.removeWhere((g) => g == null);
        assert(4 == geometries.length);

        // using the spatial index (or just bounds if no index supported)
        var env = Envelope(9, 11, 9, 11);
        List<Geometry> geometriesE = await db.getGeometriesIn(geomcollection2DTable, envelope: env);
        assert(2 == geometriesE.length);

        Geometry geom = WKTReader().read("POLYGON ((2.65 5.3, 4.875 3.7, 2.9 5.65, 2.65 5.3))");
        List<Geometry> geometriesPol = await db.getGeometriesIntersecting(geomcollection2DTable, geometry: geom);
        assert(1 == geometriesPol.length);

        tiles.add(_addInfoTile(
            "Table geomcollection2d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Found ${geometriesE.length} geometries in $env. \n" + //
                "Found ${geometriesPol.length} geometries intersecting $geom. \n\n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table geomcollection2d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }

      try {
        String point3DTable = "point3d";
        bool hasSpatialIndex = await db.hasSpatialIndex(point3DTable);
        assert(hasSpatialIndex);

        List<Geometry> geometries = await db.getGeometriesIn(point3DTable);
        geometries.removeWhere((g) => g == null);
        assert(1 == geometries.length);
        assert("POINT (1 2)" == geometries[0].toText());

        tiles.add(_addInfoTile(
            "Table point3d",
            "Has Spatial index: $hasSpatialIndex \n" + //
                "Found ${geometries.length} geometries. \n" + //
                "Geometry: " +
                geometries[0].toText() //
            ));
      } catch (e) {
        tiles.add(_addInfoTile("Table point3d", "ERROR: ${e.toString()}", color: Colors.red));
        return tiles;
      }
    } finally {
      db?.close();
    }
    return tiles;
  }
}
