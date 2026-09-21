import '../settings/app_strings.dart';
import '../theme/app_palette.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide showModalBottomSheet;
import '../windows/adaptive_sheet.dart';
import '../windows/desktop_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../branding/brand_icon_cache.dart';
import '../generator/password_generator_page.dart';
import '../generator/password_quality.dart';
import '../health/breach_check.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../vault/vault_models.dart';
import '../vault/vault_repository.dart';
import '../vault/secure_clipboard.dart';
import '../widgets/animated_password_text.dart';
import '../sync/sync_store.dart';
import '../autofill/autofill_bridge.dart';

enum _PasswordSort { favoritesFirst, name, updated, created }

String _passwordSortLabel(_PasswordSort sort) {
  return switch (sort) {
    _PasswordSort.favoritesFirst => tr('Favoritos primeiro'),
    _PasswordSort.name => tr('Nome (A–Z)'),
    _PasswordSort.updated => tr('Atualizados recentemente'),
    _PasswordSort.created => tr('Criados recentemente'),
  };
}

class PasswordsPage extends StatefulWidget {
  const PasswordsPage({
    this.showBottomNavigation = true,
    this.vault,
    this.healthFilter,
    this.breachCheck,
    this.onVaultChanged,
    this.remoteSnapshot,
    this.onRemoteAction,
    this.pendingAutofillSave,
    this.onAutofillSaveHandled,
    super.key,
  });

  final bool showBottomNavigation;
  final VaultRepository? vault;
  final String? healthFilter;
  final BreachCheckController? breachCheck;
  final VoidCallback? onVaultChanged;
  final VaultSnapshot? remoteSnapshot;
  final Future<void> Function(RemoteAction)? onRemoteAction;
  final AutofillSaveCandidate? pendingAutofillSave;
  final VoidCallback? onAutofillSaveHandled;

  @override
  State<PasswordsPage> createState() => PasswordsPageState();
}

