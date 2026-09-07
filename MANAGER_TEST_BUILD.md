# Pelines Admin — Manager Test Build

- Version: `1.0.0+1`
- Android package: `com.tkr.pelinesadmin`
- Display name: `Pelines Admin`
- Intended environment: production manager testing

## Build

Release signing must be configured locally in ignored
`android/key.properties`. Keep the keystore outside the repository.

```powershell
$env:PUB_CACHE = "C:\Users\HP 800G5\pub-cache-clean"
$env:PELINES_SUPABASE_ANON_KEY = "<set locally; do not commit>"

flutter build apk --release --no-pub `
  --dart-define=APP_ENV=production `
  --dart-define=API_BASE_URL=https://pelines-api.aiwithtalha.com/v1 `
  --dart-define=SUPABASE_URL=https://yoolmwqgjftqmcxriwnx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=$env:PELINES_SUPABASE_ANON_KEY
```

Never commit `key.properties`, a keystore, passwords, private API keys, or a
Supabase service-role key.

## Manager Test Checklist

- Install and launch the signed release APK.
- Confirm the launcher shows `Pelines Admin` and the provisional P icon.
- Confirm the login form loads and the production network is reachable.
- Sign in, verify session restoration, and choose the correct location.
- Review Today and open an Order Detail without changing its status.
- Verify foreground alert banner and local sound with fixture/local state only.
- Log out and sign in again.

## Known Limitations

- Order alerts work only while the app is in foreground; there is no push/FCM.
- Cancel remains disabled because the backend workflow is not yet safe.
- Printing remains desktop-only.
- The backend returns at most 100 orders.
- Status preflight reduces races but cannot guarantee an atomic transition
  without backend conditional-update support.
