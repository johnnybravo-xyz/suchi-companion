import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/api_models.dart';
import '../api/suchi_client.dart';

final class JdCategoryStore extends ChangeNotifier {
  JdCategoryStore({required this.client, required this.onUnauthorized});

  final SuchiClient client;
  final void Function(ApiException error) onUnauthorized;

  List<JDCategory> _categories = const [];
  ApiException? _error;
  Future<void>? _pending;
  bool _loading = false;
  int _generation = 0;

  List<JDCategory> get categories => _categories;
  ApiException? get error => _error;
  bool get loading => _loading;
  JDCategory? get inboxCategory =>
      _categories.where((category) => category.code == 49).firstOrNull;

  Future<void> load({bool force = false}) {
    final pending = _pending;
    if (pending != null) return pending;
    if (!force && _categories.isNotEmpty) return Future.value();
    final operation = _load();
    _pending = operation;
    return operation;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final categories = <JDCategory>[];
      var page = 1;
      while (page <= 100) {
        final response = await client.jdCategories(page: page, pageSize: 100);
        if (generation != _generation) return;
        categories.addAll(response.results);
        if (response.next == null) break;
        page++;
      }
      categories.sort((left, right) => left.code.compareTo(right.code));
      _categories = List.unmodifiable(categories);
    } on ApiException catch (error) {
      if (generation != _generation) return;
      _error = error;
      if (error.expiresSession) onUnauthorized(error);
    } finally {
      if (generation == _generation) {
        _loading = false;
        _pending = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
