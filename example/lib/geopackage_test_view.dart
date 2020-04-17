import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:permission_handler/permission_handler.dart';

import 'file_copy_job.dart';

class GeopackageTestView extends StatefulWidget {
  GeopackageTestView({Key key}) : super(key: key);

  @override
  _GeopackageTestViewState createState() => _GeopackageTestViewState();
}

enum states {
  STARTUP,
  LOADED,
  PREMISSIONERROR,
  FILECOPYERROR,
}

class _GeopackageTestViewState extends State<GeopackageTestView> {
  /// Loading state: 0=startuop, 1=loaded, -1=no storage permission
  states _currentState = states.STARTUP;
  List<Widget> _widgets;

  final job = AssetCopyJob(
    assets: [
      'testdbs/gdal_sample.gpkg',
      'testdbs/tiles_3857.gpkg',
    ],
    overwrite: false,
  );

  @override
  void initState() {
    super.initState();

    init();
  }

  /// do initial configuration work
  Future init() async {
    var storagePermission = await _checkStoragePermissions();
    if (!storagePermission) {
      _currentState = states.PREMISSIONERROR;
    } else {
      print("copying gpkg files...");
      job.future.then((_) async {
        print("copying done");
        _currentState = states.LOADED;

        _widgets = await getWidgets();
        setState(() {});
      }).catchError((e, stack) {
        print("Error while copying:\n$e");
        print(stack);
        _currentState = states.FILECOPYERROR;
        setState(() {});
      });
    }
  }

  Future<bool> _checkStoragePermissions() async {
    PermissionStatus permission = await PermissionHandler()
        .checkPermissionStatus(PermissionGroup.storage);
    if (permission != PermissionStatus.granted) {
      print("Storage permission is not granted.");
      Map<PermissionGroup, PermissionStatus> permissionsMap =
          await PermissionHandler()
              .requestPermissions([PermissionGroup.storage]);
      if (permissionsMap[PermissionGroup.storage] != PermissionStatus.granted) {
        print("Unable to grant permission: ${PermissionGroup.storage}");
        return false;
      }
    }
    print("Storage permission granted.");
    return true;
  }

  Future<String> _getVectorPath() async {
    final files = await job.future;
    if (files[0] == null) throw job.errors[0];
    return files[0].path;
  }

  Future<String> _getTilesPath() async {
    final files = await job.future;
    if (files[1] == null) throw job.errors[1];
    return files[1].path;
  }

