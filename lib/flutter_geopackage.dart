/// Entry point for the dart_jts library.
library flutter_geopackage;

import "dart:core";
import "dart:convert" as JSON;
import 'dart:ffi';
import 'dart:io';
import "dart:typed_data";
import 'package:flutter_geopackage/com/hydrologis/flutter_geopackage/core/queries.dart';
import 'package:intl/intl.dart';
import "dart:math" as math;
import 'package:dart_jts/dart_jts.dart';
import 'package:dart_hydrologis_db/dart_hydrologis_db.dart';
import 'package:sqlite3/sqlite3.dart';

part 'com/hydrologis/flutter_geopackage/core/geom.dart';
part 'com/hydrologis/flutter_geopackage/core/utils.dart';
part 'com/hydrologis/flutter_geopackage/core/style.dart';
part 'com/hydrologis/flutter_geopackage/core/functions.dart';
part 'com/hydrologis/flutter_geopackage/core/tiles.dart';
part 'com/hydrologis/flutter_geopackage/core/features.dart';
part 'com/hydrologis/flutter_geopackage/core/entries.dart';
part 'com/hydrologis/flutter_geopackage/geopackage.dart';
