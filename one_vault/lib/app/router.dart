import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_shell.dart';
import '../features/authentication/presentation/screens/login_screen.dart';
import '../features/authentication/presentation/screens/mpin_screens.dart';
import '../features/authentication/presentation/screens/register_screen.dart';
import '../features/authentication/presentation/screens/security_screens.dart';
import '../features/authentication/presentation/screens/splash_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/documents/presentation/screens/document_screens.dart';
import '../features/files/presentation/screens/file_screens.dart';
import '../features/finance/presentation/screens/account_screens.dart';
import '../features/finance/presentation/screens/card_screens.dart';
import '../features/finance/presentation/screens/category_screens.dart';
import '../features/finance/presentation/screens/finance_screens.dart';
import '../features/finance/presentation/screens/report_screens.dart';
import '../features/finance/presentation/screens/transaction_screens.dart';
import '../features/planner/presentation/screens/alarm_screens.dart';
import '../features/planner/presentation/screens/calendar_screens.dart';
import '../features/planner/presentation/screens/note_screens.dart';
import '../features/planner/presentation/screens/planner_screens.dart';
import '../features/planner/presentation/screens/alarm_ringing_screen.dart';
import '../features/planner/presentation/screens/reminder_screens.dart';
import '../features/planner/presentation/screens/task_screens.dart';
import '../features/passwords/presentation/screens/password_screens.dart';
import '../features/personal_info/presentation/screens/profile_screens.dart';
import '../features/photos/presentation/screens/photo_screens.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/vault/presentation/screens/vault_hub_screen.dart';
import 'app_state.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

String _id(GoRouterState state) => state.pathParameters['id']!;

int _intId(GoRouterState state) => int.parse(state.pathParameters['id']!);

GoRouter createRouter(AppState appState) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: appState,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isSplash = location == AppRoutes.splash;
      final isAuthRoute =
          location == AppRoutes.login || location == AppRoutes.register;
      final isMpinSetup = location == AppRoutes.mpinSetup;
      final isMpinUnlock = location == AppRoutes.mpinUnlock;
      final isMpinRoute = isMpinSetup || isMpinUnlock;

      if (!appState.isReady) {
        return isSplash ? null : AppRoutes.splash;
      }
      if (!appState.isLoggedIn && !isAuthRoute) {
        return AppRoutes.login;
      }
      if (appState.needsMpinSetup && !isMpinSetup) {
        return AppRoutes.mpinSetup;
      }
      if (appState.needsMpinUnlock && !isMpinUnlock) {
        return AppRoutes.mpinUnlock;
      }
      if (appState.isAppUnlocked && (isAuthRoute || isSplash || isMpinRoute)) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.mpinSetup,
        builder: (context, state) => const MpinSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.mpinUnlock,
        builder: (context, state) => const MpinUnlockScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vault',
                builder: (context, state) => const VaultHubScreen(),
                routes: [
                  GoRoute(
                    path: 'passwords',
                    builder: (context, state) => const PasswordListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const PasswordFormScreen(),
                      ),
                      GoRoute(
                        path: 'generator',
                        builder: (context, state) =>
                            const PasswordGeneratorScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            PasswordDetailScreen(id: _id(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                PasswordFormScreen(id: _id(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'documents',
                    builder: (context, state) => const DocumentListScreen(),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'new',
                        builder: (context, state) => const DocumentFormScreen(),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: ':id',
                        builder: (context, state) =>
                            DocumentDetailScreen(id: _id(state)),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'photos',
                    builder: (context, state) => const PhotoListScreen(),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'new',
                        builder: (context, state) => const PhotoFormScreen(),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: ':id',
                        builder: (context, state) =>
                            PhotoDetailScreen(id: _id(state)),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'files',
                    builder: (context, state) => const FileListScreen(),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'new',
                        builder: (context, state) => const FileFormScreen(),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: ':id',
                        builder: (context, state) =>
                            FileDetailScreen(id: _id(state)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/money',
                builder: (context, state) => const FinanceDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'accounts/new',
                    builder: (context, state) => const AccountFormScreen(),
                  ),
                  GoRoute(
                    path: 'cards/new',
                    builder: (context, state) => const CardFormScreen(),
                  ),
                  GoRoute(
                    path: 'transactions/new',
                    builder: (context, state) => TransactionFormScreen(
                      initialType: state.uri.queryParameters['type'],
                    ),
                  ),
                  GoRoute(
                    path: 'accounts',
                    builder: (context, state) => const AccountsScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            AccountDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                AccountFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'cards',
                    builder: (context, state) => const CardsScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            CardDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                CardFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'transactions',
                    builder: (context, state) => const TransactionsScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            TransactionDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                TransactionFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'transfers',
                    builder: (context, state) =>
                        const TransactionsScreen(forcedType: 'transfer'),
                  ),
                  GoRoute(
                    path: 'categories',
                    builder: (context, state) => const CategoriesScreen(),
                  ),
                  GoRoute(
                    path: 'reports',
                    builder: (context, state) => const MoneyReportsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/planner',
                builder: (context, state) => const PlannerHubScreen(),
                routes: [
                  GoRoute(
                    path: 'tasks',
                    builder: (context, state) => const TaskListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const TaskFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            TaskDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                TaskFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'notes',
                    builder: (context, state) => const NoteListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const NoteFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            NoteDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                NoteFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'alarms',
                    builder: (context, state) => const AlarmListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const AlarmFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            ReminderDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                AlarmFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'reminders',
                    builder: (context, state) => const ReminderListScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) => const ReminderFormScreen(),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'ringing/:id',
                        builder: (context, state) =>
                            AlarmRingingScreen(id: _intId(state)),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            ReminderDetailScreen(id: _intId(state)),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            builder: (context, state) =>
                                ReminderFormScreen(id: _intId(state)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'calendar',
                    builder: (context, state) => const PlannerCalendarScreen(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        builder: (context, state) =>
                            const CalendarEventFormScreen(),
                      ),
                      GoRoute(
                        path: ':id',
                        builder: (context, state) =>
                            CalendarEventFormScreen(id: _intId(state)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (context, state) => const MoreScreen(),
                routes: [
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'profile',
                    builder: (context, state) => const ProfileScreen(),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'security',
                    builder: (context, state) => const SecurityScreen(),
                    routes: [
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'pin',
                        builder: (context, state) => const ChangeMpinScreen(),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'autofill',
                        builder: (context, state) => const AutofillSetupScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
    ],
  );
}
