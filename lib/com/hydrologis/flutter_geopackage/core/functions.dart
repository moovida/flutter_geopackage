part of flutter_geopackage;

class MinxFunction extends DbFunction {
  @override
  void runOnValue(value) {
    if (value is List<int>) {
      var minX = GeoPkgGeomReader(value).getEnvelope().getMinX();
      setResultNum(minX);
    } else {
      setResultNull();
    }
  }
}

class MaxxFunction extends DbFunction {
  @override
  void runOnValue(value) {
    if (value is List<int>) {
      var maxX = GeoPkgGeomReader(value).getEnvelope().getMaxX();
      setResultNum(maxX);
    } else {
      setResultNull();
    }
  }
}

class MinyFunction extends DbFunction {
  @override
  void runOnValue(value) {
    if (value is List<int>) {
      var minY = GeoPkgGeomReader(value).getEnvelope().getMinY();
      setResultNum(minY);
    } else {
      setResultNull();
    }
  }
}

class MaxyFunction extends DbFunction {
  @override
  void runOnValue(value) {
    if (value is List<int>) {
      var maxY = GeoPkgGeomReader(value).getEnvelope().getMaxY();
      setResultNum(maxY);
    } else {
      setResultNull();
    }
  }
}

class IsEmptyFunction extends DbFunction {
  @override
  void runOnValue(value) {
    if (value is List<int>) {
      Geometry geom = GeoPkgGeomReader(value).get();
      setResultBool(geom.isEmpty());
    } else {
      setResultNull();
    }
  }
}
