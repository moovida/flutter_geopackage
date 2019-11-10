import 'package:flutter_geopackage/flutter_geopackage.dart';
import 'package:flutter/material.dart';
import 'geopackage_test_view.dart';



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
    // If the Future is complete, display the preview.
    return MaterialApp(
      title: "Test Geopackage App",
      debugShowMaterialGrid: false,
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      home: GeopackageTestView(),
    );
  }
}

