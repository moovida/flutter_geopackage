part of flutter_geopackage;

class SqliteDb {
  Database _db;
  String _dbPath;
  bool _isClosed = false;

  SqliteDb(this._dbPath);

  void openOrCreate({Function dbCreateFunction}) {
    var dbFile = File(_dbPath);
    bool existsAlready = dbFile.existsSync();
    _db = Database.openFile(dbFile);
    if (!existsAlready) {
      dbCreateFunction(_db);
    }
  }

  String get path => _dbPath;

  bool isOpen() {
    if (_db == null) return false;
    return !_isClosed;
  }

  void close() {
    _isClosed = true;
    return _db?.close();
  }

  /// This should only be used when a custom function is necessary,
  /// which forces to use the method from the moor database.
  Database getInternalDb() {
    return _db;
  }

  int execute(String sqlToExecute) {
    _db.execute(sqlToExecute);
    return _db.getUpdatedRows();
  }

  int insertPrepared(String sql, [List<dynamic> arguments]) {
    PreparedStatement insertStmt;
    try {
      insertStmt = _db.prepare(sql);
      insertStmt.execute(arguments);

      return _db.getUpdatedRows();
    } finally {
      insertStmt?.close();
    }
  }

  Iterable<Row> select(String sql, [List<dynamic> arguments]) {
    PreparedStatement selectStmt;
    try {
      selectStmt = _db.prepare(sql);
      final Result result = selectStmt.select(arguments);
      return result;
    } finally {
      selectStmt?.close();
    }
  }

  int update(String updateSql) {
    _db.execute(updateSql);
    return _db.getUpdatedRows();
  }

  int updatePrepared(String updateSql, [List<dynamic> arguments]) {
    PreparedStatement updateStmt;
    try {
      updateStmt = _db.prepare(updateSql);
      updateStmt.execute(arguments);

      return _db.getUpdatedRows();
    } finally {
      updateStmt?.close();
    }
  }

  // int updateMap(String tableName, Map<String, dynamic> values) {

  //   List<dynamic> valuesList = [];
  //   String setSql = values.entries.map((MapEntry entry){
  //     valuesList.add(entry.value);
  //     return "${entry.key}=?";
  //   }).join(",");
  //   String sql = "update $tableName "

  //   _db.execute(updateSql);
  //   return _db.getUpdatedRows();
  // }

  int delete(String deleteSql) {
    _db.execute(deleteSql);
    return _db.getUpdatedRows();
  }

  List<String> getTables(bool doOrder) {
    List<String> tableNames = [];
    String orderBy = " ORDER BY name";
    if (!doOrder) {
      orderBy = "";
    }
    String sql =
        "SELECT name FROM sqlite_master WHERE type='table' or type='view'" +
            orderBy;
    var res = select(sql);
    for (var row in res) {
      var name = row['name'];
      tableNames.add(name);
    }
    return tableNames;
  }

  bool hasTable(String tableName) {
    String sql = "SELECT name FROM sqlite_master WHERE type='table'";
    var res = select(sql);
    tableName = tableName.toLowerCase();
    for (var row in res) {
      var name = row['name'];
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
  List<List<dynamic>> getTableColumns(String tableName) {
    String sql = "PRAGMA table_info(" + tableName + ")";
    List<List<dynamic>> columnsList = [];
    var res = select(sql);
    for (var row in res) {
      String colName = row['name'];
      String colType = row['type'];
      int isPk = row['pk'];
      columnsList.add([colName, colType, isPk]);
    }
    return columnsList;
  }

  /// Get the primary key from a non spatial db.
  String getPrimaryKey(String tableName) {
    String sql = "PRAGMA table_info(" + tableName + ")";
    var res = select(sql);
    for (var map in res) {
      var pk = map["pk"];
      if (pk == 1) {
        return map["name"];
      }
    }
    return null;
  }
}