  Widget _addInfoTile(String title, String message, {color: Colors.white}) {
    return Container(
      color: color,
      child: ListTile(
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }

  Widget _addMultiInfoTile(String title, List<String> messages,
      {color: Colors.white}) {
    return Container(
      color: color,
      child: ListTile(
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: messages.map((str) => Text(str)).toList(),
        ),
      ),
    );
  }

  Future<List<Widget>> getWidgets() async {
    List<Widget> widgets = [];

    var ch = ConnectionsHandler();
    var reports = ch.getOpenDbReport();

    var widget =
        _addMultiInfoTile("Db Handler Report", reports, color: Colors.orange);
    widgets.add(widget);

    List<Widget> vector = await getVectorWidgets();
    widgets.addAll(vector);

    reports = ch.getOpenDbReport();
    widget =
        _addMultiInfoTile("Db Handler Report", reports, color: Colors.orange);
    widgets.add(widget);

    List<Widget> tiles = await getTilesWidgets();
    widgets.addAll(tiles);

    reports = ch.getOpenDbReport();
    widget =
        _addMultiInfoTile("Db Handler Report", reports, color: Colors.orange);
    widgets.add(widget);

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Test App Geopackage"),
        ),
        body: _currentState == states.STARTUP
            ? Center(child: CircularProgressIndicator())
            : _currentState == states.PREMISSIONERROR
                ? Center(
                    child: Text(
                      "This example app need the storage permission to work.",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : _currentState == states.FILECOPYERROR
                    ? Center(
                        child: Text(
                          "An error occurred while loading the test files.",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : ListView(
                        children: _widgets,
                      ));
  }

  Future<List<Widget>> getTilesWidgets() async {
    List<Widget> tiles = [];

    var ch = ConnectionsHandler();
    // ch.doRtreeCheck = false;
    ch.forceRasterMobileCompatibility = false;

    String tilesPath;
    GeopackageDb db;
    try {
      tilesPath = await _getTilesPath();
      try {
        tiles.add(_addInfoTile("Open db", "Try opening: " + tilesPath));
        db = await ch.open(tilesPath);
        tiles.add(_addInfoTile("Open db", "Done"));
      } catch (e) {
        tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }
      try {
        List<TileEntry> tilesList = await db.tiles();
        tiles.add(_addInfoTile(
            "Tiles tables count", "found tiles tables: ${tilesList.length}"));
      } catch (e) {
        tiles.add(_addInfoTile("Tiles tables count", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }
      try {
        TileEntry entry = await db.tile('tiles');
        List<TileMatrix> tileMatricies = entry.getTileMatricies();
        tiles.add(_addInfoTile(
            "Tile matrix levels", "level count: ${tileMatricies.length}"));
        tileMatricies.forEach((tm) {
          var zl = tm.zoomLevel;
          var cols = tm.matrixWidth;
          var rows = tm.matrixHeight;
          var tw = tm.tileWidth;
          var th = tm.tileHeight;
          var xPixelSize = tm.xPixelSize;
          var yPixelSize = tm.yPixelSize;

          tiles.add(_addInfoTile("Tile level Z=$zl",
              "cols=$cols; rows=$rows; tw=$tw; th=$th; xres=$xPixelSize; yres=$yPixelSize"));
        });
      } catch (e) {
        tiles.add(_addInfoTile("Tile matrix levels", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }
      try {
        List<int> tileBytes = await db.getTile('tiles', 0, 0, 1);
        tiles.add(_addInfoTile("Read tile image",
            "tile bytes size at 0,0,1: ${tileBytes.length}"));
      } catch (e) {
        tiles.add(_addInfoTile("Read tile image", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }
    } catch (e) {
      tiles.add(
          _addInfoTile("Tiles", "ERROR: ${e.toString()}", color: Colors.red));
      return tiles;
    } finally {
      if (tilesPath != null) {
        await ch.close(tilesPath);
      }
    }

    return tiles;
  }

  Future<List<Widget>> getVectorWidgets() async {
    List<Widget> tiles = [];

    var ch = ConnectionsHandler();
    // ch.doRtreeCheck = false;
    ch.forceVectorMobileCompatibility = false;

    String vectorPath;
    GeopackageDb db;
    try {
      vectorPath = await _getVectorPath();
      db = await ch.open(vectorPath);
      try {
        tiles.add(_addInfoTile("Open db", "Try opening: " + vectorPath));
        await db.openOrCreate();
        tiles.add(_addInfoTile("Open db", "Done"));
      } catch (e) {
        tiles.add(_addInfoTile("Open db", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }

      tiles.add(_addInfoTile("General info",
          "Sqlite version supports spatial index (rtree): ${db.supportsSpatialIndex}\nGeopackage version: ${db.version}"));

      try {
        Map<String, List<String>> tablesMap = await db.getTablesMap(false);
        List<String> tables = tablesMap[GeopackageTableNames.USERDATA];
        assert(tables.length == 16);
        tiles.add(
            _addInfoTile("Check tables", "Found ${tables.length} tables."));
      } catch (e) {
        tiles.add(_addInfoTile("Check tables", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }

      try {
        String point2DTable = "point2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(point2DTable);

        GeometryColumn geometryColumn =
            await db.getGeometryColumnsForTable(point2DTable);

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
        tiles.add(_addInfoTile("Table point2d", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }

      try {
        String line2DTable = "linestring2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(line2DTable);

        GeometryColumn geometryColumn =
            await db.getGeometryColumnsForTable(line2DTable);
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
        tiles.add(_addInfoTile("Table linestring2d", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }

      try {
        // with spatial index
        String polygon2DTable = "polygon2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(polygon2DTable);
        GeometryColumn geometryColumn =
            await db.getGeometryColumnsForTable(polygon2DTable);
        assert(32631 == geometryColumn.srid);
        List<Geometry> geometries = await db.getGeometriesIn(polygon2DTable);
        geometries.removeWhere((g) => g == null);

        assert(1 == geometries.length);
        assert(
            "POLYGON ((0 0, 0 10, 10 10, 10 0, 0 0), (1 1, 1 9, 9 9, 9 1, 1 1))" ==
                geometries[0].toText());

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
        tiles.add(_addInfoTile("Table polygon2d", "ERROR: ${e.toString()}",
            color: Colors.red));
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
        tiles.add(_addInfoTile("Table multipoint2d", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }

      try {
        String geomcollection2DTable = "geomcollection2d";
        bool hasSpatialIndex = await db.hasSpatialIndex(geomcollection2DTable);
        assert(hasSpatialIndex);

        List<Geometry> geometries =
            await db.getGeometriesIn(geomcollection2DTable);
        geometries.removeWhere((g) => g == null);
        assert(4 == geometries.length);

        // using the spatial index (or just bounds if no index supported)
        var env = Envelope(9, 11, 9, 11);
        List<Geometry> geometriesE =
            await db.getGeometriesIn(geomcollection2DTable, envelope: env);
        assert(2 == geometriesE.length);

        Geometry geom = WKTReader()
            .read("POLYGON ((2.65 5.3, 4.875 3.7, 2.9 5.65, 2.65 5.3))");
        List<Geometry> geometriesPol = await db
            .getGeometriesIntersecting(geomcollection2DTable, geometry: geom);
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
        tiles.add(_addInfoTile(
            "Table geomcollection2d", "ERROR: ${e.toString()}",
            color: Colors.red));
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
        tiles.add(_addInfoTile("Table point3d", "ERROR: ${e.toString()}",
            color: Colors.red));
        return tiles;
      }
    } catch (e) {
      tiles.add(
          _addInfoTile("Vectors", "ERROR: ${e.toString()}", color: Colors.red));
      return tiles;
    } finally {
      if (vectorPath != null) {
        await ch.close(vectorPath);
      }
    }
    return tiles;
  }
}
