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
    return (b & MASK_ENDIANESS) == 1 ? Endian.little : Endian.big;
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

/**
 * Translates a GeoPackage geometry BLOB to a vividsolutions Geometry.
 *
 *
 * To get from sql resultset:
 * List<int> geomBytes = rs.getBytes(index);
 *   if (geomBytes != null) {
 *   Geometry geometry = new GeoPkgGeomReader(geomBytes).get();
 *
 * @author Justin Deoliveira
 * @author Niels Charlier
 */
class GeoPkgGeomReader {
  static final GeometryFactory DEFAULT_GEOM_FACTORY = new GeometryFactory.defaultPrecision();

  Uint8List dataBuffer;

  GeometryHeader header = null;

  Geometry geometry = null;

  GeometryFactory geomFactory = DEFAULT_GEOM_FACTORY;

  ByteOrderDataInStream din;

  num simplificationDistance;
  String geometryType;

  GeoPkgGeomReader(List<int> ins) {
    if (ins is Uint8List) {
      dataBuffer = ins;
    } else {
      dataBuffer = Uint8List.fromList(ins);
    }
  }

  GeometryHeader getHeader() {
    if (header == null) {
      header = readHeader();
    }
    return header;
  }

  Geometry get() {
    if (header == null) {
      header = readHeader();
    }

    if (geometry == null) {
      Envelope envelope = header.getEnvelope();
      if (simplificationDistance != null &&
          geometryType != null &&
          header.getFlags().getEnvelopeIndicator() != EnvelopeType.NONE &&
          envelope.getWidth() < simplificationDistance.toDouble() &&
          envelope.getHeight() < simplificationDistance.toDouble()) {
        Geometry simplified = getSimplifiedShape(geometryType, envelope.getMinX(), envelope.getMinY(), envelope.getMaxX(), envelope.getMaxY());
        if (simplified != null) {
          geometry = simplified;
        }
      }

      if (geometry == null) {
        geometry = read();
      }
    }
    return geometry;
  }

  Geometry getSimplifiedShape(String type, double minX, double minY, double maxX, double maxY) {
    CoordinateSequenceFactory csf = geomFactory.getCoordinateSequenceFactory();
    final POINT_TYPE = "Point";
    final MULITPOINT_TYPE = "MultiPoint";
    final LINE_TYPE = "LineString";
    final RING_TYPE = "LinearRing";
    final MULTILINE_TYPE = "MultiLineString";
    final POLYGON_TYPE = "Polygon";
    final MULTIPOLYOGN_TYPE = "MultiPolygon";
    final GEOMETRYCOLLECTION_TYPE = "GeometryCollection";
    if (POINT_TYPE == type) {
      CoordinateSequence cs = createCS(csf, 1, 2);
      cs.setOrdinate(0, 0, (minX + maxX) / 2);
      cs.setOrdinate(0, 1, (minY + maxY) / 2);
      return geomFactory.createPointSeq(cs);
    } else if (MULITPOINT_TYPE == type) {
      Point p = getSimplifiedShape(POINT_TYPE, minX, minY, maxX, maxY);
      return geomFactory.createMultiPoint([p]);
    } else if (LINE_TYPE == type || RING_TYPE == type) {
      CoordinateSequence cs = createCS(csf, 2, 2);
      cs.setOrdinate(0, 0, minX);
      cs.setOrdinate(0, 1, minY);
      cs.setOrdinate(1, 0, maxX);
      cs.setOrdinate(1, 1, maxY);
      return geomFactory.createLineStringSeq(cs);
    } else if (MULTILINE_TYPE == type) {
      LineString ls = getSimplifiedShape(LINE_TYPE, minX, minY, maxX, maxY);
      return geomFactory.createMultiLineString([ls]);
    } else if (POLYGON_TYPE == type) {
      CoordinateSequence cs = createCS(csf, 5, 2);
      cs.setOrdinate(0, 0, minX);
      cs.setOrdinate(0, 1, minY);
      cs.setOrdinate(1, 0, minX);
      cs.setOrdinate(1, 1, maxY);
      cs.setOrdinate(2, 0, maxX);
      cs.setOrdinate(2, 1, maxY);
      cs.setOrdinate(3, 0, maxX);
      cs.setOrdinate(3, 1, minY);
      cs.setOrdinate(4, 0, minX);
      cs.setOrdinate(4, 1, minY);
      LinearRing ring = geomFactory.createLinearRingSeq(cs);
      return geomFactory.createPolygon(ring, null);
    } else if (MULTIPOLYOGN_TYPE == type || GEOMETRYCOLLECTION_TYPE == type) {
      Polygon polygon = getSimplifiedShape(POLYGON_TYPE, minX, minY, maxX, maxY);
      return geomFactory.createMultiPolygon([polygon]);
    } else {
      // don't really know what to do with this case, guessing a type might break expectations
      return null;
    }
  }

