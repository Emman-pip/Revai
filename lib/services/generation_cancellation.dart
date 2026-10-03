class GenerationCancelled implements Exception {
  const GenerationCancelled();
}

class GenerationCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  Future<void> Function()? stopNative;

  void check() {
    if (_cancelled) throw const GenerationCancelled();
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await stopNative?.call();
  }
}
