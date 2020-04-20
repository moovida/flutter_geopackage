part of flutter_geopackage;

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

  int matrixWidth;
  int matrixHeight;

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

    matrixWidth = tileMatrix.getMatrixWidth();
    matrixHeight = tileMatrix.getMatrixHeight();

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

  LazyGpkgTile getLazyTile(GeopackageDb db, int xTile, int yTile) {
    var tileBounds = getTileBounds(xTile, yTile);

    LazyGpkgTile tile = LazyGpkgTile()
      ..tableName = tableName
      ..db = db
      ..tileBoundsLatLong = tileBounds
      ..xTile = xTile
      ..yTile = yTile
      ..zoomLevel = zoomLevel
      ..xPixels = xPixels
      ..yPixels = yPixels;
    return tile;
  }

  List<LazyGpkgTile> getAllLazyTiles(GeopackageDb db) {
    var env = Envelope(-180, 180, -90, 90);
    List<LazyGpkgTile> tiles = [];
    for (var x = 0; x < matrixWidth; x++) {
      for (var y = 0; y < matrixHeight; y++) {
        var lazyTile = getLazyTile(db, x, y);
        if (lazyTile != null && env.coversEnvelope(lazyTile.tileBoundsLatLong))
          tiles.add(lazyTile);
      }
    }
    return tiles;
  }
}

/// A lazy loading geopackage tile.
class LazyGpkgTile {
  String tableName;
  Envelope tileBoundsLatLong;

  int xTile;
  int yTile;
  int zoomLevel;
  int xPixels;
  int yPixels;

  List<int> tileImageBytes;
  GeopackageDb db;

  fetch() {
    if (db != null)
      tileImageBytes = db.getTileDirect(tableName, xTile, yTile, zoomLevel);
  }

  @override
  String toString() {
    return "Tile of $tableName: x=$xTile, y=$yTile, z=$zoomLevel, loaded=${tileImageBytes != null}";
  }

  @override
  bool operator ==(Object other) =>
      other is LazyGpkgTile &&
      other.tableName == tableName &&
      other.xTile == xTile &&
      other.yTile == yTile &&
      other.zoomLevel == zoomLevel;

  @override
  int get hashCode => hashObjects([tableName, xTile, yTile, zoomLevel]);
}

/// Generates a hash code for multiple [objects].
int hashObjects(Iterable objects) =>
    _finish(objects.fold(0, (h, i) => _combine(h, i.hashCode)));

int _combine(int hash, int value) {
  hash = 0x1fffffff & (hash + value);
  hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
  return hash ^ (hash >> 6);
}

int _finish(int hash) {
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash = hash ^ (hash >> 11);
  return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
}
