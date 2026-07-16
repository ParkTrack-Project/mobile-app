import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../providers/routing_provider.dart';
import '../../../core/localization/app_localizations.dart';
import 'place_search_models.dart';
import 'place_search_service.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // Prefer results around the current map center without restricting a query
  // that explicitly names another city.
  static const double _biasLatDelta = 1.0;
  static const double _biasLonDelta = 1.5;
  // Fallback if location/camera position unknown — center of Russia.
  static const PlaceSearchBounds _russiaBoundingBox = PlaceSearchBounds(
    south: 41.0,
    west: 19.0,
    north: 82.0,
    east: 169.0,
  );

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _searchService = PlaceSearchService();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  int _suggestSeq = 0;

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
    _searchService.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    ref.read(searchQueryProvider.notifier).state = text;
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      _suggestSeq++;
      setState(() {
        _suggestions = [];
        _loading = false;
      });
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

  PlaceSearchBounds _buildLocalBoundingBox(SearchBias bias) {
    final south = _clamp(bias.latitude - _biasLatDelta, -90.0, 90.0);
    final north = _clamp(bias.latitude + _biasLatDelta, -90.0, 90.0);
    final west = _clamp(bias.longitude - _biasLonDelta, -180.0, 180.0);
    final east = _clamp(bias.longitude + _biasLonDelta, -180.0, 180.0);
    return PlaceSearchBounds(
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }

  Future<List<PlaceSuggestion>> _loadSuggestions(
    String text,
    PlaceSearchBounds boundingBox,
  ) => _searchService
      .suggestions(text, boundingBox)
      .timeout(const Duration(seconds: 5));

  Future<PlaceSearchPoint?> _searchPointByText(
    String text,
    PlaceSearchBounds boundingBox,
  ) => _searchService
      .pointByText(text, boundingBox)
      .timeout(const Duration(seconds: 5));

  Future<void> _suggest(String text) async {
    if (!mounted) return;
    final seq = ++_suggestSeq;
    setState(() => _loading = true);
    final s = ref.read(l10nProvider);
    try {
      final searchBias = ref.read(searchBiasProvider);
      final bbox = searchBias == null
          ? _russiaBoundingBox
          : _buildLocalBoundingBox(searchBias);
      final items = await _loadSuggestions(text, bbox);
      if (!mounted || seq != _suggestSeq) return;
      setState(() {
        _suggestions = items;
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted || seq != _suggestSeq) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.searchTimeout)));
    } catch (_) {
      if (!mounted || seq != _suggestSeq) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.searchError)));
    }
  }

  void _selectDestination(Destination destination) {
    ref.read(routingProvider.notifier).reset();
    ref.read(destinationProvider.notifier).state = destination;
    context.pop();
  }

  Future<void> _onSuggestionTap(PlaceSuggestion item) async {
    _focusNode.unfocus();
    if (item.latitude != null && item.longitude != null) {
      _selectDestination(
        Destination(
          latitude: item.latitude!,
          longitude: item.longitude!,
          name: item.title,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _suggestions = [];
    });
    final s = ref.read(l10nProvider);
    try {
      final searchBias = ref.read(searchBiasProvider);
      final bbox = searchBias == null
          ? _russiaBoundingBox
          : _buildLocalBoundingBox(searchBias);
      final point = await _searchPointByText(item.searchText, bbox);
      if (!mounted) return;
      if (point == null) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.pointLookupError)));
        return;
      }
      _selectDestination(
        Destination(
          latitude: point.latitude,
          longitude: point.longitude,
          name: item.title,
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.pointLookupTimeout)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.searchError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(l10nProvider);
    final theme = Theme.of(context);
    return PointerInterceptor(
      intercepting: kIsWeb,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
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
            decoration: InputDecoration(
              hintText: s.searchHint,
              hintStyle: TextStyle(color: theme.hintColor),
              border: InputBorder.none,
            ),
          ),
          actions: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  _debounce?.cancel();
                  _suggestSeq++;
                  ref.read(searchQueryProvider.notifier).state = '';
                  setState(() {
                    _suggestions = [];
                    _loading = false;
                  });
                },
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: theme.dividerColor),
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
                    leading: Icon(Icons.place_outlined, color: theme.hintColor),
                    title: Text(item.title),
                    subtitle: item.subtitle != null
                        ? Text(
                            item.subtitle!,
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 13,
                            ),
                          )
                        : null,
                    onTap: () => _onSuggestionTap(item),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(l10nProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.search,
            size: 56,
            color: Theme.of(context).dividerColor,
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? s.searchNoResults : s.searchHint,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
