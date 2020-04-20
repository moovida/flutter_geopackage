import 'package:dart_jts/dart_jts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:flutter_map/plugin_api.dart';
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
  List<Widget> _widgets;

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
        _currentState = states.LOADED;

        await loadData();
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
    GeopackageDb db = await ch.open(earthPath);
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
    var overlayImages = <OverlayImage>[
      OverlayImage(
          bounds: LatLngBounds(LatLng(51.5, -0.09), LatLng(48.8566, 2.3522)),
          opacity: 0.8,
          imageProvider: NetworkImage(
              'https://images.pexels.com/photos/231009/pexels-photo-231009.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=300&w=600')),
    ];

    return FlutterMap(
      options: MapOptions(
        center: LatLng(51.5, -0.09),
        zoom: 6.0,
      ),
      layers: [
        TileLayerOptions(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c']),
        OverlayImageLayerOptions(overlayImages: overlayImages)
      ],
    );
  }
}
