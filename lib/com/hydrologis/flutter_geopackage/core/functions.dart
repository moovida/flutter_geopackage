part of flutter_geopackage;


void minXFunction(Pointer<FunctionContext> ctx, int argCount,
      Pointer<Pointer<SqliteValue>> args) {
    final value = args[0].value;
    if (value is num) {
      // TODO implements minX check
      ctx.resultNum(value);
    } else {
      ctx.resultNull();
    }
  }

  void maxXFunction(Pointer<FunctionContext> ctx, int argCount,
      Pointer<Pointer<SqliteValue>> args) {
    final value = args[0].value;
    if (value is num) {
      // TODO implements minX check
      ctx.resultNum(value);
    } else {
      ctx.resultNull();
    }
  }

  void minYFunction(Pointer<FunctionContext> ctx, int argCount,
      Pointer<Pointer<SqliteValue>> args) {
    final value = args[0].value;
    if (value is num) {
      // TODO implements minX check
      ctx.resultNum(value);
    } else {
      ctx.resultNull();
    }
  }

  void maxYFunction(Pointer<FunctionContext> ctx, int argCount,
      Pointer<Pointer<SqliteValue>> args) {
    final value = args[0].value;
    if (value is num) {
      // TODO implements minX check
      ctx.resultNum(value);
    } else {
      ctx.resultNull();
    }
  }

  void isEmptyFunction(Pointer<FunctionContext> ctx, int argCount,
      Pointer<Pointer<SqliteValue>> args) {
    final value = args[0].value;
    if (value is num) {
      // TODO implements minX check
      ctx.resultBool(false);
    } else {
      ctx.resultNull();
    }
  }