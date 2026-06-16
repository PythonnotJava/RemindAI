import 'dart:async';

/// Interface for persisting the dock layout.
///
/// Implement this to save/restore layouts from SharedPreferences,
/// files, databases, etc.
abstract class DockStorage {
  /// Read the stored layout. Returns null if nothing is stored.
  FutureOr<Map<String, dynamic>?> read();

  /// Write the layout to storage.
  FutureOr<void> write(Map<String, dynamic> data);

  /// Clear stored layout.
  FutureOr<void> clear();
}
