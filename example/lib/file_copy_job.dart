import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:meta/meta.dart' show required;
import 'package:path/path.dart' show basename, join;
import 'package:path_provider/path_provider.dart';

// ////////////////////////////////////////////////////////////////////////////

/// A class to create asset files' copy jobs
class AssetCopyJob extends FileCopyJob {
  /// Creates an asset copy job
  ///
  /// Call [run] to start the job and get the result - a [List<File>].
  ///
  /// Use [future] to acquire the result of the job.
  AssetCopyJob({
    @required List<String> assets,
    bool overwrite = false,
    String outputDirectory,
    String debugLabel,
  })  : assert(assets.isNotEmpty),
        _assets = assets,
        super(
          count: assets.length,
          overwrite: overwrite,
          outputDirectory: outputDirectory,
          debugLabel: debugLabel,
        );

  final List<String> _assets;

  FutureOr<File> getFilename(int index) => File(_assets[index]);

  FutureOr<ByteData> getByteData(int index) => rootBundle.load(_assets[index]);
}

// ////////////////////////////////////////////////////////////////////////////

/// An abstract class to create copy files jobs
abstract class FileCopyJob extends Job {
  FileCopyJob({
    @required this.count,
    this.overwrite = false,
    this.outputDirectory,
    String debugLabel,
  })  : assert(count > 0),
        assert(overwrite != null),
        assert(outputDirectory == null || outputDirectory.isNotEmpty),
        super(
          errors: List<Object>.filled(count, null),
          debugLabel: debugLabel,
        );

  /// Signifies how many files will be copied
  final int count;

  /// Signifies if already copied files should be overwritten
  final bool overwrite;

  /// Signifies a specific output directory
  ///
  /// Defaults to the platform-specific app data/documents directory.
  final String outputDirectory;

  /// Returns the job future
  ///
  /// If [run] hasn't been called getting this future will initiate the job.
  Future<List<File>> get future => _future ??= run();

  /// Runs the copy job
  ///
  /// WARNING: Calling [run] more than once will throw a [StateError].
  ///
  /// Use [future] to await for the job to finish.
  ///
  /// NOTES:
  ///  - If any of the files fail to copy the job won't fail immediately,
  ///    but continue;
  ///  - If all files fail to copy then the job has failed - it fails
  ///    with the first error;
  ///  - Any and all errors can be found in the [errors] indexed list.
  Future<List<File>> run() {
    if (_future != null) {
      throw StateError('${toString()} has already run');
    }
    return _future = _run();
  }

  // --- Requiring implementation

  /// Produces the filename for a given index
  FutureOr<File> getFilename(int index);

  /// Fetches the [ByteData] for a file at given index
  FutureOr<ByteData> getByteData(int index);

  // --- Overridables

  /// Returns the output [File] for given [index]
  FutureOr<File> getOutFile(String outDir, int index) async {
    final file = await getFilename(index);
    return File(join(outDir, basename(file.path)));
  }

  /// Copies the file at given [index] into [outFile]
  FutureOr<File> copyFile(File outFile, int index) async {
    final data = await getByteData(index);
    return outFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  /// Returns the output directory
  ///
  /// Uses the app's platform-specific data/documents directory
  FutureOr<String> getOutputDir() {
    return outputDirectory ??
        getApplicationDocumentsDirectory().then((d) => d.path);
  }

  // --- Private

  Future<List<File>> _future;

  Future<List<File>> _run() async {
    final dir = await getOutputDir();

    final futures = <Future<File>>[];
    // Iterates over all files to copy and copies them to the data dir
    for (int i = 0; i < count; i++) {
      futures.add(Future<File>(() async {
        try {
          final outFile = await getOutFile(dir, i);
          if (!overwrite && await outFile.exists()) {
            return outFile;
          }
          return copyFile(outFile, i);
        } catch (e) {
          // Catch the error but don't fail the copy chain
          errors[i] = e;
          return null;
        }
      }));
    }

    // Await for all futures to complete
    final files = await Future.wait(futures);

    if (files.every((f) => f == null)) {
      // In case all files failed to copy - throw the first caught error
      return Future.error(errors.first);
    }

    return files;
  }
}

// ////////////////////////////////////////////////////////////////////////////

/// An abstract class for async jobs
abstract class Job {
  /// Creates a [Job] with a reference list of errors and a label
  /// used for debugging.
  ///
  /// [errors] is best initialised with an empty [List] and populated while
  /// the job runs.
  ///
  /// The label is purely for debugging and not used for comparing the identity
  /// of Job.
  Job({this.errors, String debugLabel}) : _debugLabel = debugLabel;

  Future run();

  /// Holds the failures while the job runs
  final List<Object> errors;

  final String _debugLabel;

  String toString() {
    final String label = _debugLabel == null ? '' : ' $_debugLabel';
    return '[$runtimeType$label]';
  }
}
