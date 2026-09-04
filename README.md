# Pelines Admin App

Mobile administration client foundation for Pelines Mexican Restaurant.

## Technology

- Flutter and Dart
- Riverpod
- Dio
- Supabase Flutter
- go_router

## Architecture

The project uses a lightweight feature-first structure:

- `lib/app`: application bootstrap, routing, and theme.
- `lib/core`: shared API, configuration, storage, and utility code.
- `lib/features`: modules organized by business feature, each divided into
  data, models, providers, and presentation.

Configuration is supplied at build or run time with `--dart-define`. Supported
keys are `APP_ENV`, `API_BASE_URL`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY`.
No credentials are stored in this repository, and Supabase is intentionally not
initialized until valid configuration is provided in a later task.

Backend changes are outside the scope of this repository.
