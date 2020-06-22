part of flutter_geopackage;

void minxFunction(Pointer<FunctionContext> ctx, int argCount,
    Pointer<Pointer<SqliteValue>> args) {
  final value = args[0].value;
  if (value is List<int>) {
    var minX = GeoPkgGeomReader(value).getEnvelope().getMinX();
    ctx.resultNum(minX);
  } else {
    ctx.resultNull();
  }
}

void maxxFunction(Pointer<FunctionContext> ctx, int argCount,
    Pointer<Pointer<SqliteValue>> args) {
  final value = args[0].value;
  if (value is List<int>) {
    var maxX = GeoPkgGeomReader(value).getEnvelope().getMaxX();
    ctx.resultNum(maxX);
  } else {
    ctx.resultNull();
  }
}

void minyFunction(Pointer<FunctionContext> ctx, int argCount,
    Pointer<Pointer<SqliteValue>> args) {
  final value = args[0].value;
  if (value is List<int>) {
    var minY = GeoPkgGeomReader(value).getEnvelope().getMinY();
    ctx.resultNum(minY);
  } else {
    ctx.resultNull();
  }
}

void maxyFunction(Pointer<FunctionContext> ctx, int argCount,
    Pointer<Pointer<SqliteValue>> args) {
  final value = args[0].value;
  if (value is List<int>) {
    var maxY = GeoPkgGeomReader(value).getEnvelope().getMaxY();
    ctx.resultNum(maxY);
  } else {
    ctx.resultNull();
  }
}

void isEmptyFunction(Pointer<FunctionContext> ctx, int argCount,
    Pointer<Pointer<SqliteValue>> args) {
  final value = args[0].value;
  if (value is List<int>) {
    Geometry geom = GeoPkgGeomReader(value).get();
    ctx.resultBool(geom.isEmpty());
  } else {
    ctx.resultNull();
  }
}