  Envelope getEnvelope() {
    if (getHeader().getFlags().getEnvelopeIndicator() == EnvelopeType.NONE) {
      return get().getEnvelopeInternal();
    } else {
      return getHeader().getEnvelope();
    }
  }

  Geometry read() {
    // header must be read!
// read the geometry
    WKBReader wkbReader = new WKBReader.withFactory(geomFactory);
    Geometry g = wkbReader.read(dataBuffer.sublist(din.readOffset));
    g.setSRID(header.getSrid());
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
    din = ByteOrderDataInStream(ByteData.view(dataBuffer.buffer));
    din.readByte();
    din.readByte();
    din.readByte();
    int flag = din.readByte();

// next byte flags
    h.setFlags(new GeometryHeaderFlags(flag)); //(byte) buf[3]));

// set endianess
//    ByteOrderDataInStream din = new ByteOrderDataInStream(input);
    din.setOrder(h.getFlags().getEndianess());

// read the srid
    h.setSrid(din.readInt());

// read the envelope
    EnvelopeType envelopeIndicator = h.getFlags().getEnvelopeIndicator();
    if (envelopeIndicator != EnvelopeType.NONE) {
      double x1 = din.readDouble();
      double x2 = din.readDouble();
      double y1 = din.readDouble();
      double y2 = din.readDouble();

      if (envelopeIndicator.value > 1) {
// 2 = minz,maxz; 3 = minm,maxm - we ignore these for now
        din.readDouble();
        din.readDouble();
      }

      if (envelopeIndicator.value > 3) {
// 4 = minz,maxz,minm,maxm - we ignore these for now
        din.readDouble();
        din.readDouble();
      }

      h.setEnvelope(new Envelope(x1, x2, y1, y2));
    }
    return h;
  }

  /** @return the factory */
  GeometryFactory getFactory() {
    return geomFactory;
  }

  /** @param factory the factory to set */
  void setFactory(GeometryFactory factory) {
    if (factory != null) {
      this.geomFactory = factory;
    }
  }

  void setSimplificationDistance(double simplificationDistance) {
    this.simplificationDistance = simplificationDistance;
  }

  void setGeometryType(String geometryType) {
    this.geometryType = geometryType;
  }

  /**
   * Creates a {@link CoordinateSequence} using the provided factory confirming the provided size
   * and dimension are respected.
   *
   * <p>If the requested dimension is larger than the CoordinateSequence implementation can
   * provide, then a sequence of maximum possible dimension should be created. An error should not
   * be thrown.
   *
   * <p>This method is functionally identical to calling csFactory.create(size,dim) - it contains
   * additional logic to work around a limitation on the commonly used
   * CoordinateArraySequenceFactory.
   *
   * @param size the number of coordinates in the sequence
   * @param dimension the dimension of the coordinates in the sequence
   */
  static CoordinateSequence createCS(CoordinateSequenceFactory csFactory, int size, int dimension) {
    // the coordinates don't have measures
    return createCSMEas(csFactory, size, dimension, 0);
  }

  /**
   * Creates a {@link CoordinateSequence} using the provided factory confirming the provided size
   * and dimension are respected.
   *
   * <p>If the requested dimension is larger than the CoordinateSequence implementation can
   * provide, then a sequence of maximum possible dimension should be created. An error should not
   * be thrown.
   *
   * <p>This method is functionally identical to calling csFactory.create(size,dim) - it contains
   * additional logic to work around a limitation on the commonly used
   * CoordinateArraySequenceFactory.
   *
   * @param size the number of coordinates in the sequence
   * @param dimension the dimension of the coordinates in the sequence
   * @param measures the measures of the coordinates in the sequence
   */
  static CoordinateSequence createCSMEas(CoordinateSequenceFactory csFactory, int size, int dimension, int measures) {
    CoordinateSequence cs;
    if (csFactory is CoordinateArraySequenceFactory && dimension == 1) {
      // work around JTS 1.14 CoordinateArraySequenceFactory regression ignoring provided
      // dimension
      cs = new CoordinateArraySequence.fromSizeDimensionMeasures(size, dimension, measures);
    } else {
      cs = csFactory.createSizeDimMeas(size, dimension, measures);
    }
    if (cs.getDimension() != dimension) {
      // illegal state error, try and fix
      throw StateError("Unable to use $csFactory to produce CoordinateSequence with dimension $dimension");
    }
    return cs;
  }
}
