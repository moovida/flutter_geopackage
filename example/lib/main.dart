import 'package:flutter/material.dart';
import 'geopackage_test_view.dart';
import 'package:permission_handler/permission_handler.dart';


void main() => runApp(SmashApp());

class SmashApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return SmashAppState();
  }
}

class SmashAppState extends State<SmashApp> {
  @override
  Widget build(BuildContext context) {

    permissions();

    // If the Future is complete, display the preview.
    return MaterialApp(
      title: "Test Geopackage App",
      debugShowMaterialGrid: false,
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      home: GeopackageTestView(),
    );
  }



  void permissions() async {
    PermissionStatus permission = await PermissionHandler().checkPermissionStatus(PermissionGroup.storage);
    if (permission != PermissionStatus.granted) {
      print("Storage permission is not granted.");
      Map<PermissionGroup, PermissionStatus> permissionsMap = await PermissionHandler().requestPermissions([PermissionGroup.storage]);
      if (permissionsMap[PermissionGroup.storage] != PermissionStatus.granted) {
        print("Unable to grant permission: ${PermissionGroup.storage}");
      }
    }
  }

}