class PasswordsPageState extends State<PasswordsPage> {
  final TextEditingController _searchController = TextEditingController();
  late final List<_AccountData> _accounts;
  late final List<_ServiceData> _services;
  String _query = '';
  String? _selectedAccountEmail;
  String? _healthFilter;
  bool _accountsExpanded = false;
  bool _servicesExpanded = true;
  int _idCounter = 0;
  bool _weakAlertDismissed = false;
  bool _compromisedAlertDismissed = false;
  String? _handledAutofillSaveId;
  _PasswordSort _sort = _PasswordSort.favoritesFirst;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    final vault = widget.vault;
    _healthFilter = widget.healthFilter;
    if (vault == null && widget.remoteSnapshot == null) {
      _accounts = List.of(_defaultAccounts);
      _services = List.of(_defaultServices);
    } else {
      _services = (widget.remoteSnapshot?.services ?? vault!.services)
          .map(_ServiceData.fromVault)
          .toList(growable: true);
      _accounts = (widget.remoteSnapshot?.accounts ?? vault!.accounts)
          .map(
            (account) => _AccountData.fromVault(
              account,
              services: _serviceCountFor(account.email),
            ),
          )
          .toList(growable: true);
    }
    _searchController.addListener(_onSearchChanged);
    widget.breachCheck?.addListener(_onBreachChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveAutofillCapture());
  }

  @override
  void didUpdateWidget(covariant PasswordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final remote = widget.remoteSnapshot;
    if (remote != null && !identical(oldWidget.remoteSnapshot, remote)) {
      _services
        ..clear()
        ..addAll(remote.services.map(_ServiceData.fromVault));
      _accounts
        ..clear()
        ..addAll(
          remote.accounts.map(
            (a) =>
                _AccountData.fromVault(a, services: _serviceCountFor(a.email)),
          ),
        );
      if (!_accounts.any((a) => a.email == _selectedAccountEmail)) {
        _selectedAccountEmail = null;
      }
    }
    if (oldWidget.healthFilter != widget.healthFilter) {
      _healthFilter = widget.healthFilter;
    }
    if (oldWidget.breachCheck != widget.breachCheck) {
      oldWidget.breachCheck?.removeListener(_onBreachChanged);
      widget.breachCheck?.addListener(_onBreachChanged);
    }
    if (oldWidget.pendingAutofillSave?.id != widget.pendingAutofillSave?.id) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _saveAutofillCapture(),
      );
    }
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    widget.breachCheck?.removeListener(_onBreachChanged);
    super.dispose();
  }

  void _onBreachChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _saveAutofillCapture() async {
    final candidate = widget.pendingAutofillSave;
    if (candidate == null ||
        candidate.id == _handledAutofillSaveId ||
        !mounted) {
      return;
    }
    _handledAutofillSaveId = candidate.id;
    if (widget.remoteSnapshot != null) {
      widget.onAutofillSaveHandled?.call();
      return;
    }
    final domain = candidate.domain;
    final service = _ServiceData(
      brand: _brandForService('${domain ?? ''} ${candidate.packageName}'),
      name: _nameFromAutofillDomain(domain),
      email: candidate.email,
      username: candidate.username,
      password: candidate.password,
      url: domain ?? '',
    );
    final alreadySaved = _services.any(
      (item) =>
          item.url.trim().toLowerCase() == service.url.trim().toLowerCase() &&
          item.email.trim().toLowerCase() ==
              service.email.trim().toLowerCase() &&
          item.username.trim().toLowerCase() ==
              service.username.trim().toLowerCase(),
    );
    if (alreadySaved) {
      widget.onAutofillSaveHandled?.call();
      return;
    }
    final now = DateTime.now().toUtc();
    final savedService = service.copyWith(
      id: _newId(),
      createdAt: now,
      updatedAt: now,
    );
    setState(() {
      _services.add(savedService);
      _ensureLinkedAccount(service.email);
      _recalculateServiceCounts();
    });
    await _persistChanges();
    if (mounted) {
      final label = service.name.isEmpty
          ? (domain ?? tr('Credencial'))
          : service.name;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              tx('$label adicionado ao cofre.', '$label added to the vault.'),
            ),
            action: SnackBarAction(
              label: tr('Desfazer'),
              onPressed: () => unawaited(_undoAutofillSave(savedService.id)),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      widget.onAutofillSaveHandled?.call();
    }
  }

  Future<void> _undoAutofillSave(String serviceId) async {
    if (!mounted) return;
    final index = _services.indexWhere((item) => item.id == serviceId);
    if (index < 0) return;
    setState(() {
      _services.removeAt(index);
      _recalculateServiceCounts();
    });
    await _persistChanges();
  }

  String _nameFromAutofillDomain(String? domain) {
    final host = domain?.trim().toLowerCase();
    if (host == null || host.isEmpty) return '';
    final first = host.replaceFirst(RegExp(r'^www\\.'), '').split('.').first;
    if (first.isEmpty) return '';
    return '${first[0].toUpperCase()}${first.substring(1)}';
  }

  void _setHealthFilter(String? value) {
    if (_healthFilter == value) return;
    setState(() => _healthFilter = value);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query != _query) {
      setState(() => _query = query);
    }
  }

  List<_AccountData> get _filteredAccounts {
    final accounts = _accounts
        .where(
          (account) =>
              _matches(account.email, account.provider) &&
              (!_favoritesOnly || account.favorite),
        )
        .toList();
    accounts.sort(
      (left, right) => _compareItems(
        nameA: left.label.isEmpty ? left.email : left.label,
        nameB: right.label.isEmpty ? right.email : right.label,
        createdA: left.createdAt,
        createdB: right.createdAt,
        updatedA: left.updatedAt,
        updatedB: right.updatedAt,
        favoriteA: left.favorite,
        favoriteB: right.favorite,
      ),
    );
    return accounts;
  }

  List<_ServiceData> get _filteredServices {
    final services = _services
        .where(
          (service) =>
              (_selectedAccountEmail == null ||
                  service.email.toLowerCase() ==
                      _selectedAccountEmail!.toLowerCase()) &&
              _matchesHealthFilter(service) &&
              _matches(service.name, service.email) &&
              (!_favoritesOnly || service.favorite),
        )
        .toList();
    services.sort(
      (left, right) => _compareItems(
        nameA: left.name,
        nameB: right.name,
        createdA: left.createdAt,
        createdB: right.createdAt,
        updatedA: left.updatedAt,
        updatedB: right.updatedAt,
        favoriteA: left.favorite,
        favoriteB: right.favorite,
      ),
    );
    return services;
  }

  int _compareItems({
    required String nameA,
    required String nameB,
    required DateTime? createdA,
    required DateTime? createdB,
    required DateTime? updatedA,
    required DateTime? updatedB,
    required bool favoriteA,
    required bool favoriteB,
  }) {
    if (_sort != _PasswordSort.favoritesFirst && favoriteA != favoriteB) {
      return favoriteA ? -1 : 1;
    }
    return switch (_sort) {
      _PasswordSort.favoritesFirst => 0,
      _PasswordSort.name => nameA.toLowerCase().compareTo(nameB.toLowerCase()),
      _PasswordSort.updated =>
        (updatedB ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          updatedA ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      _PasswordSort.created =>
        (createdB ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          createdA ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
    };
  }

  String get _organizationLabel {
    if (_favoritesOnly) return tr('Somente favoritos');
    return _passwordSortLabel(_sort);
  }

  Future<void> _openOrganizationSheet() async {
    final selection = await showModalBottomSheet<_OrganizationSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _OrganizationSheet(sort: _sort, favoritesOnly: _favoritesOnly),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _sort = selection.sort;
      _favoritesOnly = selection.favoritesOnly;
    });
  }

  bool _matchesHealthFilter(_ServiceData service) {
    return switch (_healthFilter) {
      'weak' => passwordLevel(service.password) <= 2,
      'reused' =>
        _services
                .where((item) => item.password.isNotEmpty)
                .where((item) => item.password == service.password)
                .length >
            1,
      'secure' => passwordLevel(service.password) >= 4,
      'compromised' => _isCompromised(service.id),
      _ => true,
    };
  }

  String? get _healthFilterLabel => switch (_healthFilter) {
    'weak' => tr('Fracas'),
    'reused' => tr('Reutilizadas'),
    'secure' => tr('Seguras'),
    'compromised' => tr('Comprometidas'),
    _ => null,
  };

  bool _matches(String first, String second) {
    return _query.isEmpty ||
        first.toLowerCase().contains(_query) ||
        second.toLowerCase().contains(_query);
  }

  int _serviceCountFor(String email) {
    return _services
        .where((service) => service.email.toLowerCase() == email.toLowerCase())
        .length;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_idCounter++}';

  void _ensureLinkedAccount(String email) {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty ||
        _accounts.any(
          (account) =>
              account.email.toLowerCase() == normalizedEmail.toLowerCase(),
        )) {
      return;
    }
    final now = DateTime.now().toUtc();
    final brand = _brandForEmail(normalizedEmail);
    _accounts.add(
      _AccountData(
        id: _newId(),
        createdAt: now,
        updatedAt: now,
        brand: brand,
        provider: _providerName(brand),
        email: normalizedEmail,
        services: 0,
      ),
    );
  }

  void _recalculateServiceCounts() {
    for (var index = 0; index < _accounts.length; index++) {
      final account = _accounts[index];
      final count = _serviceCountFor(account.email);
      if (count != account.services) {
        _accounts[index] = account.copyWith(services: count);
      }
    }
  }

  Future<void> _persistChanges() async {
    if (widget.remoteSnapshot != null) return;
    final vault = widget.vault;
    if (vault == null) return;
    final snapshot = vault.snapshot.copyWith(
      accounts: _accounts.map((account) => account.toVault()).toList(),
      services: _services.map((service) => service.toVault()).toList(),
    );
    try {
      await vault.replaceSnapshot(snapshot);
      if (mounted) widget.onVaultChanged?.call();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Não foi possível salvar as alterações.'),
            style: const TextStyle(fontFamily: 'Kumbh Sans'),
          ),
        ),
      );
    }
  }

  Future<void> _toggleAccountFavorite(_AccountData account) async {
    if (widget.remoteSnapshot != null) {
      await widget.onRemoteAction?.call(
        RemoteAction(RemoteActionKind.favoriteAccount, itemId: account.id),
      );
      return;
    }
    final index = _accounts.indexOf(account);
    if (index < 0) return;
    setState(() {
      _moveFavoriteToTop(
        _accounts,
        index,
        account.copyWith(favorite: !account.favorite),
      );
    });
    await _persistChanges();
  }

  Future<void> _toggleServiceFavorite(_ServiceData service) async {
    if (widget.remoteSnapshot != null) {
      await widget.onRemoteAction?.call(
        RemoteAction(RemoteActionKind.favoriteService, itemId: service.id),
      );
      return;
    }
    final index = _services.indexOf(service);
    if (index < 0) return;
    setState(() {
      _moveFavoriteToTop(
        _services,
        index,
        service.copyWith(favorite: !service.favorite),
      );
    });
    await _persistChanges();
  }

  void _moveFavoriteToTop<T extends dynamic>(
    List<T> items,
    int index,
    T updated,
  ) {
    final shouldPin = switch (updated) {
      _AccountData item => item.favorite,
      _ServiceData item => item.favorite,
      _ => false,
    };
    items.removeAt(index);
    if (shouldPin) {
      items.insert(0, updated);
      return;
    }

    final firstUnpinned = items.indexWhere((item) {
      return switch (item) {
        _AccountData value => !value.favorite,
        _ServiceData value => !value.favorite,
        _ => true,
      };
    });
    if (firstUnpinned < 0) {
      items.add(updated);
    } else {
      items.insert(firstUnpinned, updated);
    }
  }

  void _selectAccount(_AccountData account) {
    setState(() {
      _selectedAccountEmail =
          _selectedAccountEmail?.toLowerCase() == account.email.toLowerCase()
          ? null
          : account.email;
      if (_selectedAccountEmail != null) {
        _servicesExpanded = true;
      }
    });
  }

  Future<void> _openServiceDetails(_ServiceData service) async {
    final action = await showModalBottomSheet<_ServiceDetailsAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ServiceDetailsSheet(service: service),
    );
    if (!mounted || action == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    await _handleServiceAction(service, action);
  }

  Future<void> _handleServiceAction(
    _ServiceData service,
    _ServiceDetailsAction action,
  ) async {
    if (widget.remoteSnapshot != null) {
      await widget.onRemoteAction?.call(
        RemoteAction(
          action == _ServiceDetailsAction.delete
              ? RemoteActionKind.deleteService
              : RemoteActionKind.editService,
          itemId: service.id,
        ),
      );
      return;
    }
    final index = _services.indexOf(service);
    if (index < 0) return;
    if (action == _ServiceDetailsAction.delete) {
      final confirmed = await _confirmDeletion(
        title: tr('Excluir serviço?'),
        message: tr('Essa credencial será removida do cofre.'),
      );
      if (confirmed && mounted) {
        setState(() {
          _services.removeAt(index);
          _recalculateServiceCounts();
        });
        await _persistChanges();
      }
      return;
    }

    final edited = await showModalBottomSheet<_ServiceData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _AddCreationSheet(
          accounts: List.unmodifiable(_accounts),
          initialService: service,
        ),
      ),
    );
    if (edited != null && mounted) {
      final now = DateTime.now().toUtc();
      setState(() {
        _services[index] = edited.copyWith(
          id: service.id,
          createdAt: service.createdAt ?? now,
          updatedAt: now,
        );
        _ensureLinkedAccount(edited.email);
        _recalculateServiceCounts();
      });
      await _persistChanges();
    }
  }

  Future<void> _openAccountActions(_AccountData account) async {
    final action = await showModalBottomSheet<_ServiceDetailsAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemActionsSheet(
        editLabel: tr('Editar conta'),
        deleteLabel: tr('Excluir conta'),
      ),
    );
    if (!mounted || action == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    await _handleAccountAction(account, action);
  }

  Future<void> _handleAccountAction(
    _AccountData account,
    _ServiceDetailsAction action,
  ) async {
    if (widget.remoteSnapshot != null) {
      await widget.onRemoteAction?.call(
        RemoteAction(
          action == _ServiceDetailsAction.delete
              ? RemoteActionKind.deleteAccount
              : RemoteActionKind.editAccount,
          itemId: account.id,
        ),
      );
      return;
    }
    final index = _accounts.indexOf(account);
    if (index < 0) return;

    if (action == _ServiceDetailsAction.delete) {
      if (_serviceCountFor(account.email) > 0) {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _BottomSheetNotice(
            title: tr('Excluir conta?'),
            message: tr(
              'Esta conta possui serviços vinculados. Remova ou transfira esses serviços antes de excluir.',
            ),
            buttonLabel: tr('Entendi'),
          ),
        );
        return;
      }
      final confirmed = await _confirmDeletion(
        title: tr('Excluir conta?'),
        message: tr('Essa conta será removida do cofre.'),
      );
      if (confirmed && mounted) {
        setState(() {
          _accounts.removeAt(index);
          if (_selectedAccountEmail?.toLowerCase() ==
              account.email.toLowerCase()) {
            _selectedAccountEmail = null;
          }
        });
        await _persistChanges();
      }
      return;
    }

    final edited = await showModalBottomSheet<_AccountData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _AddCreationSheet(
          accounts: List.unmodifiable(_accounts),
          initialAccount: account,
        ),
      ),
    );
    if (edited != null && mounted) {
      final now = DateTime.now().toUtc();
      setState(() {
        if (edited.email.toLowerCase() != account.email.toLowerCase()) {
          if (_selectedAccountEmail?.toLowerCase() ==
              account.email.toLowerCase()) {
            _selectedAccountEmail = edited.email;
          }
          for (
            var serviceIndex = 0;
            serviceIndex < _services.length;
            serviceIndex++
          ) {
            final service = _services[serviceIndex];
            if (service.email.toLowerCase() == account.email.toLowerCase()) {
              _services[serviceIndex] = service.copyWith(
                email: edited.email,
                updatedAt: now,
              );
            }
          }
        }
        _accounts[index] = edited.copyWith(
          id: account.id,
          createdAt: account.createdAt ?? now,
          updatedAt: now,
        );
        _recalculateServiceCounts();
      });
      await _persistChanges();
    }
  }

  Future<bool> _confirmDeletion({
    required String title,
    required String message,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _BottomSheetConfirmation(title: title, message: message),
      ) ??
      false;

  Future<void> _openAddSelector([_AddChoice? initialChoice]) async {
    final choice =
        initialChoice ??
        await showModalBottomSheet<_AddChoice>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (sheetContext) => _AddChoiceSheet(
            onChoice: (value) => Navigator.of(sheetContext).pop(value),
          ),
        );

    if (!mounted || choice == null) return;
    if (widget.remoteSnapshot != null) {
      await widget.onRemoteAction?.call(
        RemoteAction(
          choice == _AddChoice.account
              ? RemoteActionKind.addAccount
              : RemoteActionKind.addService,
        ),
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _AddCreationSheet(
          accounts: List.unmodifiable(_accounts),
          initialMode: choice == _AddChoice.account
              ? _CreationMode.account
              : _CreationMode.service,
        ),
      ),
    );

    if (!mounted || result == null) return;
    final now = DateTime.now().toUtc();
    setState(() {
      if (result case final _AccountData account) {
        _accounts.add(
          account.copyWith(id: _newId(), createdAt: now, updatedAt: now),
        );
      } else if (result case final _ServiceData service) {
        _services.add(
          service.copyWith(id: _newId(), createdAt: now, updatedAt: now),
        );
        _ensureLinkedAccount(service.email);
        _recalculateServiceCounts();
      }
    });
    await _persistChanges();
  }

  bool _isCompromised(String id) =>
      widget.breachCheck?.isCompromised(id) == true ||
      widget.remoteSnapshot?.breachChecks[id]?.compromised == true;

  /// Entry point for authenticated requests, always executed by the phone UI.
  Future<bool> handleRemoteAction(RemoteAction action) async {
    if (widget.vault == null || widget.remoteSnapshot != null) return false;
    final before = widget.vault!.snapshot.encode();
    switch (action.kind) {
      case RemoteActionKind.addAccount:
        await _openAddSelector(_AddChoice.account);
      case RemoteActionKind.addService:
        await _openAddSelector(_AddChoice.service);
      case RemoteActionKind.editAccount:
      case RemoteActionKind.deleteAccount:
      case RemoteActionKind.favoriteAccount:
        final account = _accounts
            .where((a) => a.id == action.itemId)
            .firstOrNull;
        if (account == null) return false;
        if (action.kind == RemoteActionKind.favoriteAccount) {
          await _toggleAccountFavorite(account);
        } else {
          await _handleAccountAction(
            account,
            action.kind == RemoteActionKind.deleteAccount
                ? _ServiceDetailsAction.delete
                : _ServiceDetailsAction.edit,
          );
        }
      case RemoteActionKind.editService:
      case RemoteActionKind.deleteService:
      case RemoteActionKind.favoriteService:
        final service = _services
            .where((s) => s.id == action.itemId)
            .firstOrNull;
        if (service == null) return false;
        if (action.kind == RemoteActionKind.favoriteService) {
          await _toggleServiceFavorite(service);
        } else {
          await _handleServiceAction(
            service,
            action.kind == RemoteActionKind.deleteService
                ? _ServiceDetailsAction.delete
                : _ServiceDetailsAction.edit,
          );
        }
    }
    await widget.vault!.flush();
    return before != widget.vault!.snapshot.encode();
  }

  Widget _desktopPasswords(
    List<_AccountData> accounts,
    List<_ServiceData> services,
    int weakCount,
    int? compromisedCount,
  ) {
    return DesktopPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopHeading(
            tr('Minhas senhas'),
            trailing: FilledButton.icon(
              onPressed: _openAddSelector,
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Adicionar')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          _SearchField(controller: _searchController),
          _OrganizationButton(
            key: const ValueKey('passwords-organize'),
            onTap: _openOrganizationSheet,
            currentLabel: _organizationLabel,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _healthFilterLabel == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _HealthFilterNotice(
                      label: _healthFilterLabel!,
                      onClear: () => _setHealthFilter(null),
                    ),
                  ),
          ),
          if (weakCount > 0 && !_weakAlertDismissed)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SecurityAlert(
                icon: Icons.warning_amber_rounded,
                color: AppPalette.resolve(const Color(0xFFDF820F)),
                title: tr('Existem senhas fracas'),
                message: tr(
                  'Atualize suas senhas para proteger melhor suas contas.',
                ),
                onClose: () => setState(() => _weakAlertDismissed = true),
                onTap: () => _setHealthFilter('weak'),
              ),
            ),
          if ((compromisedCount ?? 0) > 0 && !_compromisedAlertDismissed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SecurityAlert(
                icon: Icons.shield_outlined,
                color: AppPalette.resolve(const Color(0xFFE65353)),
                title: tr('Existem senhas comprometidas'),
                message: tr(
                  'Essas senhas apareceram em vazamentos conhecidos e devem ser alteradas.',
                ),
                onClose: () =>
                    setState(() => _compromisedAlertDismissed = true),
                onTap: () => _setHealthFilter('compromised'),
              ),
            ),
          const SizedBox(height: 28),
          DesktopSurface(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Contas'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    Text(
                      '${accounts.length}',
                      style: TextStyle(fontSize: 15, color: desktopMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (accounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      tr('Nenhuma conta encontrada.'),
                      style: TextStyle(fontSize: 14, color: desktopMuted),
                    ),
                  )
                else
                  _AccountsList(
                    key: ValueKey('desktop-accounts-$_query'),
                    accounts: accounts,
                    selectedEmail: _selectedAccountEmail,
                    onAccountTap: _selectAccount,
                    onFavoriteToggle: _toggleAccountFavorite,
                    onActions: _openAccountActions,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          DesktopSurface(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Serviços'),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    Text(
                      '${services.length}',
                      style: TextStyle(fontSize: 15, color: desktopMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_selectedAccountEmail != null)
                  _SelectedAccountFilter(
                    email: _selectedAccountEmail!,
                    onClear: () => setState(() => _selectedAccountEmail = null),
                  ),
                if (services.isEmpty)
                  _EmptyServicesState(
                    hasSelectedAccount: _selectedAccountEmail != null,
                    onAdd: _openAddSelector,
                  )
                else
                  _ServicesList(
                    key: ValueKey(
                      'desktop-services-$_healthFilter-$_query-$_selectedAccountEmail',
                    ),
                    services: services,
                    onServiceTap: _openServiceDetails,
                    onFavoriteToggle: _toggleServiceFavorite,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final accounts = _filteredAccounts;
    final services = _filteredServices;
    final accountMembership = List<_AccountData>.of(accounts)
      ..sort((left, right) {
        final leftId = left.id.isEmpty ? left.email : left.id;
        final rightId = right.id.isEmpty ? right.email : right.id;
        return leftId.compareTo(rightId);
      });
    final weakCount = _services
        .where(
          (service) =>
              service.password.isNotEmpty &&
              passwordLevel(service.password) <= 2,
        )
        .length;
    final compromisedCount =
        widget.breachCheck?.compromisedCount ??
        (widget.remoteSnapshot == null
            ? null
            : _services.where((s) => _isCompromised(s.id)).length);

    if (isWindowsDesktop) {
      return _desktopPasswords(accounts, services, weakCount, compromisedCount);
    }

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FloatingActionButton.extended(
          onPressed: _openAddSelector,
          backgroundColor: AppPalette.resolve(const Color(0xFF347BFF)),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.add, size: 24),
          label: Text(tr('Adicionar'), style: AppTypography.buttonLabel),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: widget.showBottomNavigation
          ? const SafeArea(top: false, child: _PasswordsBottomNavigation())
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _PasswordsHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SearchField(controller: _searchController),
                    _OrganizationButton(
                      key: const ValueKey('passwords-organize'),
                      onTap: _openOrganizationSheet,
                      currentLabel: _organizationLabel,
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => SizeTransition(
                        sizeFactor: animation,
                        axis: Axis.vertical,
                        alignment: Alignment.topCenter,
                        child: FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -.22),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      ),
                      child: _healthFilterLabel == null
                          ? const SizedBox.shrink(key: ValueKey('no-filter'))
                          : Padding(
                              key: ValueKey(_healthFilterLabel),
                              padding: const EdgeInsets.only(top: 10),
                              child: _HealthFilterNotice(
                                label: _healthFilterLabel!,
                                onClear: () => _setHealthFilter(null),
                              ),
                            ),
                    ),
                    if (widget.vault == null) ...[
                      const SizedBox(height: 12),
                      const SecurityAlert(),
                      const SizedBox(height: 18),
                    ] else ...[
                      if (weakCount > 0 && !_weakAlertDismissed) ...[
                        const SizedBox(height: 12),
                        SecurityAlert(
                          icon: Icons.warning_amber_rounded,
                          color: AppPalette.resolve(const Color(0xFFFF8A00)),
                          title: tr('Existem senhas fracas'),
                          message: tr(
                            'Atualize suas senhas para proteger melhor suas contas.',
                          ),
                          onClose: () =>
                              setState(() => _weakAlertDismissed = true),
                          onTap: () => _setHealthFilter('weak'),
                        ),
                      ],
                      if (compromisedCount != null &&
                          compromisedCount > 0 &&
                          !_compromisedAlertDismissed) ...[
                        const SizedBox(height: 10),
                        SecurityAlert(
                          icon: Icons.shield_outlined,
                          color: AppPalette.resolve(const Color(0xFFFF5F59)),
                          title: tr('Existem senhas comprometidas'),
                          message: tr(
                            'Essas senhas apareceram em vazamentos conhecidos e devem ser alteradas.',
                          ),
                          onClose: () =>
                              setState(() => _compromisedAlertDismissed = true),
                          onTap: () => _setHealthFilter('compromised'),
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],
                    _CollapsibleSectionHeader(
                      title: tr('Contas'),
                      expanded: _accountsExpanded,
                      onTap: () => setState(
                        () => _accountsExpanded = !_accountsExpanded,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_accountsExpanded
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: accounts.isEmpty
                                  ? _query.isNotEmpty
                                        ? _EmptySearchResult(
                                            onClear: _searchController.clear,
                                          )
                                        : const _EmptyAccountsState()
                                  : _AccountsList(
                                      key: ValueKey(
                                        accountMembership
                                            .map(
                                              (account) => account.id.isEmpty
                                                  ? account.email
                                                  : account.id,
                                            )
                                            .join('|'),
                                      ),
                                      accounts: accounts,
                                      selectedEmail: _selectedAccountEmail,
                                      onAccountTap: _selectAccount,
                                      onFavoriteToggle: _toggleAccountFavorite,
                                      onActions: _openAccountActions,
                                    ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    _CollapsibleSectionHeader(
                      title: tr('Serviços'),
                      expanded: _servicesExpanded,
                      onTap: () => setState(
                        () => _servicesExpanded = !_servicesExpanded,
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_servicesExpanded
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: services.isEmpty
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_selectedAccountEmail != null)
                                          _SelectedAccountFilter(
                                            email: _selectedAccountEmail!,
                                            onClear: () => setState(
                                              () =>
                                                  _selectedAccountEmail = null,
                                            ),
                                          ),
                                        if (_query.isNotEmpty)
                                          _EmptySearchResult(
                                            onClear: _searchController.clear,
                                          )
                                        else
                                          _EmptyServicesState(
                                            hasSelectedAccount:
                                                _selectedAccountEmail != null,
                                            onAdd: _openAddSelector,
                                          ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        if (_selectedAccountEmail != null)
                                          _SelectedAccountFilter(
                                            email: _selectedAccountEmail!,
                                            onClear: () => setState(
                                              () =>
                                                  _selectedAccountEmail = null,
                                            ),
                                          ),
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          transitionBuilder:
                                              (child, animation) =>
                                                  FadeTransition(
                                                    opacity: animation,
                                                    child: SizeTransition(
                                                      sizeFactor: animation,
                                                      axis: Axis.vertical,
                                                      alignment:
                                                          Alignment.topCenter,
                                                      child: SlideTransition(
                                                        position: Tween<Offset>(
                                                          begin: const Offset(
                                                            0,
                                                            .035,
                                                          ),
                                                          end: Offset.zero,
                                                        ).animate(animation),
                                                        child: child,
                                                      ),
                                                    ),
                                                  ),
                                          child: _ServicesList(
                                            key: ValueKey(
                                              '$_healthFilter-$_query-${_selectedAccountEmail ?? ''}',
                                            ),
                                            services: services,
                                            onServiceTap: _openServiceDetails,
                                            onFavoriteToggle:
                                                _toggleServiceFavorite,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetNotice extends StatelessWidget {
  const _BottomSheetNotice({
    required this.title,
    required this.message,
    required this.buttonLabel,
  });

  final String title;
  final String message;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BottomSheetHandle(),
              const SizedBox(height: 20),
              Text(title, style: AppTypography.sectionTitle),
              const SizedBox(height: 12),
              Text(message, style: AppTypography.secondary),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(buttonLabel, style: AppTypography.buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSheetConfirmation extends StatelessWidget {
  const _BottomSheetConfirmation({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BottomSheetHandle(),
              const SizedBox(height: 20),
              Text(title, style: AppTypography.sectionTitle),
              const SizedBox(height: 12),
              Text(message, style: AppTypography.secondary),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppPalette.resolve(const Color(0xFFD6DAE7)),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(tr('Cancelar')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.resolve(
                          const Color(0xFFE65353),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(tr('Excluir')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrganizationSelection {
  const _OrganizationSelection({
    required this.sort,
    required this.favoritesOnly,
  });

  final _PasswordSort sort;
  final bool favoritesOnly;
}

class _OrganizationButton extends StatelessWidget {
  const _OrganizationButton({
    required this.onTap,
    required this.currentLabel,
    super.key,
  });

  final VoidCallback onTap;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Tooltip(
          message: currentLabel,
          child: TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(tr('Organizar')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrganizationSheet extends StatefulWidget {
  const _OrganizationSheet({required this.sort, required this.favoritesOnly});

  final _PasswordSort sort;
  final bool favoritesOnly;

  @override
  State<_OrganizationSheet> createState() => _OrganizationSheetState();
}

class _OrganizationSheetState extends State<_OrganizationSheet> {
  late _PasswordSort _sort = widget.sort;
  late bool _favoritesOnly = widget.favoritesOnly;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SafeArea(
      top: false,
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BottomSheetHandle(),
              const SizedBox(height: 18),
              Text(tr('Organizar senhas'), style: AppTypography.sectionTitle),
              const SizedBox(height: 12),
              ..._PasswordSort.values.map(
                (sort) => ListTile(
                  onTap: () => setState(() => _sort = sort),
                  leading: Icon(
                    sort == _sort
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: sort == _sort
                        ? AppColors.blue
                        : AppPalette.resolve(const Color(0xFF9AA4B7)),
                  ),
                  title: Text(_passwordSortLabel(sort)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              SwitchListTile(
                value: _favoritesOnly,
                onChanged: (value) => setState(() => _favoritesOnly = value),
                title: Text(tr('Mostrar somente favoritos')),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.blue,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _OrganizationSelection(
                    sort: _sort,
                    favoritesOnly: _favoritesOnly,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(tr('Aplicar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSheetHandle extends StatelessWidget {
  const _BottomSheetHandle();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Center(
      child: Container(
        width: isWindowsDesktop ? 0 : 38,
        height: isWindowsDesktop ? 0 : 4,
        decoration: BoxDecoration(
          color: AppPalette.resolve(const Color(0xFFDCE2EC)),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

enum _AddChoice { account, service }

class _AddChoiceSheet extends StatelessWidget {
  const _AddChoiceSheet({required this.onChoice});

  final ValueChanged<_AddChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppPalette.resolve(Colors.white),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 38,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFDCE2EC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                tr('O que deseja adicionar?'),
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: 10),
              _AddChoiceTile(
                icon: Icons.alternate_email,
                title: tr('Adicionar conta'),
                description: tr(
                  'Cadastre um email principal para vincular serviços.',
                ),
                onTap: () => onChoice(_AddChoice.account),
              ),
              const SizedBox(height: 8),
              _AddChoiceTile(
                icon: Icons.language_outlined,
                title: tr('Adicionar serviço'),
                description: tr('Guarde o acesso de um site ou aplicativo.'),
                onTap: () => onChoice(_AddChoice.service),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChoiceTile extends StatelessWidget {
  const _AddChoiceTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppPalette.resolve(const Color(0xFFF7F9FE)),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppPalette.resolve(const Color(0xFFE5EDFF)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AppPalette.resolve(const Color(0xFF347BFF)),
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.itemTitle),
                    const SizedBox(height: 4),
                    Text(description, style: AppTypography.secondary),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8993A8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCreationSheet extends StatefulWidget {
  const _AddCreationSheet({
    required this.accounts,
    this.initialMode,
    this.initialAccount,
    this.initialService,
  });

  final List<_AccountData> accounts;
  final _CreationMode? initialMode;
  final _AccountData? initialAccount;
  final _ServiceData? initialService;

  @override
  State<_AddCreationSheet> createState() => _AddCreationSheetState();
}

enum _CreationMode { account, service }

class _AddCreationSheetState extends State<_AddCreationSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menuAnimation;
  bool _switchingMenu = false;
  final _accountFocus = FocusNode();
  bool _showAccounts = false;
  String? _accountError;
  String? _urlError;
  final _emailController = TextEditingController();
  final _labelController = TextEditingController();
  final _noteController = TextEditingController();
  final _usernameController = TextEditingController();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serviceNameController = TextEditingController();
  final _urlController = TextEditingController();

  _CreationMode? _mode;
  int _serviceStep = 0;
  String? _selectedEmail;
  String? _errorText;
  bool _passwordVisible = false;
  bool _generatorExpanded = false;

  @override
  void initState() {
    super.initState();
    _menuAnimation = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 170),
    );
    _emailController.addListener(_refresh);
    _accountFocus.addListener(_onAccountFocus);
    _passwordController.addListener(_refresh);
    _accountController.addListener(_refreshAccount);
    _serviceNameController.addListener(_refresh);
    _urlController.addListener(_refresh);

    final initialAccount = widget.initialAccount;
    final initialService = widget.initialService;
    if (initialAccount != null) {
      _mode = _CreationMode.account;
      _emailController.text = initialAccount.email;
      _labelController.text = initialAccount.label;
      _noteController.text = initialAccount.note;
    } else if (initialService != null) {
      _mode = _CreationMode.service;
      _usernameController.text = initialService.username;
      _accountController.text = initialService.email;
      _passwordController.text = initialService.password;
      _serviceNameController.text = initialService.name;
      _urlController.text = initialService.url;
      _selectedEmail = initialService.email.isEmpty
          ? null
          : initialService.email;
    } else {
      _mode = widget.initialMode;
    }
  }

  @override
  void dispose() {
    _menuAnimation.dispose();
    _accountFocus.dispose();
    _emailController
      ..removeListener(_refresh)
      ..dispose();
    _accountController
      ..removeListener(_refreshAccount)
      ..dispose();
    _serviceNameController
      ..removeListener(_refresh)
      ..dispose();
    _urlController
      ..removeListener(_refresh)
      ..dispose();
    _labelController.dispose();
    _noteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {
    _errorText = null;
    _urlError = null;
  });

  void _onAccountFocus() => setState(() {
    _showAccounts = _accountFocus.hasFocus && _selectedEmail == null;
  });

  void _refreshAccount() {
    final text = _accountController.text.trim();
    if (_selectedEmail != null && _selectedEmail != text) {
      _selectedEmail = null;
    }
    setState(() {
      _accountError = null;
      _showAccounts = _accountFocus.hasFocus && _selectedEmail == null;
    });
  }

  Future<void> _selectMode(_CreationMode? mode) async {
    await _swapContent(() {
      _mode = mode;
      _serviceStep = 0;
      _errorText = null;
      _accountError = null;
      _urlError = null;
      _generatorExpanded = false;
    });
  }

  Future<void> _swapContent(VoidCallback change) async {
    if (_switchingMenu) return;
    _switchingMenu = true;
    FocusScope.of(context).unfocus();
    await _menuAnimation.reverse();
    if (!mounted) return;
    setState(change);
    await _menuAnimation.forward();
    _switchingMenu = false;
  }

  Future<void> _goBack() async {
    if (_mode == _CreationMode.service && _generatorExpanded) {
      await _swapContent(() => _generatorExpanded = false);
    } else if (_mode == _CreationMode.service && _serviceStep == 1) {
      await _swapContent(() => _serviceStep = 0);
    } else if (widget.initialAccount != null || widget.initialService != null) {
      Navigator.pop(context);
    } else if (_mode != null) {
      _selectMode(null);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _copyPassword() async {
    if (_passwordController.text.isEmpty) return;
    await SecureClipboard.copy(_passwordController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Senha copiada. ${SecureClipboard.clearAfterMessage}',
          style: const TextStyle(fontFamily: 'Kumbh Sans'),
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _saveAccount() {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _errorText = tr('Digite um email válido.'));
      return;
    }
    if (widget.accounts.any(
      (account) =>
          !identical(account, widget.initialAccount) &&
          account.email.toLowerCase() == email.toLowerCase(),
    )) {
      setState(() => _errorText = tr('Esta conta já está cadastrada.'));
      return;
    }
    Navigator.pop(
      context,
      _AccountData(
        brand: _brandForEmail(email),
        provider: _providerName(_brandForEmail(email)),
        email: email,
        services: 0,
        label: _labelController.text.trim(),
        note: _noteController.text.trim(),
        favorite: widget.initialAccount?.favorite ?? false,
      ),
    );
  }

  Future<void> _continueService() async {
    final email = _accountController.text.trim();
    if (email.isNotEmpty && !_isValidEmail(email)) {
      setState(
        () => _accountError = tr('Digite um email válido ou deixe em branco.'),
      );
      _accountFocus.requestFocus();
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(
        () => _errorText = tr('Digite uma senha ou gere uma senha forte.'),
      );
      return;
    }
    await _swapContent(() {
      _selectedEmail = _accountController.text.trim().isEmpty
          ? null
          : _accountController.text.trim();
      _errorText = null;
      _serviceStep = 1;
    });
  }

  void _saveService() {
    final url = _urlController.text.trim();
    if (url.isNotEmpty && _siteHost(url) == null) {
      setState(
        () => _urlError = tr('Informe um endereço válido, como github.com.'),
      );
      return;
    }
    final name = _serviceNameController.text.trim();
    final fallbackName = url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .split(RegExp(r'[/\s]'))
        .firstWhere((value) => value.isNotEmpty, orElse: () => tr('Serviço'));
    Navigator.pop(
      context,
      _ServiceData(
        brand: _brandForService('$name $url'),
        name: name.isEmpty ? fallbackName : name,
        email: _selectedEmail ?? '',
        url: url,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        favorite: widget.initialService?.favorite ?? false,
      ),
    );
  }

  Future<void> _useGeneratedPassword(String password) async {
    await _swapContent(() {
      _passwordController.text = password;
      _generatorExpanded = false;
    });
  }

  List<_AccountData> get _matchingAccounts {
    final query = _accountController.text.trim().toLowerCase();
    if (!_showAccounts) return [];
    return widget.accounts
        .where((account) => account.email.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _menuAnimation,
              curve: Curves.easeInOutCubic,
            ),
          ),
      child: Material(
        color: AppPalette.resolve(Colors.white),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (height * .9 - MediaQuery.viewInsetsOf(context).bottom)
                  .clamp(150.0, height),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mode != null)
                  _CreationHeader(
                    title: _mode == _CreationMode.account
                        ? widget.initialAccount == null
                              ? tr('Adicionar conta')
                              : tr('Editar conta')
                        : widget.initialService == null
                        ? tr('Adicionar serviço')
                        : tr('Editar serviço'),
                    onBack: _goBack,
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: KeyedSubtree(
                          key: ValueKey('$_mode-$_serviceStep'),
                          child: _mode == null
                              ? _AddChoiceSheet(
                                  onChoice: (choice) {
                                    _selectMode(
                                      choice == _AddChoice.account
                                          ? _CreationMode.account
                                          : _CreationMode.service,
                                    );
                                  },
                                )
                              : _mode == _CreationMode.account
                              ? _buildAccountForm()
                              : _buildServiceForm(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_mode != null)
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(22, 8, 22, 14),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _mode == _CreationMode.account
                            ? _saveAccount
                            : _serviceStep == 0
                            ? _continueService
                            : _saveService,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.resolve(
                            const Color(0xFF347BFF),
                          ),
                          textStyle: AppTypography.buttonLabel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _mode == _CreationMode.account
                              ? widget.initialAccount == null
                                    ? tr('Salvar conta')
                                    : tr('Salvar alterações')
                              : _serviceStep == 0
                              ? tr('Continuar')
                              : widget.initialService == null
                              ? tr('Salvar serviço')
                              : tr('Salvar alterações'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountForm() {
    final brand = _brandForEmail(_emailController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(tr('Email principal')),
        _EntryField(
          controller: _emailController,
          hintText: 'voce@exemplo.com',
          keyboardType: TextInputType.emailAddress,
          maxLength: 320,
          prefix: _BrandIcon(brand: brand),
          errorText: _errorText,
        ),
        if (_emailController.text.trim().isNotEmpty && _errorText == null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              brand == _Brand.genericEmail
                  ? tr('Provedor não identificado')
                  : 'Provedor identificado: ${_providerName(brand)}',
              style: AppTypography.secondary.copyWith(
                color: brand == _Brand.genericEmail
                    ? AppColors.bodyText
                    : AppColors.success,
              ),
            ),
          ),
        const SizedBox(height: 18),
        _FormLabel(tr('Nome para organização (opcional)')),
        _EntryField(
          controller: _labelController,
          hintText: tr('Pessoal, trabalho ou faculdade'),
          maxLength: 160,
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('Observação (opcional)')),
        _EntryField(
          controller: _noteController,
          hintText: tr('Uma anotação curta'),
          maxLines: 3,
          maxLength: 1000,
        ),
      ],
    );
  }

  Widget _buildServiceForm() {
    if (_serviceStep == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FormLabel(tr('Nome do serviço (opcional)')),
          _EntryField(
            controller: _serviceNameController,
            hintText: tr('GitHub, Netflix ou PayPal'),
            maxLength: 200,
            prefix: _BrandIcon(
              address: _urlController.text,
              brand: _brandForService(
                '${_serviceNameController.text} ${_urlController.text}',
              ),
            ),
          ),
          const SizedBox(height: 18),
          _FormLabel(tr('URL ou domínio (opcional)')),
          _EntryField(
            controller: _urlController,
            hintText: 'github.com',
            keyboardType: TextInputType.url,
            errorText: _urlError,
            maxLength: 2048,
          ),
          if (_urlController.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                _providerName(_brandForService(_urlController.text)),
                style: AppTypography.secondary,
              ),
            ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: () {
                _serviceNameController.clear();
                _urlController.clear();
                _saveService();
              },
              child: Text(tr('Pular esta etapa')),
            ),
          ),
        ],
      );
    }

    final matches = _matchingAccounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FormLabel(tr('Usuário (opcional)')),
        _EntryField(
          controller: _usernameController,
          hintText: tr('Seu usuário no serviço'),
          maxLength: 320,
        ),
        const SizedBox(height: 18),
        _FormLabel(tr('Conta vinculada (opcional)')),
        _EntryField(
          controller: _accountController,
          focusNode: _accountFocus,
          errorText: _accountError,
          hintText: tr('Digite ou selecione um email'),
          keyboardType: TextInputType.emailAddress,
          maxLength: 320,
          prefix: _accountController.text.trim().isEmpty
              ? const Icon(Icons.alternate_email, color: Color(0xFF347BFF))
              : _BrandIcon(brand: _brandForEmail(_accountController.text)),
        ),
        if (matches.isNotEmpty)
          _AccountSuggestions(
            accounts: matches,
            onSelected: (account) {
              _accountController.text = account.email;
              _accountController.selection = TextSelection.collapsed(
                offset: account.email.length,
              );
              _selectedEmail = account.email;
              _accountFocus.unfocus();
              setState(() => _showAccounts = false);
            },
          )
        else if (_selectedEmail == null &&
            _isValidEmail(_accountController.text.trim()) &&
            !widget.accounts.any(
              (a) =>
                  a.email.toLowerCase() ==
                  _accountController.text.trim().toLowerCase(),
            ))
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              tr('Este email será registrado como uma nova conta.'),
              style: AppTypography.secondary.copyWith(color: AppColors.success),
            ),
          ),
        const SizedBox(height: 18),
        _FormLabel(tr('Senha')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EntryField(
                controller: _passwordController,
                hintText: tr('Digite uma senha forte'),
                obscureText: !_passwordVisible,
                animatePassword: true,
                errorText: _errorText,
                maxLength: 4096,
                suffix: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('Copiar senha'),
                      onPressed: _copyPassword,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: _passwordVisible
                          ? tr('Ocultar senha')
                          : tr('Mostrar senha'),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _GeneratePasswordButton(
              onTap: () =>
                  _swapContent(() => _generatorExpanded = !_generatorExpanded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _passwordController,
          builder: (_, value, __) => PasswordStrengthBar(password: value.text),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: _generatorExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _EmbeddedPasswordGenerator(
                    initialPassword: _passwordController.text,
                    onUse: _useGeneratedPassword,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CreationHeader extends StatelessWidget {
  const _CreationHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 24, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('Voltar'),
              onPressed: onBack,
              icon: Icon(Icons.arrow_back_rounded, color: AppColors.navy),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: isWindowsDesktop ? 0 : 38,
          height: isWindowsDesktop ? 0 : 4,
          decoration: BoxDecoration(
            color: AppPalette.resolve(const Color(0xFFDCE2EC)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Voltar'),
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, color: AppColors.navy),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.appPageTitle,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmbeddedPasswordGenerator extends StatefulWidget {
  const _EmbeddedPasswordGenerator({
    required this.initialPassword,
    required this.onUse,
  });

  final String initialPassword;
  final ValueChanged<String> onUse;

  @override
  State<_EmbeddedPasswordGenerator> createState() =>
      _EmbeddedPasswordGeneratorState();
}

class _EmbeddedPasswordGeneratorState
    extends State<_EmbeddedPasswordGenerator> {
  String _password = '';
  int _length = 16;
  bool _customizeExpanded = false;
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _avoidSimilar = true;

  @override
  void initState() {
    super.initState();
    _password = createStrongPassword(length: _length);
  }

  void _regenerate() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_length == 0) _length = 8;
      _password = createStrongPassword(
        length: _length,
        uppercase: _uppercase,
        lowercase: _lowercase,
        numbers: _numbers,
        symbols: _symbols,
        avoidSimilar: _avoidSimilar,
      );
      _length = _password.length;
    });
  }

  void _updateOption(bool value, void Function(bool) update) {
    HapticFeedback.selectionClick();
    setState(() {
      update(value);
      _password = removeDisabledPasswordCharacters(
        _password,
        uppercase: _uppercase,
        lowercase: _lowercase,
        numbers: _numbers,
        symbols: _symbols,
        avoidSimilar: _avoidSimilar,
      );
      _length = _password.length;
    });
  }

  void _updateLength(double value) {
    final nextLength = value.round();
    if (nextLength == _length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _length = nextLength;
      _password = resizeExistingPassword(
        _password,
        length: nextLength,
        uppercase: _uppercase,
        lowercase: _lowercase,
        numbers: _numbers,
        symbols: _symbols,
        avoidSimilar: _avoidSimilar,
      );
      _length = _password.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          decoration: BoxDecoration(
            color: AppPalette.resolve(const Color(0xFFF8F9FC)),
            border: Border.all(
              color: AppPalette.resolve(const Color(0xFFE1E6F0)),
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Expanded(
                child: _password.isEmpty
                    ? Text(
                        tr('Ative pelo menos um tipo de caractere para gerar.'),
                        style: AppTypography.secondary,
                      )
                    : AnimatedPasswordText(
                        password: _password,
                        backgroundColor: AppPalette.resolve(
                          const Color(0xFFF8F9FC),
                        ),
                      ),
              ),
              IconButton(
                tooltip: tr('Gerar outra senha'),
                onPressed: _uppercase || _lowercase || _numbers || _symbols
                    ? _regenerate
                    : null,
                icon: const Icon(Icons.refresh, color: Color(0xFF347BFF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        PasswordStrengthBar(password: _password),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _password.isEmpty ? null : () => widget.onUse(_password),
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.resolve(const Color(0xFF347BFF)),
              textStyle: AppTypography.buttonLabel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(tr('Usar esta senha')),
          ),
        ),
        const SizedBox(height: 12),
        _SheetCustomizeCard(
          expanded: _customizeExpanded,
          length: _length,
          uppercase: _uppercase,
          lowercase: _lowercase,
          numbers: _numbers,
          symbols: _symbols,
          avoidSimilar: _avoidSimilar,
          onToggle: () =>
              setState(() => _customizeExpanded = !_customizeExpanded),
          onLengthChanged: _updateLength,
          onUppercaseChanged: (value) =>
              _updateOption(value, (next) => _uppercase = next),
          onLowercaseChanged: (value) =>
              _updateOption(value, (next) => _lowercase = next),
          onNumbersChanged: (value) =>
              _updateOption(value, (next) => _numbers = next),
          onSymbolsChanged: (value) =>
              _updateOption(value, (next) => _symbols = next),
          onAvoidSimilarChanged: (value) =>
              _updateOption(value, (next) => _avoidSimilar = next),
        ),
      ],
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: AppTypography.itemTitle),
    );
  }
}

class _EntryField extends StatelessWidget {
  const _EntryField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.prefix,
    this.suffix,
    this.obscureText = false,
    this.maxLines = 1,
    this.maxLength,
    this.errorText,
    this.focusNode,
    this.animatePassword = false,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscureText;
  final int maxLines;
  final int? maxLength;
  final String? errorText;
  final FocusNode? focusNode;
  final bool animatePassword;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboardType,
      obscureText: obscureText,
      obscuringCharacter: '*',
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      style: AppTypography.itemTitle,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: AppTypography.secondary,
        errorText: errorText,
        prefixIcon: prefix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: prefix,
              ),
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: 54,
          height: 48,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppPalette.resolve(const Color(0xFFF8F9FC)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: AppPalette.resolve(const Color(0xFFE1E6F0)),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: AppPalette.resolve(const Color(0xFFE1E6F0)),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFF347BFF), width: 1.4),
        ),
      ),
    );
    if (!animatePassword) return field;
    return _AnimatedPasswordEntry(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      style: AppTypography.itemTitle,
      decoration: field.decoration ?? const InputDecoration(),
    );
  }
}

class _AnimatedPasswordEntry extends StatefulWidget {
  const _AnimatedPasswordEntry({
    required this.controller,
    required this.keyboardType,
    required this.obscureText,
    required this.maxLines,
    required this.maxLength,
    required this.style,
    required this.decoration,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final int? maxLength;
  final TextStyle style;
  final InputDecoration decoration;

  @override
  State<_AnimatedPasswordEntry> createState() => _AnimatedPasswordEntryState();
}

class _AnimatedPasswordEntryState extends State<_AnimatedPasswordEntry> {
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final overlayRight = widget.decoration.suffixIcon == null ? 14.0 : 100.0;
    return Stack(
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscureText,
          obscuringCharacter: '*',
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          buildCounter:
              (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
          style: widget.style.copyWith(color: Colors.transparent),
          cursorColor: AppColors.blue,
          decoration: widget.decoration,
        ),
        Positioned(
          left: 14,
          right: overlayRight,
          top: 9,
          height: 32,
          child: IgnorePointer(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, child) => AnimatedPasswordText(
                password: value.text,
                obscured: widget.obscureText,
                style: widget.style,
                cellWidth: 16,
                followEnd: true,
                backgroundColor:
                    widget.decoration.fillColor ??
                    AppPalette.resolve(Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountSuggestions extends StatelessWidget {
  const _AccountSuggestions({required this.accounts, required this.onSelected});

  final List<_AccountData> accounts;
  final ValueChanged<_AccountData> onSelected;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border.all(color: AppPalette.resolve(const Color(0xFFE1E6F0))),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          for (var index = 0; index < accounts.length; index++) ...[
            Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _BrandIcon(brand: accounts[index].brand),
                title: Text(
                  accounts[index].email,
                  style: AppTypography.itemTitle,
                ),
                onTap: () => onSelected(accounts[index]),
              ),
            ),
            if (index < accounts.length - 1)
              Divider(
                height: 1,
                color: AppPalette.resolve(const Color(0xFFF0F2F6)),
              ),
          ],
        ],
      ),
    );
  }
}

class _GeneratePasswordButton extends StatelessWidget {
  const _GeneratePasswordButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      width: 54,
      height: 54,
      child: Material(
        color: AppPalette.resolve(const Color(0xFFEAF0FF)),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: const Icon(
            Icons.auto_awesome,
            color: Color(0xFF347BFF),
            size: 23,
          ),
        ),
      ),
    );
  }
}

class _SheetCustomizeCard extends StatelessWidget {
  const _SheetCustomizeCard({
    required this.expanded,
    required this.length,
    required this.uppercase,
    required this.lowercase,
    required this.numbers,
    required this.symbols,
    required this.avoidSimilar,
    required this.onToggle,
    required this.onLengthChanged,
    required this.onUppercaseChanged,
    required this.onLowercaseChanged,
    required this.onNumbersChanged,
    required this.onSymbolsChanged,
    required this.onAvoidSimilarChanged,
  });

  final bool expanded;
  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool numbers;
  final bool symbols;
  final bool avoidSimilar;
  final VoidCallback onToggle;
  final ValueChanged<double> onLengthChanged;
  final ValueChanged<bool> onUppercaseChanged;
  final ValueChanged<bool> onLowercaseChanged;
  final ValueChanged<bool> onNumbersChanged;
  final ValueChanged<bool> onSymbolsChanged;
  final ValueChanged<bool> onAvoidSimilarChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppPalette.resolve(const Color(0xFFE1E6F0))),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Personalizar senha'),
                      style: AppTypography.itemTitle,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppPalette.resolve(const Color(0xFF8993A8)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(tr('Tamanho'), style: AppTypography.secondary),
                            Text(
                              tx('$length caracteres', '$length characters'),
                              style: AppTypography.secondary,
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            activeTrackColor: AppPalette.resolve(
                              const Color(0xFF347BFF),
                            ),
                            inactiveTrackColor: AppPalette.resolve(
                              const Color(0xFFE8EDFA),
                            ),
                            thumbColor: AppPalette.resolve(
                              const Color(0xFF347BFF),
                            ),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 10,
                            ),
                            overlayColor: AppPalette.resolve(
                              const Color(0x22347BFF),
                            ),
                          ),
                          child: Slider(
                            value: length.toDouble(),
                            min: 0,
                            max: 32,
                            label: tx(
                              '$length caracteres',
                              '$length characters',
                            ),
                            onChanged: onLengthChanged,
                          ),
                        ),
                        _SheetSwitchRow(
                          label: tr('Letras maiúsculas'),
                          value: uppercase,
                          onChanged: onUppercaseChanged,
                        ),
                        _SheetSwitchRow(
                          label: tr('Letras minúsculas'),
                          value: lowercase,
                          onChanged: onLowercaseChanged,
                        ),
                        _SheetSwitchRow(
                          label: tr('Números'),
                          value: numbers,
                          onChanged: onNumbersChanged,
                        ),
                        _SheetSwitchRow(
                          label: tr('Símbolos'),
                          value: symbols,
                          onChanged: onSymbolsChanged,
                        ),
                        _SheetSwitchRow(
                          label: tr('Evitar caracteres semelhantes'),
                          value: avoidSimilar,
                          onChanged: onAvoidSimilarChanged,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SheetSwitchRow extends StatelessWidget {
  const _SheetSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.secondary)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppPalette.resolve(Colors.white),
          activeTrackColor: AppPalette.resolve(const Color(0xFF347BFF)),
        ),
      ],
    );
  }
}

class _PasswordsHeader extends StatelessWidget {
  const _PasswordsHeader();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            const SizedBox(width: 30),
            Expanded(
              child: Center(
                child: Text(
                  tr('Minhas senhas'),
                  style: AppTypography.appPageTitle,
                ),
              ),
            ),
            SizedBox(
              width: 30,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.notifications_none,
                      color: AppColors.navy,
                      size: 26,
                    ),
                  ),
                  Positioned(
                    right: -1,
                    top: 11,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5F59),
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(
                            color: AppPalette.resolve(Colors.white),
                            width: 2,
                          ),
                        ),
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: isWindowsDesktop ? null : 46,
      decoration: BoxDecoration(
        color: AppPalette.resolve(const Color(0xFFF7F8FB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontFamily: 'Kumbh Sans',
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w400,
          color: AppColors.navy,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF98A1B2),
            size: 21,
          ),
          hintText: tr('Buscar contas ou serviços'),
          hintStyle: const TextStyle(
            fontFamily: 'Kumbh Sans',
            fontSize: 14,
            height: 1,
            fontWeight: FontWeight.w400,
            color: Color(0xFF9AA3B5),
          ),
        ),
      ),
    );
  }
}

class _HealthFilterNotice extends StatelessWidget {
  const _HealthFilterNotice({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Semantics(
      label: tx('Filtro de saúde: $label', 'Health filter: $label'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppPalette.resolve(const Color(0xFFEAF1FF)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.health_and_safety_outlined, color: AppColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tx('Mostrando senhas $label', 'Showing $label passwords'),
                style: AppTypography.secondary.copyWith(color: AppColors.navy),
              ),
            ),
            IconButton(
              tooltip: tr('Limpar filtro'),
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.navy,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class SecurityAlert extends StatelessWidget {
  const SecurityAlert({
    super.key,
    this.icon = Icons.warning_amber_rounded,
    this.color = const Color(0xFFFF5F59),
    this.title = '22 senhas comprometidas',
    this.message = 'Altere suas senhas para manter suas contas seguras.',
    this.onTap,
    this.onClose,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppPalette.resolve(const Color(0xFFFFF1F1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Kumbh Sans',
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontFamily: 'Kumbh Sans',
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.bodyText,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: tr('Fechar aviso'),
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 19),
                color: AppColors.bodyText,
                visualDensity: VisualDensity.compact,
              )
            else ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: AppColors.navy, size: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSectionHeader extends StatelessWidget {
  const _CollapsibleSectionHeader({
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Text(title, style: AppTypography.sectionTitle),
            const Spacer(),
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
              color: AppColors.navy,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsList extends StatefulWidget {
  const _AccountsList({
    super.key,
    required this.accounts,
    required this.selectedEmail,
    required this.onAccountTap,
    required this.onFavoriteToggle,
    required this.onActions,
  });

  final List<_AccountData> accounts;
  final String? selectedEmail;
  final ValueChanged<_AccountData> onAccountTap;
  final ValueChanged<_AccountData> onFavoriteToggle;
  final ValueChanged<_AccountData> onActions;

  @override
  State<_AccountsList> createState() => _AccountsListState();
}

class _AccountsListState extends State<_AccountsList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<_AccountData> _visible;

  String _identity(_AccountData account) =>
      account.id.isEmpty ? account.email.toLowerCase() : account.id;

  @override
  void initState() {
    super.initState();
    _visible = List.of(widget.accounts);
  }

  @override
  void didUpdateWidget(covariant _AccountsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.accounts;
    final currentIds = _visible.map(_identity).toSet();
    final nextIds = next.map(_identity).toSet();
    if (currentIds.length != nextIds.length ||
        !currentIds.containsAll(nextIds)) {
      setState(() => _visible = List.of(next));
      return;
    }
    final orderChanged = _visible.asMap().entries.any(
      (entry) => _identity(entry.value) != _identity(next[entry.key]),
    );
    if (!orderChanged) {
      _visible = List.of(next);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animateReorder(next);
    });
  }

  void _animateReorder(List<_AccountData> next) {
    final target = next.firstWhere(
      (account) =>
          _visible.indexWhere(
            (current) => _identity(current) == _identity(account),
          ) !=
          next.indexOf(account),
    );
    final oldIndex = _visible.indexWhere(
      (account) => _identity(account) == _identity(target),
    );
    final newIndex = next.indexWhere(
      (account) => _identity(account) == _identity(target),
    );
    if (oldIndex < 0 || newIndex < 0) {
      setState(() => _visible = List.of(next));
      return;
    }

    final removed = _visible.removeAt(oldIndex);
    _listKey.currentState?.removeItem(
      oldIndex,
      (context, animation) => _animatedCard(removed, animation),
      duration: const Duration(milliseconds: 180),
    );
    _visible.insert(newIndex, target);
    _listKey.currentState?.insertItem(
      newIndex,
      duration: const Duration(milliseconds: 220),
    );
    setState(() {});
  }

  Widget _animatedCard(_AccountData account, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      axis: Axis.horizontal,
      alignment: Alignment.centerLeft,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _AccountCard(
            account: account,
            selected:
                widget.selectedEmail?.toLowerCase() ==
                account.email.toLowerCase(),
            onTap: () => widget.onAccountTap(account),
            onFavoriteToggle: () => widget.onFavoriteToggle(account),
            onActions: () => widget.onActions(account),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: isWindowsDesktop ? (textScale >= 1.5 ? 188 : 150) : 136,
      child: AnimatedList(
        key: _listKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 2),
        initialItemCount: _visible.length,
        itemBuilder: (context, index, animation) =>
            _animatedCard(_visible[index], animation),
      ),
    );
  }
}

class _ServicesList extends StatefulWidget {
  const _ServicesList({
    required this.services,
    required this.onServiceTap,
    required this.onFavoriteToggle,
    super.key,
  });

  final List<_ServiceData> services;
  final ValueChanged<_ServiceData> onServiceTap;
  final ValueChanged<_ServiceData> onFavoriteToggle;

  @override
  State<_ServicesList> createState() => _ServicesListState();
}

class _ServicesListState extends State<_ServicesList> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<_ServiceData> _visible;

  String _identity(_ServiceData service) => service.id.isEmpty
      ? '${service.name.toLowerCase()}-${service.email.toLowerCase()}'
      : service.id;

  @override
  void initState() {
    super.initState();
    _visible = List.of(widget.services);
  }

  @override
  void didUpdateWidget(covariant _ServicesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.services;
    final currentIds = _visible.map(_identity).toSet();
    final nextIds = next.map(_identity).toSet();
    if (currentIds.length != nextIds.length ||
        !currentIds.containsAll(nextIds)) {
      // AnimatedList owns its item count; changing the data alone leaves newly
      // added rows invisible (or stale indices after deletion).
      _listKey = GlobalKey<AnimatedListState>();
      _visible = List.of(next);
      return;
    }
    final orderChanged = _visible.asMap().entries.any(
      (entry) => _identity(entry.value) != _identity(next[entry.key]),
    );
    if (!orderChanged) {
      _visible = List.of(next);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animateReorder(next);
    });
  }

  void _animateReorder(List<_ServiceData> next) {
    final target = next.firstWhere(
      (item) =>
          _visible.indexWhere(
            (current) => _identity(current) == _identity(item),
          ) !=
          next.indexOf(item),
    );
    final oldIndex = _visible.indexWhere(
      (item) => _identity(item) == _identity(target),
    );
    final newIndex = next.indexWhere(
      (item) => _identity(item) == _identity(target),
    );
    if (oldIndex < 0 || newIndex < 0) {
      setState(() => _visible = List.of(next));
      return;
    }
    final removed = _visible.removeAt(oldIndex);
    _listKey.currentState?.removeItem(
      oldIndex,
      (context, animation) => _animatedRow(removed, animation),
      duration: const Duration(milliseconds: 180),
    );
    _visible.insert(newIndex, target);
    _listKey.currentState?.insertItem(
      newIndex,
      duration: const Duration(milliseconds: 220),
    );
    setState(() {});
  }

  Widget _animatedRow(_ServiceData service, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      axis: Axis.vertical,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: animation,
        child: _ServiceRow(
          service: service,
          onTap: () => widget.onServiceTap(service),
          onFavoriteToggle: () => widget.onFavoriteToggle(service),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return _ListFrame(
      child: AnimatedList(
        key: _listKey,
        initialItemCount: _visible.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index, animation) => Column(
          children: [
            _animatedRow(_visible[index], animation),
            if (index < _visible.length - 1) const _SoftDivider(),
          ],
        ),
      ),
    );
  }
}

class _ListFrame extends StatelessWidget {
  const _ListFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) return child;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border.all(color: AppPalette.resolve(const Color(0xFFE5EAF3))),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Divider(
      height: 1,
      thickness: 1,
      indent: 58,
      color: AppPalette.resolve(const Color(0xFFF0F2F6)),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.selected,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onActions,
  });

  final _AccountData account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 132,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.resolve(const Color(0xFFF3F7FF))
              : AppPalette.resolve(Colors.white),
          border: Border.all(
            color: selected
                ? AppPalette.resolve(const Color(0xFF347BFF))
                : AppPalette.resolve(const Color(0xFFE1E6F0)),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _BrandIcon(brand: account.brand),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FavoriteButton(
                      favorite: account.favorite,
                      onTap: onFavoriteToggle,
                    ),
                    _ActionsButton(
                      key: ValueKey(
                        'account-actions-${account.id.isEmpty ? account.email : account.id}',
                      ),
                      onTap: onActions,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              account.label.isEmpty ? account.provider : account.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.itemTitle.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              account.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.secondary.copyWith(fontSize: 11),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? AppPalette.resolve(const Color(0xFFE2ECFF))
                    : AppPalette.resolve(const Color(0xFFF1F5FF)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                tx(
                  '${account.services} serviços',
                  '${account.services} services',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.secondary.copyWith(
                  fontSize: 10,
                  color: AppPalette.resolve(const Color(0xFF347BFF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  final _ServiceData service;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (isWindowsDesktop) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 460 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5;
                final email = Text(
                  service.email.isEmpty
                      ? tr('Sem conta vinculada')
                      : service.email,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: desktopMuted,
                  ),
                );
                return Row(
                  children: [
                    _BrandIcon(brand: service.brand, address: service.url),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.name,
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                          if (!columns) ...[const SizedBox(height: 4), email],
                        ],
                      ),
                    ),
                    if (columns) ...[
                      const SizedBox(width: 16),
                      Expanded(child: email),
                    ],
                    const SizedBox(width: 8),
                    _FavoriteButton(
                      favorite: service.favorite,
                      onTap: onFavoriteToggle,
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: desktopMuted,
                      size: 20,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          children: [
            _BrandIcon(brand: service.brand, address: service.url),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: AppTypography.itemTitle),
                  const SizedBox(height: 4),
                  Text(
                    service.email.isEmpty
                        ? tr('Sem conta vinculada')
                        : service.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.secondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            _FavoriteButton(
              favorite: service.favorite,
              onTap: onFavoriteToggle,
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8993A8), size: 22),
          ],
        ),
      ),
    );
  }
}

class _SelectedAccountFilter extends StatelessWidget {
  const _SelectedAccountFilter({required this.email, required this.onClear});

  final String email;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppPalette.resolve(const Color(0xFFF1F5FF)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              color: Color(0xFF347BFF),
              size: 17,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                tx('Serviços de $email', '$email services'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.secondary.copyWith(
                  color: AppPalette.resolve(const Color(0xFF347BFF)),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: onClear,
              tooltip: tr('Mostrar todos os serviços'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 25, minHeight: 25),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Color(0xFF347BFF), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ServiceDetailsAction { edit, delete }

class _ServiceDetailsSheet extends StatefulWidget {
  const _ServiceDetailsSheet({required this.service});

  final _ServiceData service;

  @override
  State<_ServiceDetailsSheet> createState() => _ServiceDetailsSheetState();
}

class _ServiceDetailsSheetState extends State<_ServiceDetailsSheet> {
  bool _passwordVisible = false;

  _ServiceData get service => widget.service;

  Future<void> _copy(BuildContext context, String label, String value) async {
    if (value.isEmpty) return;
    await SecureClipboard.copy(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tx(
            '$label copiado. ${SecureClipboard.clearAfterMessage}',
            '$label copied. ${SecureClipboard.clearAfterMessage}',
          ),
          style: const TextStyle(fontFamily: 'Kumbh Sans'),
        ),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppPalette.resolve(Colors.white),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: isWindowsDesktop ? 0 : 42,
                  height: isWindowsDesktop ? 0 : 4,
                  decoration: BoxDecoration(
                    color: AppPalette.resolve(const Color(0xFFD9DFEB)),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _BrandIcon(brand: service.brand, address: service.url),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service.name, style: AppTypography.appPageTitle),
                        if (service.url.isNotEmpty)
                          Text(
                            service.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.secondary,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    service.favorite ? Icons.star : Icons.star_border,
                    color: service.favorite
                        ? AppPalette.resolve(const Color(0xFFF4BB35))
                        : AppPalette.resolve(const Color(0xFF9AA3B5)),
                    size: 23,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _DetailValue(
                label: tr('Conta vinculada'),
                value: service.email.isEmpty
                    ? tr('Sem conta vinculada')
                    : service.email,
                onCopy: service.email.isEmpty
                    ? null
                    : () => _copy(context, tr('Conta'), service.email),
              ),
              _DetailValue(
                label: tr('Usuário'),
                value: service.username.isEmpty
                    ? tr('Não informado')
                    : service.username,
                onCopy: service.username.isEmpty
                    ? null
                    : () => _copy(context, tr('Usuário'), service.username),
              ),
              _DetailValue(
                label: tr('Senha'),
                value: service.password.isEmpty
                    ? tr('Não informada')
                    : _passwordVisible
                    ? service.password
                    : List<String>.filled(
                        service.password.runes.length,
                        '•',
                      ).join(),
                valueStyle: service.password.isEmpty
                    ? null
                    : TextStyle(
                        fontFamily: 'Kumbh Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                        letterSpacing: 1.5,
                      ),
                onCopy: service.password.isEmpty
                    ? null
                    : () => _copy(context, tr('Senha'), service.password),
                onToggleVisibility: service.password.isEmpty
                    ? null
                    : () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                obscured: !_passwordVisible,
              ),
              if (service.url.isNotEmpty)
                _DetailValue(
                  label: tr('Endereço'),
                  value: service.url,
                  onCopy: () => _copy(context, tr('Endereço'), service.url),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _ServiceDetailsAction.edit),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      label: Text(tr('Editar')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        minimumSize: const Size.fromHeight(50),
                        side: BorderSide(
                          color: AppPalette.resolve(const Color(0xFFD9E0EC)),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _ServiceDetailsAction.delete),
                      icon: const Icon(Icons.delete_outline, size: 19),
                      label: Text(tr('Excluir')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.resolve(
                          const Color(0xFFE65353),
                        ),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({
    required this.label,
    required this.value,
    required this.onCopy,
    this.valueStyle,
    this.onToggleVisibility,
    this.obscured = false,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final TextStyle? valueStyle;
  final VoidCallback? onToggleVisibility;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.secondary),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle ?? AppTypography.itemTitle,
                ),
              ),
              if (onToggleVisibility != null)
                IconButton(
                  onPressed: onToggleVisibility,
                  tooltip: obscured
                      ? tx('Mostrar $label', 'Show $label')
                      : tx('Ocultar $label', 'Hide $label'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              IconButton(
                onPressed: onCopy,
                tooltip: tx('Copiar $label', 'Copy $label'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 19),
              ),
            ],
          ),
          Divider(
            height: 1,
            color: AppPalette.resolve(const Color(0xFFF0F2F6)),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.favorite, required this.onTap});

  final bool favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Semantics(
      button: true,
      label: favorite
          ? tr('Remover dos favoritos')
          : tr('Adicionar aos favoritos'),
      child: IconButton(
        onPressed: onTap,
        tooltip: favorite
            ? tr('Remover dos favoritos')
            : tr('Adicionar aos favoritos'),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        visualDensity: VisualDensity.standard,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: Icon(
          favorite ? Icons.star : Icons.star_border,
          color: favorite
              ? AppPalette.resolve(const Color(0xFFF4BB35))
              : AppPalette.resolve(const Color(0xFF9AA3B5)),
          size: 20,
        ),
      ),
    );
  }
}

class _ActionsButton extends StatelessWidget {
  const _ActionsButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Semantics(
      button: true,
      label: tr('Mais opções'),
      child: IconButton(
        tooltip: tr('Mais opções'),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
        icon: const Icon(Icons.more_vert, color: Color(0xFF8993A8), size: 20),
      ),
    );
  }
}

class _ItemActionsSheet extends StatelessWidget {
  const _ItemActionsSheet({required this.editLabel, required this.deleteLabel});

  final String editLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Material(
      color: AppPalette.resolve(Colors.white),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isWindowsDesktop ? 0 : 42,
                height: isWindowsDesktop ? 0 : 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppPalette.resolve(const Color(0xFFD9DFEB)),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.blue),
                title: Text(editLabel, style: AppTypography.itemTitle),
                onTap: () => Navigator.pop(context, _ServiceDetailsAction.edit),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE65353),
                ),
                title: Text(
                  deleteLabel,
                  style: AppTypography.itemTitle.copyWith(
                    color: AppPalette.resolve(const Color(0xFFE65353)),
                  ),
                ),
                onTap: () =>
                    Navigator.pop(context, _ServiceDetailsAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            tr('Nenhum resultado encontrado'),
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 14,
              height: 1.1,
              color: AppColors.bodyText,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onClear, child: Text(tr('Limpar busca'))),
        ],
      ),
    );
  }
}

class _EmptyAccountsState extends StatelessWidget {
  const _EmptyAccountsState();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          const Icon(
            Icons.alternate_email_rounded,
            size: 38,
            color: AppColors.blue,
          ),
          const SizedBox(height: 12),
          Text(
            tr('Nenhuma conta adicionada'),
            textAlign: TextAlign.center,
            style: AppTypography.itemTitle,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Adicione um email principal para encontrar seus serviços com mais facilidade.',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.secondary,
          ),
        ],
      ),
    );
  }
}

class _EmptyServicesState extends StatelessWidget {
  const _EmptyServicesState({
    required this.hasSelectedAccount,
    required this.onAdd,
  });

  final bool hasSelectedAccount;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.key_outlined, size: 38, color: AppColors.blue),
          const SizedBox(height: 12),
          Text(
            hasSelectedAccount
                ? tr('Esta conta ainda não tem serviços')
                : tr('Seu primeiro serviço começa aqui'),
            textAlign: TextAlign.center,
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Adicione um acesso para guardar suas credenciais com segurança.',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.secondary,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(tr('Adicionar serviço')),
          ),
        ],
      ),
    );
  }
}

class _BrandIcon extends StatefulWidget {
  const _BrandIcon({required this.brand, this.address = ''});

  final _Brand brand;
  final String address;

  @override
  State<_BrandIcon> createState() => _BrandIconState();
}

class _BrandIconState extends State<_BrandIcon> {
  String? _host;
  Uint8List? _iconBytes;
  bool _loading = false;

  String? get _resolvedHost {
    final providerHost = switch (widget.brand) {
      _Brand.gmail => 'gmail.com',
      _Brand.outlook => 'outlook.com',
      _Brand.proton => 'proton.me',
      _Brand.yahoo => 'yahoo.com',
      _ => null,
    };
    return _siteHost(widget.address) ?? providerHost;
  }

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(covariant _BrandIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand != widget.brand ||
        oldWidget.address != widget.address) {
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final host = _resolvedHost;
    if (host == null) {
      if (!mounted) return;
      setState(() {
        _host = null;
        _iconBytes = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _host = host;
      _iconBytes = null;
      _loading = true;
    });
    Uint8List? bytes;
    try {
      bytes = await BrandIconCache.load(
        host,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // The public icon is optional; do not keep the row in a loading state.
    }
    if (!mounted || _host != host) return;
    setState(() {
      _iconBytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final providerHost = switch (widget.brand) {
      _Brand.gmail => 'gmail.com',
      _Brand.outlook => 'outlook.com',
      _Brand.proton => 'proton.me',
      _Brand.yahoo => 'yahoo.com',
      _ => null,
    };
    if (_host != null && _iconBytes != null) {
      return SizedBox.square(
        dimension: 34,
        child: Image.memory(
          _iconBytes!,
          key: ValueKey(_host),
          width: 34,
          height: 34,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallbackIcon(providerHost),
        ),
      );
    }
    if (_host != null && _loading) {
      return const SizedBox.square(
        dimension: 34,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return _fallbackIcon(providerHost);
  }

  Widget _fallbackIcon(String? providerHost) {
    if (widget.brand == _Brand.genericEmail ||
        widget.brand == _Brand.genericService) {
      return SizedBox.square(
        dimension: 34,
        child: Icon(
          widget.brand == _Brand.genericEmail
              ? Icons.mail_outline_rounded
              : Icons.public_rounded,
          size: 28,
          color: AppPalette.resolve(const Color(0xFF73819D)),
        ),
      );
    }
    return SizedBox.square(
      dimension: 34,
      child: SvgPicture.string(
        _brandSvg[widget.brand]!,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
      ),
    );
  }
}

enum _Brand {
  gmail,
  outlook,
  proton,
  yahoo,
  google,
  paypal,
  shopify,
  github,
  netflix,
  genericEmail,
  genericService,
}

String? _siteHost(String address) {
  final value = address.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      !uri.host.contains('.')) {
    return null;
  }
  return uri.host.toLowerCase();
}

bool _isValidEmail(String email) {
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
}

_Brand _brandForEmail(String email) {
  final domain = email.trim().toLowerCase().split('@').last;
  if (domain == 'gmail.com' || domain == 'googlemail.com') return _Brand.gmail;
  if (domain == 'outlook.com' ||
      domain == 'hotmail.com' ||
      domain == 'live.com' ||
      domain == 'outlook.com.br' ||
      domain == 'hotmail.com.br' ||
      domain == 'msn.com') {
    return _Brand.outlook;
  }
  if (domain == 'proton.me' ||
      domain == 'protonmail.com' ||
      domain == 'pm.me' ||
      domain == 'protonmail.ch') {
    return _Brand.proton;
  }
  if (domain == 'yahoo.com' || domain == 'yahoo.com.br') return _Brand.yahoo;
  return _Brand.genericEmail;
}

_Brand _brandForService(String value) {
  final normalized = value.toLowerCase().replaceAll('www.', '');
  if (normalized.contains('github.com') || normalized.contains('github')) {
    return _Brand.github;
  }
  if (normalized.contains('paypal.com') || normalized.contains('paypal')) {
    return _Brand.paypal;
  }
  if (normalized.contains('shopify.com') || normalized.contains('shopify')) {
    return _Brand.shopify;
  }
  if (normalized.contains('google.com') || normalized.contains('google')) {
    return _Brand.google;
  }
  if (normalized.contains('netflix.com') || normalized.contains('netflix')) {
    return _Brand.netflix;
  }
  return _Brand.genericService;
}

_Brand _brandFromStorage(String value, _Brand fallback) {
  for (final brand in _Brand.values) {
    if (brand.name == value) return brand;
  }
  return fallback;
}

String _providerName(_Brand brand) {
  switch (brand) {
    case _Brand.gmail:
      return 'Gmail';
    case _Brand.outlook:
      return 'Outlook';
    case _Brand.proton:
      return 'Proton';
    case _Brand.yahoo:
      return 'Yahoo';
    case _Brand.google:
      return 'Google';
    case _Brand.paypal:
      return 'PayPal';
    case _Brand.shopify:
      return 'Shopify';
    case _Brand.github:
      return 'GitHub';
    case _Brand.netflix:
      return 'Netflix';
    case _Brand.genericEmail:
      return 'Email';
    case _Brand.genericService:
      return tr('Serviço');
  }
}

final Map<_Brand, String> _brandSvg = {
  _Brand.gmail:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#EA4335" d="M4 8.2A4.2 4.2 0 0 1 8.2 4H27.8A4.2 4.2 0 0 1 32 8.2v19.6A4.2 4.2 0 0 1 27.8 32H8.2A4.2 4.2 0 0 1 4 27.8V8.2Z"/><path fill="#fff" d="M8 11.2V27h4.1V15.4L18 20l5.9-4.6V27H28V11.2L18 18.8 8 11.2Z"/><path fill="#34A853" d="M8 11.2 18 18.8v-4.6L10.8 8.7A4.2 4.2 0 0 0 8 11.2Z"/><path fill="#4285F4" d="M28 11.2 18 18.8v-4.6l7.2-5.5a4.2 4.2 0 0 1 2.8 2.5Z"/></svg>''',
  _Brand.outlook:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><rect x="5" y="7" width="26" height="22" rx="3" fill="#1683D8"/><path fill="#fff" d="m18 17.4 10-6.1v12.8l-10-6.7Z"/><path fill="#D9F0FF" d="m7 11.3 11 7.3 11-7.3v3.8l-11 7.2L7 15.1v-3.8Z"/><path fill="#0868B9" d="M5 11h13v14H5z"/><text x="7.2" y="21" fill="#fff" font-family="Arial" font-size="9" font-weight="700">O</text></svg>''',
  _Brand.proton:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#6C4BEA" d="M18 4 33 29H3L18 4Z"/><path fill="#B8A8FF" d="m18 10 8.4 14H9.6L18 10Z"/><path fill="#fff" d="m18 14 4.8 8h-9.6l4.8-8Z"/></svg>''',
  _Brand.yahoo:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="15" fill="#6001D2"/><path fill="#fff" d="M10 11h4l4 6.1 4-6.1h4l-6 9v5h-4v-5l-6-9Zm8 16.5a1.7 1.7 0 1 1 0-3.4 1.7 1.7 0 0 1 0 3.4Z"/></svg>''',
  _Brand.google:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#4285F4" d="M32 18.4c0-1-.1-2-.3-2.9H18v5.5h7.8a6.7 6.7 0 0 1-2.9 4.4v3.7h4.7c2.8-2.6 4.4-6.3 4.4-10.7Z"/><path fill="#34A853" d="M18 32c4 0 7.4-1.3 9.9-3.6l-4.7-3.7c-1.3.9-3 1.5-5.2 1.5-4 0-7.3-2.7-8.5-6.3H4.7v3.8A15 15 0 0 0 18 32Z"/><path fill="#FBBC05" d="M9.5 19.9a9 9 0 0 1 0-3.8v-3.8H4.7a14.5 14.5 0 0 0 0 11.4l4.8-3.8Z"/><path fill="#EA4335" d="M18 9.8c2.3 0 4.3.8 5.9 2.3l4.3-4.3C25.4 5.3 22 4 18 4A15 15 0 0 0 4.7 12.3l4.8 3.8c1.2-3.6 4.5-6.3 8.5-6.3Z"/></svg>''',
  _Brand.paypal:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#123984" d="M11 7h9.3c6 0 9.2 3 8.3 8.1-.8 4.4-4 6.9-9.2 6.9h-3.3L15 29h-5l3.1-17H11V7Z"/><path fill="#179BD7" d="M8 10h8.7c5.4 0 8.3 2.7 7.5 7.1-.7 3.9-3.5 6.1-8.2 6.1h-3.1l-1.2 6.8H6l3-16H8v-4Z"/></svg>''',
  _Brand.shopify:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#95BF47" d="m11 9 4-4 10 2 3 25H8l3-23Z"/><path fill="#5E8E3E" d="m15 5 2 4h9l-1-2-10-2Z"/><path fill="#fff" d="M22 17.5c-2.8-1.4-5.9-.3-5.9 1.8 0 2.2 4.2 2.4 4.2 4.1 0 1-1.4 1.4-2.9.7v2.1c3.4 1.1 5.7-.5 5.7-2.9 0-2.8-4.2-3-4.2-4.2 0-.7 1.2-1 3.1-.1v-1.5Z"/></svg>''',
  _Brand.github:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="14" fill="#202124"/><path fill="#fff" d="M18 8.3a9.7 9.7 0 0 0-3.1 18.9c.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.5-1.1-1.1-1.4-1.1-1.4-.9-.6.1-.6.1-.6 1 0 1.5 1 1.5 1 .9 1.5 2.4 1.1 3 .8.1-.6.3-1.1.6-1.3-2.2-.3-4.5-1.1-4.5-4.9 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1a9.7 9.7 0 0 1 5.1 0c1.9-1.3 2.7-1 2.7-1 .5 1.4.2 2.4.1 2.7.7.7 1 1.6 1 2.7 0 3.8-2.3 4.6-4.5 4.9.4.3.7.9.7 1.8v2.7c0 .3.2.6.7.5A9.7 9.7 0 0 0 18 8.3Z"/></svg>''',
  _Brand.netflix:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><path fill="#E50914" d="M7 5h6l10 26h-6L7 5Z"/><path fill="#B20710" d="M23 5h6v26h-6V5Z"/><path fill="#E50914" d="m13 5 10 26h-6L7 5h6Z"/></svg>''',
  _Brand.genericEmail:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><rect x="4" y="7" width="28" height="22" rx="5" fill="#E5EDFF"/><path fill="none" stroke="#347BFF" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="m7 11 11 9 11-9M7 27l8-8m14 8-8-8"/></svg>''',
  _Brand.genericService:
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36"><circle cx="18" cy="18" r="14" fill="#E5EDFF"/><path fill="none" stroke="#347BFF" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.5 18h27M18 4.5c4 3.7 6 8.2 6 13.5s-2 9.8-6 13.5c-4-3.7-6-8.2-6-13.5s2-9.8 6-13.5ZM18 4.5a14 14 0 0 1 0 27 14 14 0 0 1 0-27Z"/></svg>''',
};

class _PasswordsBottomNavigation extends StatelessWidget {
  const _PasswordsBottomNavigation();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppPalette.resolve(Colors.white),
        border: Border(
          top: BorderSide(color: AppPalette.resolve(const Color(0xFFF1F3F8))),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _PasswordsNavigationItem(
              icon: Icons.home_outlined,
              label: tr('Início'),
              onTap: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.pop();
                }
              },
            ),
          ),
          Expanded(
            child: _PasswordsNavigationItem(
              icon: Icons.lock_outline,
              label: tr('Senhas'),
              selected: true,
            ),
          ),
          Expanded(
            child: _PasswordsNavigationItem(
              icon: Icons.key_outlined,
              label: tr('Gerador'),
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const PasswordGeneratorPage(),
                ),
              ),
            ),
          ),
          Expanded(
            child: _PasswordsNavigationItem(
              icon: Icons.settings_outlined,
              label: tr('Ajustes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordsNavigationItem extends StatelessWidget {
  const _PasswordsNavigationItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final color = selected
        ? AppPalette.resolve(const Color(0xFF347BFF))
        : AppPalette.resolve(const Color(0xFF9AA3B5));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Kumbh Sans',
              fontSize: 12,
              height: 1,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountData {
  const _AccountData({
    required this.brand,
    required this.provider,
    required this.email,
    required this.services,
    this.id = '',
    this.createdAt,
    this.updatedAt,
    this.label = '',
    this.note = '',
    this.favorite = false,
  });

  final String id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final _Brand brand;
  final String provider;
  final String email;
  final int services;
  final String label;
  final String note;
  final bool favorite;

  factory _AccountData.fromVault(
    VaultAccount account, {
    required int services,
  }) {
    return _AccountData(
      id: account.id,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt,
      brand: _brandForEmail(account.email),
      provider: account.provider,
      email: account.email,
      services: services,
      label: account.label,
      note: account.note,
      favorite: account.favorite,
    );
  }

  VaultAccount toVault() {
    final now = DateTime.now().toUtc();
    return VaultAccount(
      id: id.isEmpty ? email.toLowerCase() : id,
      email: email,
      provider: provider,
      label: label,
      note: note,
      favorite: favorite,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  _AccountData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? services,
    bool? favorite,
  }) {
    return _AccountData(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      brand: brand,
      provider: provider,
      email: email,
      services: services ?? this.services,
      label: label,
      note: note,
      favorite: favorite ?? this.favorite,
    );
  }
}

class _ServiceData {
  const _ServiceData({
    required this.brand,
    required this.name,
    required this.email,
    this.id = '',
    this.createdAt,
    this.updatedAt,
    this.url = '',
    this.username = '',
    this.password = '',
    this.favorite = false,
  });

  final String id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final _Brand brand;
  final String name;
  final String email;
  final String url;
  final String username;
  final String password;
  final bool favorite;

  factory _ServiceData.fromVault(VaultService service) {
    return _ServiceData(
      id: service.id,
      createdAt: service.createdAt,
      updatedAt: service.updatedAt,
      brand: _brandFromStorage(
        service.brand,
        _brandForService('${service.name} ${service.url}'),
      ),
      name: service.name,
      email: service.email,
      url: service.url,
      username: service.username,
      password: service.password,
      favorite: service.favorite,
    );
  }

  VaultService toVault() {
    final now = DateTime.now().toUtc();
    return VaultService(
      id: id.isEmpty ? '${name.toLowerCase()}-${email.toLowerCase()}' : id,
      name: name,
      email: email,
      url: url,
      username: username,
      password: password,
      favorite: favorite,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
      brand: brand.name,
    );
  }

  _ServiceData copyWith({
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? favorite,
    String? email,
  }) {
    return _ServiceData(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      brand: brand,
      name: name,
      email: email ?? this.email,
      url: url,
      username: username,
      password: password,
      favorite: favorite ?? this.favorite,
    );
  }
}

final _defaultAccounts = [
  const _AccountData(
    brand: _Brand.gmail,
    provider: 'Gmail',
    email: 'joao@gmail.com',
    services: 5,
  ),
  const _AccountData(
    brand: _Brand.outlook,
    provider: 'Outlook',
    email: 'joao@outlook.com',
    services: 3,
  ),
  const _AccountData(
    brand: _Brand.proton,
    provider: 'Proton',
    email: 'contato@proton.me',
    services: 2,
  ),
];

final _defaultServices = [
  const _ServiceData(
    brand: _Brand.google,
    name: 'Google',
    email: 'joao@gmail.com',
  ),
  const _ServiceData(
    brand: _Brand.paypal,
    name: 'PayPal',
    email: 'joao@outlook.com',
  ),
  const _ServiceData(
    brand: _Brand.shopify,
    name: 'Shopify',
    email: 'contato@proton.me',
  ),
  const _ServiceData(
    brand: _Brand.github,
    name: 'GitHub',
    email: 'joao@gmail.com',
  ),
  const _ServiceData(
    brand: _Brand.netflix,
    name: 'Netflix',
    email: 'joao@gmail.com',
  ),
];
