import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geopackage/flutter_geopackage.dart';

class GeopackageImageProvider extends ImageProvider<GeopackageImageProvider> {
  LazyGpkgTile _tile;
  GeopackageImageProvider(this._tile);

  @override
  ImageStreamCompleter load(
      GeopackageImageProvider key, DecoderCallback decoder) {
    return MultiFrameImageStreamCompleter(
      codec: loadAsync(key),
      scale: 1,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('Image provider', this);
        yield DiagnosticsProperty<GeopackageImageProvider>('Image key', key);
      },
    );
  }

  Future<Codec> loadAsync(GeopackageImageProvider key) async {
    assert(key == this);

    try {
      _tile.fetch();
      if (_tile.tileImageBytes != null) {
        return await PaintingBinding.instance
            .instantiateImageCodec(_tile.tileImageBytes);
      }
    } catch (e) {
      print(e); // ignore later
    }

    return Future<Codec>.error('Failed to load tile: $_tile');
  }

  @override
  Future<GeopackageImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  int get hashCode => _tile.hashCode;

  @override
  bool operator ==(other) {
    return other is GeopackageImageProvider && _tile == other._tile;
  }
}
