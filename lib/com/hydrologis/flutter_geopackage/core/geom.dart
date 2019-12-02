part of flutter_geopackage;

/// EnvelopeType specified in the header of a Geometry (see Geopackage specs)
class EnvelopeType {
  static const NONE = const EnvelopeType._(0, 0);
  static const XY = const EnvelopeType._(1, 32);
  static const XYZ = const EnvelopeType._(2, 48);
  static const XYM = const EnvelopeType._(3, 48);
  static const XYZM = const EnvelopeType._(4, 64);

  static List<EnvelopeType> get values => [NONE, XY, XYZ, XYM, XYZM];

  final int value;
  final int length;

  const EnvelopeType._(this.value, this.length);

  static EnvelopeType valueOf(int b) {
    return values.firstWhere((v) => v.value == b);
  }
}

/// GeoPackage Binary Type inside Geometry Header Flags.
///
/// @author Niels Charlier
class GeopackageBinaryType {
  static const StandardGeoPackageBinary = const GeopackageBinaryType._(0);
  static const ExtendedGeoPackageBinary = const GeopackageBinaryType._(1);

  static List<GeopackageBinaryType> get values => [StandardGeoPackageBinary, ExtendedGeoPackageBinary];

  final int value;

  const GeopackageBinaryType._(this.value);

  static GeopackageBinaryType valueOf(int b) {
    return values.firstWhere((v) => v.value == b);
  }
}

/// The Geopackage Geometry BLOB Header Flags (see Geopackage specs).
///
/// @author Justin Deoliveira
/// @author Niels Charlier
class GeometryHeaderFlags {
  int b;

  static const int MASK_BINARY_TYPE = 0x20; // 00100000
  static const int MASK_EMPTY = 0x10; // 00010000
  static const int MASK_ENVELOPE_IND = 0x0e; // 00001110
  static const int MASK_ENDIANESS = 0x01; // 00000001

  GeometryHeaderFlags(int b) {
    this.b = b;
  }

  EnvelopeType getEnvelopeIndicator() {
    return EnvelopeType.valueOf(((b & MASK_ENVELOPE_IND) >> 1));
  }

  void setEnvelopeIndicator(EnvelopeType e) {
    b |= ((e.value << 1) & MASK_ENVELOPE_IND);
  }

  Endian getEndianess() {
    var endian = (b & MASK_ENDIANESS) == 1 ? Endian.little : Endian.big;
    return endian;
  }

  void setEndianess(Endian endian) {
    int e = (endian == Endian.little ? 1 : 0);
    b |= (e & MASK_ENDIANESS);
  }

  bool isEmpty() {
    return (b & MASK_EMPTY) == MASK_EMPTY;
  }

  void setEmpty(bool empty) {
    if (empty) {
      b |= MASK_EMPTY;
    } else {
      b &= ~MASK_EMPTY;
    }
  }

  GeopackageBinaryType getBinaryType() {
    return GeopackageBinaryType.valueOf(((b & MASK_BINARY_TYPE) >> 1));
  }

  void setBinaryType(GeopackageBinaryType binaryType) {
    b |= ((binaryType.value << 1) & MASK_BINARY_TYPE);
  }

  int toByte() {
    return b;
  }
}

/// The Geopackage Geometry BLOB Header (see Geopackage specs).
///
/// @author Justin Deoliveira
/// @author Niels Charlier
class GeometryHeader {
  int version;
  GeometryHeaderFlags flags;
  int srid;
  Envelope envelope;

  int getVersion() {
    return version;
  }

  void setVersion(int version) {
    this.version = version;
  }

  GeometryHeaderFlags getFlags() {
    return flags;
  }

  void setFlags(GeometryHeaderFlags flags) {
    this.flags = flags;
  }

  int getSrid() {
    return srid;
  }

  void setSrid(int srid) {
    this.srid = srid;
  }

  Envelope getEnvelope() {
    return envelope;
  }

  void setEnvelope(Envelope envelope) {
    this.envelope = envelope;
  }
}

/// Translates a GeoPackage geometry BLOB to a vividsolutions Geometry.
///
///
/// To get from sql resultset:
/// List<int> geomBytes = rs.getBytes(index);
///   if (geomBytes != null) {
///   Geometry geometry = new GeoPkgGeomReader(geomBytes).get();
///
/// @author Justin Deoliveira
/// @author Niels Charlier
class GeoPkgGeomReader {
  static final GeometryFactory DEFAULT_GEOM_FACTORY = new GeometryFactory.defaultPrecision();

