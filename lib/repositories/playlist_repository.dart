import '../models/playlist.dart';
import '../objectbox.g.dart';

class PlaylistRepository {
  final Box<Playlist> _box;

  PlaylistRepository(Store store) : _box = store.box<Playlist>();

  int save(Playlist playlist) {
    return _box.put(playlist);
  }

  Playlist? getById(int id) {
    return _box.get(id);
  }

  Playlist? getByPlaylistId(String playlistId) {
    final query = _box.query(Playlist_.playlistId.equals(playlistId)).build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  List<Playlist> getAll() {
    return _box.getAll();
  }

  bool delete(int id) {
    return _box.remove(id);
  }

  void updatePosition(String playlistId, int newIndex) {
    final playlist = getByPlaylistId(playlistId);
    if (playlist != null) {
      playlist.currentIndex = newIndex;
      save(playlist);
    }
  }

  void markCompleted(String playlistId) {
    final playlist = getByPlaylistId(playlistId);
    if (playlist != null) {
      playlist.isCompleted = true;
      save(playlist);
    }
  }

  void updateLastAccessed(int id) {
    final playlist = getById(id);
    if (playlist != null) {
      playlist.lastAccessedAt = DateTime.now();
      save(playlist);
    }
  }
}
