part of flutter_geopackage;

abstract class QueryObjectBuilder<T> {
  String querySql();

  String insertSql();

  Map<String, dynamic> toMap(T item);

  T fromMap(Map<String, dynamic> map);
}

class SqliteDb {
  Database _db;
  String _dbPath;

  SqliteDb(this._dbPath);

  Future<void> openOrCreate({Function dbCreateFunction}) async {
    _db = await openDatabase(
      _dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        if (dbCreateFunction != null) {
          await dbCreateFunction(db);
        }
      },
    );
  }

  String get path => _dbPath;

  bool isOpen() {
    if (_db == null) return false;
    return _db.isOpen;
  }

  Future<void> close() async {
    return await _db.close();
  }

  /// Get a list of items defined by the [queryObj].
  ///
  /// Optionally a custom [whereString] piece can be passed in. This needs to start with the word where.
  Future<List<T>> getQueryObjectsList<T>(QueryObjectBuilder<T> queryObj,
      {whereString: ""}) async {
    String querySql = "${queryObj.querySql()} $whereString";
    var res = await query(querySql);
    List<T> items = [];
    for (int i = 0; i < res.length; i++) {
      var map = res[i];
      var obj = queryObj.fromMap(map);
      items.add(obj);
    }
    return items;
  }

  Future<void> execute(String insertSql, [List<dynamic> arguments]) async {
    return _db.execute(insertSql, arguments);
  }

  Future<List<Map<String, dynamic>>> query(String querySql,
      [List<dynamic> arguments]) async {
    return _db.rawQuery(querySql, arguments);
  }

  Future<int> insert(String insertSql, [List<dynamic> arguments]) async {
    return _db.rawInsert(insertSql, arguments);
  }

  Future<int> insertMap(String table, Map<String, dynamic> values) async {
    return _db.insert(table, values);
  }

  Future<int> update(String updateSql) async {
    return _db.rawUpdate(updateSql);
  }

  Future<int> updateMap(
      String table, Map<String, dynamic> values, String where) async {
    return _db.update(table, values, where: where);
  }

  Future<int> delete(String deleteSql) async {
    return _db.rawDelete(deleteSql);
  }

  Future<T> transaction<T>(Future<T> action(Transaction txn),
      {bool exclusive}) async {
    return await _db.transaction(action, exclusive: exclusive);
  }

  Future<List<String>> getTables(bool doOrder) async {
    List<String> tableNames = [];
    String orderBy = " ORDER BY name";
    if (!doOrder) {
      orderBy = "";
    }
    String sql =
        "SELECT name FROM sqlite_master WHERE type='table' or type='view'" +
            orderBy;
    var res = await query(sql);
    for (int i = 0; i < res.length; i++) {
      var name = res[i]['name'];
      tableNames.add(name);
    }
    return tableNames;
  }

  Future<bool> hasTable(String tableName) async {
    String sql = "SELECT name FROM sqlite_master WHERE type='table'";
    var res = await query(sql);
    tableName = tableName.toLowerCase();
    for (int i = 0; i < res.length; i++) {
      String name = res[i]['name'];
      if (name.toLowerCase() == tableName) return true;
    }
    return false;
  }

  /// Get the table columns from a non spatial db.
  ///
  /// @param db the db.
  /// @param tableName the name of the table to get the columns for.
  /// @return the list of table column information.
  /// @throws Exception
  Future<List<List<dynamic>>> getTableColumns(String tableName) async {
    String sql = "PRAGMA table_info(" + tableName + ")";
    List<List<dynamic>> columnsList = [];
    var res = await query(sql);
    for (int i = 0; i < res.length; i++) {
      var map = res[i];
      String colName = map['name'];
      String colType = map['type'];
      int isPk = map['pk'];
      columnsList.add([colName, colType, isPk]);
    }
    return columnsList;
  }
}