  Uint8List _dataBuffer;

  GeometryHeader _header;

  Geometry _geometry;

  GeometryFactory _geomFactory = DEFAULT_GEOM_FACTORY;

  ByteOrderDataInStream _din;

  String geometryType;

  GeoPkgGeomReader(List<int> ins) {
    if (ins is Uint8List) {
      _dataBuffer = ins;
    } else {
      _dataBuffer = Uint8List.fromList(ins);
    }
  }

  GeometryHeader _getHeader() {
    if (_header == null) {
      _header = readHeader();
    }
    return _header;
  }

  Geometry get() {
    if (_header == null) {
      _header = readHeader();
    }
    if (_geometry == null) {
      _geometry = _read();
    }
    return _geometry;
  }


  Envelope getEnvelope() {
    if (_getHeader().getFlags().getEnvelopeIndicator() == EnvelopeType.NONE) {
      return get().getEnvelopeInternal();
    } else {
      return _getHeader().getEnvelope();
    }
  }

  Geometry _read() {
    WKBReader wkbReader = new WKBReader.withFactory(_geomFactory);
    Geometry g = wkbReader.read(_dataBuffer.sublist(_din.readOffset));
    g.setSRID(_header.getSrid());
    return g;
  }

   /*
    * OptimizedGeoPackageBinary {
    * byte[3] magic = 0x47504230; // 'GPB'
    * byte flags;                 // see flags layout below
    * unit32 srid;
    * double[] envelope;          // see flags envelope contents indicator code below
    * WKBGeometry geometry;       // per OGC 06-103r4 clause 8
    *
    *
    * flags layout:
    *   bit     7       6       5       4       3       2       1       0
    *   use     -       -       X       Y       E       E       E       B

    *   use:
    *   X: GeoPackageBinary type (0: StandardGeoPackageBinary, 1: ExtendedGeoPackageBinary)
    *   Y: 0: non-empty geometry, 1: empty geometry
    *
    *   E: envelope contents indicator code (3-bit unsigned integer)
    *     value |                    description                               | envelope length (bytes)
    *       0   | no envelope (space saving slower indexing option)            |      0
    *       1   | envelope is [minx, maxx, miny, maxy]                         |      32
    *       2   | envelope is [minx, maxx, miny, maxy, minz, maxz]             |      48
    *       3   | envelope is [minx, maxx, miny, maxy, minm, maxm]             |      48
    *       4   | envelope is [minx, maxx, miny, maxy, minz, maxz, minm, maxm] |      64
    *   B: byte order for header values (1-bit Boolean)
    *       0 = Big Endian   (most significant bit first)
    *       1 = Little Endian (least significant bit first)
    */
  GeometryHeader readHeader() {
    GeometryHeader h = new GeometryHeader();

// read first 4 bytes
// TODO: something with the magic number
//    byte[] buf = new byte[4];
    _din = ByteOrderDataInStream(_dataBuffer);
    var b1 = _din.readByte();
    var b2 = _din.readByte();
    var b3 = _din.readByte();
    int flag = _din.readByte();

// next byte flags
    h.setFlags(new GeometryHeaderFlags(flag)); //(byte) buf[3]));

// set endianess
//    ByteOrderDataInStream din = new ByteOrderDataInStream(input);
    _din.setOrder(h.getFlags().getEndianess());

// read the srid
    h.setSrid(_din.readInt());

// read the envelope
    EnvelopeType envelopeIndicator = h.getFlags().getEnvelopeIndicator();
    if (envelopeIndicator != EnvelopeType.NONE) {
      double x1 = _din.readDouble();
      double x2 = _din.readDouble();
      double y1 = _din.readDouble();
      double y2 = _din.readDouble();

      if (envelopeIndicator.value > 1) {
// 2 = minz,maxz; 3 = minm,maxm - we ignore these for now
        _din.readDouble();
        _din.readDouble();
      }

      if (envelopeIndicator.value > 3) {
// 4 = minz,maxz,minm,maxm - we ignore these for now
        _din.readDouble();
        _din.readDouble();
      }

      h.setEnvelope(new Envelope(x1, x2, y1, y2));
    }
    return h;
  }
}
