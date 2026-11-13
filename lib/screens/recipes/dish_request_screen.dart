import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/dish_options.dart';
import '../../providers/pantry_provider.dart';
import '../../services/dish_options_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/live_recipe_card.dart';

class DishRequestScreen extends StatefulWidget {
  const DishRequestScreen({
    super.key,
    this.initialDish = '',
    this.autoCheck = false,
    this.service,
    this.openMenu,
  });
  final String initialDish;
  final bool autoCheck;
  final DishOptionsService? service;
  final Future<bool> Function(Uri)? openMenu;

  @override
  State<DishRequestScreen> createState() => _DishRequestScreenState();
}

class _DishRequestScreenState extends State<DishRequestScreen> {
  final _resultAnchor = GlobalKey();
  late final TextEditingController _dish;
  final _area = TextEditingController();
  late final DishOptionsService _service;
  DishOptions? _result;
  RestaurantResults? _restaurants;
  String? _error, _restaurantError, _snapshot;
  bool _checking = false, _searching = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _dish = TextEditingController(text: widget.initialDish);
    _service = widget.service ?? DishOptionsService();
    if (widget.autoCheck && widget.initialDish.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }
  }

  @override
  void dispose() {
    _dish.dispose();
    _area.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _signature(PantryProvider pantry) => jsonEncode([
    for (final item in pantry.allItems)
      [
        item.id,
        item.householdId,
        item.name,
        item.quantity,
        item.unit,
        item.expiryDate?.toIso8601String(),
      ],
  ]);

  void _invalidate(String _) => setState(() {
    _generation++;
    _checking = false;
    _searching = false;
    _result = null;
    _restaurants = null;
    _error = null;
    _restaurantError = null;
  });

  Future<void> _check() async {
    if (_checking) return;
    final dish = _dish.text.trim();
    if (dish.length < 2 || dish.length > 120) {
      setState(() => _error = 'Enter a dish name, such as chicken biryani.');
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    final pantry = context.read<PantryProvider>();
    final snapshot = _signature(pantry);
    setState(() {
      _checking = true;
      _result = null;
      _restaurants = null;
      _error = null;
      _restaurantError = null;
    });
    try {
      final result = await _service.checkDish(dish, pantry.allItems);
      if (!mounted || generation != _generation) return;
      if (snapshot != _signature(context.read<PantryProvider>())) {
        setState(
          () => _error =
              'Your pantry changed during the check. Please check again.',
        );
        return;
      }
      setState(() {
        _result = result;
        _snapshot = snapshot;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _generation) return;
      final resultContext = _resultAnchor.currentContext;
      if (resultContext != null && resultContext.mounted) {
        await Scrollable.ensureVisible(
          resultContext,
          alignment: 0.05,
          duration: const Duration(milliseconds: 250),
        );
      }
      if (!mounted || generation != _generation) return;
      if (result.hasMissingIngredients && _area.text.trim().length >= 2) {
        await _findRestaurants(generation);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is DishOptionsException
              ? error.message
              : 'The dish could not be checked. Please retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _findRestaurants(int generation) async {
    final area = _area.text.trim();
    if (area.length < 2 || area.length > 120) {
      setState(
        () => _restaurantError =
            'Enter your neighbourhood and city to find matching menus.',
      );
      return;
    }
    setState(() {
      _searching = true;
      _restaurantError = null;
      _restaurants = null;
    });
    try {
      final results = await _service.restaurants(_dish.text, area);
      if (mounted && generation == _generation) {
        setState(() => _restaurants = results);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _restaurantError = error is DishOptionsException
              ? error.message
              : 'Restaurant search failed. Please retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _open(RestaurantOption option) async {
    var opened = false;
    try {
      opened =
          await (widget.openMenu?.call(option.url) ??
              launchUrl(
                option.url,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The menu could not be opened. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final stale = _result != null && _snapshot != _signature(pantry);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a dish')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: AppPageBody(
          maxWidth: 992,
          shrinkWrap: true,
          child: FilledButton.icon(
            onPressed: _checking || pantry.isLoading ? null : _check,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_checking ? 'Checking…' : 'Check my pantry'),
          ),
        ),
      ),
      body: AppPageBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cook it or order it',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a dish. We will check your pantry and show what is missing. Add your area to find restaurant menus if you need ingredients.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _dish,
                onChanged: _invalidate,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Dish name',
                  hintText: 'e.g. chicken biryani',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _area,
                maxLength: 120,
                onChanged: (_) => setState(() {
                  _generation++;
                  _searching = false;
                  _checking = false;
                  _restaurants = null;
                  _restaurantError = null;
                }),
                decoration: const InputDecoration(
                  labelText: 'Area and city (optional)',
                  hintText: 'e.g. Johar Town, Lahore',
                  counterText: '',
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: 8),
              Text(
                'Restaurant search shares only the dish and the area you enter with web search. Your pantry is not sent to the search provider.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (stale)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Your pantry has changed. Check again to update the result.',
                  ),
                ),
              if (result != null && !stale) ...[
                const SizedBox(height: 24),
                Text(
                  result.status == 'ready'
                      ? 'You can cook this recipe'
                      : result.hasMissingIngredients
                      ? 'Ingredients to pick up'
                      : 'Check this dish first',
                  key: _resultAnchor,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(result.message),
                if (result.recipe != null) ...[
                  const SizedBox(height: 12),
                  LiveRecipeCard(recipe: result.recipe!),
                  Text(
                    result.quantitiesNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (result.status != 'ready') ...[
                  const SizedBox(height: 24),
                  Text(
                    'Order from a restaurant',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your neighbourhood and city above, then find matching menus.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _searching
                        ? null
                        : () => _findRestaurants(_generation),
                    icon: const Icon(Icons.restaurant_outlined),
                    label: Text(
                      _searching ? 'Finding menus…' : 'Find restaurants',
                    ),
                  ),
                  if (_restaurantError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _restaurantError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_restaurants != null) ...[
                    const SizedBox(height: 12),
                    Text(_restaurants!.message),
                    const SizedBox(height: 8),
                    for (final option in _restaurants!.restaurants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SurfacePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                option.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${option.source} · ${_restaurants!.area}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Text(option.summary),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _open(option),
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('View menu and order'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Text(
                      _restaurants!.note,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
