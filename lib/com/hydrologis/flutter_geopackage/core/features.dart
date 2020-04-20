import 'package:flutter_geopackage/com/hydrologis/flutter_geopackage/core/entries.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';

/// Feature entry in a geopackage.
///
/// <p>This class corresponds to the "geometry_columns" table.
///
/// @author Justin Deoliveira, OpenGeo
/// @author Niels Charlier
class FeatureEntry extends Entry {
  EGeometryType geometryType;
  bool z = false;
  bool m = false;
  String geometryColumn;

  FeatureEntry() {
    setDataType(DataType.Feature);
  }

  String getGeometryColumn() {
    return geometryColumn;
  }

  void setGeometryColumn(String geometryColumn) {
    this.geometryColumn = geometryColumn;
  }

  EGeometryType getGeometryType() {
    return geometryType;
  }

  void setGeometryType(EGeometryType geometryType) {
    this.geometryType = geometryType;
  }

  void init(Entry e) {
    super.init(e);
    if (e is FeatureEntry) {
      setGeometryColumn(e.getGeometryColumn());
      setGeometryType(e.getGeometryType());
      setZ(e.isZ());
      setM(e.isM());
    }
  }

  bool isZ() {
    return z;
  }

  void setZ(bool z) {
    this.z = z;
  }

  bool isM() {
    return m;
  }

  void setM(bool m) {
    this.m = m;
  }

  FeatureEntry copy() {
    FeatureEntry e = new FeatureEntry();
    e.init(this);
    return e;
  }
}
