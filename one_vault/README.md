# OneVault

Personal Android app for passwords, planner, money, and profile data. Built with Flutter. Backend is Node on Render (or local).

This file is the design and feature record. Update it when screens or behavior change.

## Scope for now

- Android only
- Personal use (sideload / `flutter run`)
- One backend URL, edited by hand in `lib/core/network/api_config.dart`
- Application id: `in.avinashvmetre20.one_vault`

Later options (not built yet): Play Store, sharing with others, iOS, web.

## Run

```bash
cd one_vault
flutter run
```

Launch config `OneVault Android` targets an Android device.

Backend URL examples:

- Render: `https://one-vault-wgdu.onrender.com`
- Emulator local: `http://10.0.2.2:3000`
- Web / Windows local: `http://localhost:3000`

## Design system

All screens reuse the same tokens and widgets. Do not copy padding, cards, or text fields into a new screen.

### Color (`lib/app/theme/app_colors.dart`)

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `primary` | `#2563EB` | same | Buttons, icons, auth banner |
| page background | `scaffold` | `darkScaffold` | Scaffold |
| fields / cards | `surface` | `darkSurface` | Inputs and cards |
| icon wash | `iconWash` | `darkIconWash` | Icon badges |
| muted text | `textMuted` | `darkMuted` | Subtitles and labels |
| borders | `border` | `darkBorder` | Outlines |
| `danger` / `success` / `warning` | same | same | Errors, income, strength |

Widgets must use `AppColors.card(context)`, `line(context)`, `muted(context)`, `wash(context)`, `canvas(context)` so light and dark both work. Brand blue buttons stay `#2563EB` with white text in both themes.

### Space (`lib/app/theme/app_dimensions.dart`)

| Token | Use |
| --- | --- |
| `pagePadding` | Normal lists and details |
| `pagePaddingFab` | Lists with a FAB |
| `pagePaddingTallFab` | Lists with extra bottom actions |
| `pagePaddingForm` | Forms and settings |
| `pagePaddingAuth` | Login, register, vault lock |
| `itemSpacing` | Gap between `ListTileCard`s |
| `fieldGap` | Gap between form fields |
| `radiusMd` / `radiusLg` | Cards and buttons (16 / 18) |

### Shared widgets (`lib/core/widgets/`)

| Widget | Use |
| --- | --- |
| `AppPage` | App bar + padded list |
| `AppDetailPage` | Read-only detail list |
| `AppMissingPage` | Not-found state with back bar |
| `FormPage` | Form + primary Save button |
| `AppTextField` / `AppDropdown` / `AppPickerField` | All inputs |
| `AppSearchField` | Search bars |
| `AppFilterChips` | Category filters |
| `ListTileCard` | Hub and list rows |
| `ActionCard` | Home quick actions |
| `AppCard` | Health / money summaries |
| `InfoRow` | Label + value on details |
| `EmptyState` | Empty and missing lists |
| `AppPrimaryButton` | Primary actions |
| `AppIconBadge` | Blue icon well |
| `SectionTitle` | Section header + optional action |
| `ShellFab` | Add button above the floating tab bar |
| `AuthScaffold` | Login / register shell only |

Login and register use `AuthTextField`, which wraps `AppTextField`.

## App structure

```
lib/
  main.dart
  app/           theme, router, AppState
  core/          http client, shared widgets
  features/      auth, vault, passwords, planner, finance, profile
  shared/        models, enums, formatters
```

Tabs: Home, Vault, Money, Planner, More.

## Features

### Account

- Register, login, logout
- JWT access + refresh tokens stored in Android Keystore (`flutter_secure_storage`)
- Shared `ApiClient` retries once on 401 after refresh
- Debug-only API logs; Profile token copy is debug-only

### Vault passwords (real)

- AES-256-GCM vault, Argon2id from master password
- Master password never sent to the server
- Setup / unlock / biometric / auto-lock
- Add, edit, delete, favorite, tags, generator, health counts
- Encrypted sync to `GET/PUT /api/v1/vault`
- Android Autofill save/fill via Keystore-backed native store (no vault prompt on fill)
- Chrome needs Android Autofill = OneVault **and** Chrome “Autofill using another service”

### Vault placeholders (local only)

- Documents, photos, files: list / detail / add
- Same cards, filters, forms, and empty states as the rest of the app

### Money (local)

- Accounts, monthly income/expense, add transaction

### Planner (API)

- Tasks, notes, reminders, alarms, calendar
- User-scoped. Notes default to non-archived
- Alarm ringing uses notifications; vault still auto-locks in background

### Profile / security / settings

- Personal info, masked IDs when hide-sensitive is on
- App PIN, biometric vault unlock, auto-lock, Autofill checklist
- Light / dark / system theme
- Log out and every delete (password, task, note, reminder/alarm, calendar event) asks for confirmation first (`showAppConfirm`)

## Security notes

- Release traffic is HTTPS-only; HTTP localhost is debug/emulator
- Android backup is off
- Release minify/shrink is on; signing still uses debug keys for personal installs
- Changing `applicationId` later installs as a new app; Autofill must be set again
