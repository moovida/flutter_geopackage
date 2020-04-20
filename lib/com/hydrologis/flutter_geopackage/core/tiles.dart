import 'package:dart_jts/dart_jts.dart';
import 'package:flutter_geopackage/com/hydrologis/flutter_geopackage/core/entries.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';

/// Tiles Entry inside a GeoPackage.
///
/// @author Justin Deoliveira
/// @author Niels Charlier
/// @author Andrea Antonello (www.hydrologis.com)
class TileEntry extends Entry {
  List<TileMatrix> tileMatricies = [];

  Envelope tileMatrixSetBounds;

  TileEntry() {
    setDataType(DataType.Tile);
  }

  List<TileMatrix> getTileMatricies() {
    return tileMatricies;
  }

  void setTileMatricies(List<TileMatrix> tileMatricies) {
    this.tileMatricies = tileMatricies;
  }

  void init(Entry e) {
    super.init(e);
    TileEntry te = e as TileEntry;
    setTileMatricies(te.getTileMatricies());
    this.tileMatrixSetBounds = te.tileMatrixSetBounds == null
        ? null
        : new Envelope.fromEnvelope(te.tileMatrixSetBounds);
  }

  /// Returns the tile matrix set bounds. The bounds are expressed in the same CRS as the entry,
  /// but they might differ in extent (if null, then the tile matrix bounds are supposed to be the
  /// same as the entry)
  Envelope getTileMatrixSetBounds() {
    return tileMatrixSetBounds != null ? tileMatrixSetBounds : bounds;
  }

  void setTileMatrixSetBounds(Envelope tileMatrixSetBounds) {
    this.tileMatrixSetBounds = tileMatrixSetBounds;
  }
}

/// A TileMatrix inside a Geopackage. Corresponds to the gpkg_tile_matrix table.
///
/// @author Justin Deoliveira
/// @author Niels Charlier
class TileMatrix {
  int zoomLevel;
  int matrixWidth, matrixHeight;
  int tileWidth, tileHeight;
  double xPixelSize;
  double yPixelSize;
  bool tiles;

  TileMatrix(this.zoomLevel, this.matrixWidth, this.matrixHeight,
      this.tileWidth, this.tileHeight, this.xPixelSize, this.yPixelSize);

  int getZoomLevel() {
    return zoomLevel;
  }

  void setZoomLevel(int zoomLevel) {
    this.zoomLevel = zoomLevel;
  }

  int getMatrixWidth() {
    return matrixWidth;
  }

  void setMatrixWidth(int matrixWidth) {
    this.matrixWidth = matrixWidth;
  }

  int getMatrixHeight() {
    return matrixHeight;
  }

  void setMatrixHeight(int matrixHeight) {
    this.matrixHeight = matrixHeight;
  }

  int getTileWidth() {
    return tileWidth;
  }

  void setTileWidth(int tileWidth) {
    this.tileWidth = tileWidth;
  }

  int getTileHeight() {
    return tileHeight;
  }

  void setTileHeight(int tileHeight) {
    this.tileHeight = tileHeight;
  }

  double getXPixelSize() {
    return xPixelSize;
  }

  void setXPixelSize(double xPixelSize) {
    this.xPixelSize = xPixelSize;
  }

  double getYPixelSize() {
    return yPixelSize;
  }

  void setYPixelSize(double yPixelSize) {
    this.yPixelSize = yPixelSize;
  }

  bool hasTiles() {
    return tiles;
  }

  void setTiles(bool tiles) {
    this.tiles = tiles;
  }

  String toString() {
    return "TileMatrix [zoomLevel=$zoomLevel, matrixWidth=" +
        "$matrixWidth , matrixHeight=$matrixHeight, tileWidth=" +
        "$tileWidth , tileHeight=$tileHeight, xPixelSize=" +
        "$xPixelSize, yPixelSize=$yPixelSize, tiles=$tiles]";
  }
}

class TilesFetcher {
  TileEntry tileEntry;
  String tableName;
  int zoomLevel;
  List<TileMatrix> tileMatricies;

  double deltaX;
  double deltaY;
  double tileSetMinX;
  double tileSetMaxY;

  int xPixels;
  int yPixels;

  TilesFetcher(this.tileEntry, {this.zoomLevel}) {
    tileMatricies = tileEntry.getTileMatricies();
    if (tileMatricies.isEmpty) {
      throw StateError("No tile matrices available.");
    }
    TileMatrix tileMatrix = tileMatricies.last;
    if (zoomLevel != null) {
      tileMatrix =
          tileMatricies.firstWhere((tm) => tm.getZoomLevel() == zoomLevel);
    }
    zoomLevel = tileMatrix.zoomLevel;

    if (tileMatrix == null) {
      throw StateError("No tile matrix found for given zoomlevel.");
    }
    var matrixWidth = tileMatrix.getMatrixWidth();
    var matrixHeight = tileMatrix.getMatrixHeight();

    var tileMatrixSetBounds = tileEntry.getTileMatrixSetBounds();

    deltaX = tileMatrixSetBounds.getWidth() / matrixWidth;
    deltaY = tileMatrixSetBounds.getHeight() / matrixHeight;

    tileSetMinX = tileMatrixSetBounds.getMinX();
    tileSetMaxY = tileMatrixSetBounds.getMaxY();

    tableName = tileEntry.getTableName();

    xPixels = tileMatrix.getTileWidth();
    yPixels = tileMatrix.getTileHeight();
  }

  Envelope getTileBounds(int xTile, int yTile) {
    double minX = tileSetMinX + deltaX * xTile;
    double maxX = minX + deltaX;

    double maxY = tileSetMaxY - deltaY * yTile;
    double minY = maxY - deltaY;

    return Envelope(minX, maxX, minY, maxY);
  }

  List<int> getTileIndex(double lon, double lat) {}

  GpkgTile getTile(GeopackageDb db, int xTile, int yTile) {
    var tileBounds = getTileBounds(xTile, yTile);

    List<int> tileBytes = db.getTileDirect(tableName, xTile, yTile, zoomLevel);

    GpkgTile tile = GpkgTile()
      ..tileBoundsLatLong = tileBounds
      ..tileImageBytes = tileBytes
      ..xTile = xTile
      ..yTile = yTile
      ..xPixels = xPixels
      ..yPixels = yPixels;
    return tile;
  }
}

class GpkgTile {
  Envelope tileBoundsLatLong;

  int xTile;
  int yTile;
  int xPixels;
  int yPixels;

  List<int> tileImageBytes;
}
