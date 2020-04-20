part of flutter_geopackage;

class DataType {
  static const Feature = const DataType._("features");
  static const Tile = const DataType._("tiles");

  final String value;

  const DataType._(this.value);

  static DataType of(String type) {
    if (type == Feature.value) {
      return Feature;
    } else if (type == Tile.value) {
      return Tile;
    } else {
      return null;
    }
  }
}

/// Entry in a geopackage.
///
/// <p>This class corresponds to the "geopackage_contents" table.
///
/// @author Justin Deoliveira, OpenGeo
class Entry {
  String tableName;
  DataType dataType;
  String identifier;
  String description;
  Envelope bounds;
  int srid;

  String getTableName() {
    return tableName;
  }

  void setTableName(String tableName) {
    this.tableName = tableName;
  }

  DataType getDataType() {
    return dataType;
  }

  void setDataType(DataType dataType) {
    this.dataType = dataType;
  }

  String getIdentifier() {
    return identifier;
  }

  void setIdentifier(String identifier) {
    this.identifier = identifier;
  }

  String getDescription() {
    return description;
  }

  void setDescription(String description) {
    this.description = description;
  }

  Envelope getBounds() {
    return bounds;
  }

  void setBounds(Envelope bounds) {
    this.bounds = bounds;
  }

  int getSrid() {
    return srid;
  }

  void setSrid(int srid) {
    this.srid = srid;
  }

  void init(Entry e) {
    setDescription(e.getDescription());
    setIdentifier(e.getIdentifier());
    setDataType(e.getDataType());
    setBounds(e.getBounds());
    setSrid(e.getSrid());
    setTableName(e.getTableName());
  }

  Entry copy() {
    Entry e = new Entry();
    e.init(this);
    return e;
  }
}
