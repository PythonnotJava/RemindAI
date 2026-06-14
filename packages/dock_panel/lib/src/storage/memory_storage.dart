import 'dock_storage.dart';

/// In-memory implementation of [DockStorage] for testing.
class MemoryDockStorage implements DockStorage {
  Map<String, dynamic>? _data;

  @override
  Map<String, dynamic>? read() => _data;

  @override
  void write(Map<String, dynamic> data) => _data = data;

  @override
  void clear() => _data = null;
}
