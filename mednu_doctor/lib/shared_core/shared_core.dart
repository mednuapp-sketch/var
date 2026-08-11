/// MedNu Partner — Shared Core barrel export.
///
/// Import this single file from a feature module to pull in the whole
/// reusable foundation (role engine, shell, navigation, notifications,
/// profile, wallet, settings, and shared UI states) instead of importing
/// each file individually.
library shared_core;

// Models
export 'models/app_role.dart';
export 'models/user_profile.dart';

// Providers
export 'providers/current_user_provider.dart';
export 'providers/role_providers.dart';

// Services
export 'services/role_migration_hook.dart';
export 'services/role_prefs.dart';

// Widgets
export 'widgets/app_shell.dart';
export 'widgets/profile_avatar.dart';
export 'widgets/role_badge.dart';
export 'widgets/role_switcher_sheet.dart';
export 'widgets/shared_state_widgets.dart';

// Navigation
export 'navigation/adaptive_side_rail.dart';
export 'navigation/nav_item.dart';
export 'navigation/role_menu.dart';

// Notifications
export 'notifications/shared_notification_providers.dart';
export 'notifications/shared_notification_repository.dart';

// Wallet
export 'wallet/currency_formatter.dart';
export 'wallet/wallet_models.dart';
export 'wallet/wallet_providers.dart';
export 'wallet/wallet_repository.dart';
export 'wallet/wallet_summary_card.dart';

// Partner verification documents
export 'documents/partner_document_models.dart';
export 'documents/partner_document_service.dart';
export 'documents/partner_document_upload_card.dart';

// Settings
export 'settings/settings_models.dart';
export 'settings/settings_widgets.dart';
export 'settings/shared_settings_screen.dart';
