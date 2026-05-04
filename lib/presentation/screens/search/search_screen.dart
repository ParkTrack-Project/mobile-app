import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../providers/routing_provider.dart';
import '../../../core/theme/app_colors.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // Широкая bbox вокруг точки биаса (покрывает ~1000 км в каждую сторону).
  // Центр bbox = текущая позиция камеры, что правильно биасирует Yandex Suggest.
  static const double _biasLatDelta = 10.0;
  static const double _biasLonDelta = 15.0;
  // Запасной вариант если геолокация/позиция камеры неизвестны — центр России.
  static const BoundingBox _russiaBoundingBox = BoundingBox(
    southWest: Point(latitude: 41.0, longitude: 19.0),
    northEast: Point(latitude: 82.0, longitude: 169.0),
  );

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  SuggestSession? _suggestSession;
  SearchSession? _searchSession;
  Timer? _debounce;
  List<SuggestItem> _suggestions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      final saved = ref.read(searchQueryProvider);
      if (saved.isNotEmpty) {
        _controller.text = saved;
        _suggest(saved);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestSession?.close();
    _searchSession?.close();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    ref.read(searchQueryProvider.notifier).state = text;
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _suggest(text.trim()),
    );
  }

  double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  BoundingBox _buildLocalBoundingBox(SearchBias bias) {
    final south = _clamp(bias.latitude - _biasLatDelta, -90.0, 90.0);
    final north = _clamp(bias.latitude + _biasLatDelta, -90.0, 90.0);
    final west = _clamp(bias.longitude - _biasLonDelta, -180.0, 180.0);
    final east = _clamp(bias.longitude + _biasLonDelta, -180.0, 180.0);
    return BoundingBox(
      southWest: Point(latitude: south, longitude: west),
      northEast: Point(latitude: north, longitude: east),
    );
  }

  Future<List<SuggestItem>> _loadSuggestions(
    String text,
    BoundingBox boundingBox,
  ) async {
    final resultWithSession = YandexSuggest.getSuggestions(
      text: text,
      boundingBox: boundingBox,
      suggestOptions: const SuggestOptions(suggestType: SuggestType.unspecified),
    );
    _suggestSession?.close();
    _suggestSession = resultWithSession.session;
    final result = await resultWithSession.result.timeout(
      const Duration(seconds: 5),
    );
    return result.items ?? [];
  }

  Future<Point?> _searchPointByText(
    String text,
    BoundingBox boundingBox,
  ) async {
    final resultWithSession = YandexSearch.searchByText(
      searchText: text,
      geometry: Geometry.fromBoundingBox(boundingBox),
      searchOptions: const SearchOptions(searchType: SearchType.geo),
    );
    _searchSession?.close();
    _searchSession = resultWithSession.session;
    final result = await resultWithSession.result.timeout(
      const Duration(seconds: 5),
    );
    return result.items?.firstOrNull?.geometry.firstOrNull?.point;
  }

  Future<void> _suggest(String text) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final searchBias = ref.read(searchBiasProvider);
      final bbox = searchBias == null
          ? _russiaBoundingBox
          : _buildLocalBoundingBox(searchBias);
      final items = await _loadSuggestions(text, bbox);
      if (!mounted) return;
      setState(() {
        _suggestions = items;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Поиск занял слишком много времени')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось выполнить поиск')),
      );
    }
  }

  void _selectDestination(Destination destination) {
    ref.read(destinationProvider.notifier).state = destination;
    context.pop();
  }

  Future<void> _onSuggestionTap(SuggestItem item) async {
    _focusNode.unfocus();
    if (item.center != null) {
      _selectDestination(Destination(
        latitude: item.center!.latitude,
        longitude: item.center!.longitude,
        name: item.title,
      ));
      return;
    }

    setState(() {
      _loading = true;
      _suggestions = [];
    });
    try {
      final searchBias = ref.read(searchBiasProvider);
      final bbox = searchBias == null
          ? _russiaBoundingBox
          : _buildLocalBoundingBox(searchBias);
      final point = await _searchPointByText(item.searchText, bbox);
      if (!mounted) return;
      if (point == null) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось определить координаты места')),
        );
        return;
      }
      _selectDestination(Destination(
        latitude: point.latitude,
        longitude: point.longitude,
        name: item.title,
      ));
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Определение точки заняло слишком много времени')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить координаты места')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          onSubmitted: (text) {
            if (text.trim().isNotEmpty) _suggest(text.trim());
          },
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Введите адрес или место',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
                setState(() => _suggestions = []);
              },
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _suggestions.isEmpty
              ? _EmptyState(hasQuery: _controller.text.isNotEmpty)
              : ListView.builder(
                  itemCount: _suggestions.length,
                  itemBuilder: (_, i) {
                    final item = _suggestions[i];
                    return ListTile(
                      leading: const Icon(
                        Icons.place_outlined,
                        color: AppColors.textSecondary,
                      ),
                      title: Text(item.title),
                      subtitle: item.subtitle != null
                          ? Text(
                              item.subtitle!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            )
                          : null,
                      onTap: () => _onSuggestionTap(item),
                    );
                  },
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.search,
            size: 56,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'Ничего не найдено' : 'Введите адрес или место',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
