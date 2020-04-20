import 'package:dart_jts/dart_jts.dart' as JTS;
import 'package:flutter/material.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:geopackage_example/image_provider.dart';
import 'package:latlong/latlong.dart';
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
  List<LazyGpkgTile> allLazyTiles;
  List<JTS.Geometry> placesGeoms;
  List<JTS.Geometry> countriesGeoms;

  final job = AssetCopyJob(
    assets: [
      'testdbs/earth.gpkg',
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
        await loadData();
        _currentState = states.LOADED;
        setState(() {});
      }).catchError((e, stack) {
        print("Error while copying:\n$e");
        print(stack);
        _currentState = states.FILECOPYERROR;
        setState(() {});
      });
    }
  }

  Future loadData() async {
    final files = await job.future;
    if (files[0] == null) throw job.errors[0];
    var earthPath = files[0].path;

    var ch = ConnectionsHandler();

    var db = await ch.open(earthPath);
    db.forceRasterMobileCompatibility = false;

    // load tiles
    var tileEntry = db.tile("clouds");
    TilesFetcher fetcher = TilesFetcher(tileEntry);
    allLazyTiles = fetcher.getAllLazyTiles(db);

    // load places
    var dataEnv = JTS.Envelope(-9, 22, 35, 63);
    placesGeoms =
        db.getGeometriesIn("places", userDataField: "name", envelope: dataEnv);

    // load countries
    countriesGeoms =
        db.getGeometriesIn("countries", envelope: dataEnv);
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
                  : getMap(),
    );
  }

  Widget getMap() {
    var overlayImages = allLazyTiles.map((lt) {
      var minX = lt.tileBoundsLatLong.getMinX();
      var minY = lt.tileBoundsLatLong.getMinY();
      var maxX = lt.tileBoundsLatLong.getMaxX();
      var maxY = lt.tileBoundsLatLong.getMaxY();

      return OverlayImage(
        bounds: LatLngBounds(LatLng(minY, minX), LatLng(maxY, maxX)),
        opacity: 0.7,
        imageProvider: GeopackageImageProvider(lt),
      );
    }).toList();

    Widget circle = new Container(
      width: 10.0,
      height: 10.0,
      decoration: new BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
    );
    var markers = placesGeoms.map((g) {
      var c = g.getCoordinate();
      var name = g.getUserData().toString();
      return Marker(
        width: 200.0,
        height: 80.0,
        anchorPos: AnchorPos.align(AnchorAlign.right),
        point: new LatLng(c.y, c.x),
        builder: (ctx) => new Row(
          children: <Widget>[
            circle,
            Stack(
              children: <Widget>[
                Text(
                  name,
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: Colors.red,
                  ),
                ),
              ],
            )
          ],
        ),
      );
    }).toList();

    List<Polygon> polygons = [];
    Color strokeColor = Colors.green;
    Color fillColor = Colors.green.withAlpha(70);
    countriesGeoms.forEach((polyGeom) {
      for (int i = 0; i < polyGeom.getNumGeometries(); i++) {
        try {
          var geometryN = polyGeom.getGeometryN(i);
          List<LatLng> polyPoints =
              geometryN.getCoordinates().map((c) => LatLng(c.y, c.x)).toList();
          polygons.add(
            Polygon(
              points: polyPoints,
              borderStrokeWidth: 3,
              borderColor: strokeColor,
              color: fillColor,
            ),
          );
        } catch (e) {}
      }
    });

    return FlutterMap(
      options: MapOptions(
        center: LatLng(46, 11),
        zoom: 4.0,
      ),
      layers: [
        TileLayerOptions(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c']),
        // OverlayImageLayerOptions(overlayImages: overlayImages),
        PolygonLayerOptions(
          polygons: polygons,
        ),
        MarkerLayerOptions(
          markers: markers,
        ),
      ],
    );
  }
}
