/// Entry point for the dart_jts library.
library flutter_geopackage;

import "dart:core" ;
import "dart:convert" as JSON ;
import 'dart:ffi';
import 'dart:io';
import "dart:typed_data" ;
import 'package:intl/intl.dart';
import "dart:math" as math;
import 'package:dart_jts/dart_jts.dart';
import 'package:moor_ffi/database.dart';

part 'com/hydrologis/flutter_geopackage/core/database.dart';
part 'com/hydrologis/flutter_geopackage/core/geom.dart';
part 'com/hydrologis/flutter_geopackage/core/utils.dart';
part 'com/hydrologis/flutter_geopackage/core/style.dart';
part 'com/hydrologis/flutter_geopackage/core/functions.dart';
part 'com/hydrologis/flutter_geopackage/geopackage.dart';