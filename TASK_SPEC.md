Quiero que prepares desde cero el proyecto Flutter para la nueva aplicación administrativa móvil de Pelines.

Tienes permiso para ejecutar comandos, crear archivos, crear carpetas e instalar las dependencias necesarias para ESTA tarea.

## 1. UBICACIÓN DEL PROYECTO

Trabaja en mi escritorio de Windows.

Ruta base esperada:

C:\Users<MI_USUARIO>\Desktop

Primero identifica correctamente mi usuario/ruta de Desktop en esta computadora.

Crea ahí un nuevo proyecto Flutter llamado:

pelines_admin_app

La carpeta final debe quedar aproximadamente como:

Desktop\pelines_admin_app

IMPORTANTE:

Existe otro repositorio llamado:

Pelines-Catering

Ese repositorio contiene el backend existente.

NO modifiques absolutamente nada dentro de `Pelines-Catering`.

El proyecto Flutter debe ser completamente independiente.

---

# 2. CONTEXTO

Estamos desarrollando una aplicación móvil administrativa para Pelines Mexican Restaurant.

Ya analizamos:

1. El Dashboard Web existente.
2. El Backend existente.

La aplicación móvil será otro cliente del backend existente.

Arquitectura general:

Pelines Flutter App
↓
Supabase Auth
↓
access_token
↓
Pelines REST API /v1
↓
Backend existente

No vamos a reconstruir el backend.

No vamos a modificar el backend en esta tarea.

---

# 3. OBJETIVO DE ESTA TAREA

Quiero terminar esta tarea con:

* Flutter instalado/verificado.
* Proyecto Flutter creado.
* Proyecto compilable.
* Dependencias base instaladas.
* Arquitectura de carpetas creada.
* Configuración base preparada.
* Una aplicación mínima que arranque correctamente.
* Sin implementar todavía funcionalidades reales de Pelines.

NO desarrolles todavía:

* Login real.
* Orders.
* Products.
* Menu.
* Locations.
* Promotions.
* Analytics.
* Notifications.
* Printing.
* API calls reales.
* Pantallas finales.
* Diseño visual definitivo.

Estamos construyendo solamente los cimientos.

---

# 4. PRIMERO REVISA EL ENTORNO

Antes de crear nada ejecuta:

flutter --version

dart --version

flutter doctor -v

Determina si están correctamente disponibles:

* Flutter SDK
* Dart
* Android toolchain
* Android Studio / Android SDK
* VS Code integration
* dispositivos/emuladores disponibles

Recuerda que estoy trabajando desde Windows.

NO intentes configurar iOS/Xcode en Windows.

Si Flutter NO está instalado o existe un bloqueo importante, detente y explícame exactamente qué falta antes de crear el proyecto.

Si existen warnings que NO bloquean Android/Flutter development, puedes continuar pero documéntalos al final.

---

# 5. CREAR PROYECTO

Desde Desktop crea:

flutter create pelines_admin_app

Usa una configuración compatible con:

Android
iOS

aunque iOS será compilado posteriormente desde macOS.

Después entra al proyecto.

Confirma que Flutter generó correctamente la estructura.

---

# 6. DEPENDENCIAS BASE

Quiero utilizar esta arquitectura:

State management:
Riverpod

HTTP:
Dio

Authentication:
Supabase Flutter

Navigation:
go_router

JSON serialization:
json_annotation
json_serializable
build_runner

Local preferences:
shared_preferences

Image selection:
image_picker

Image compression:
flutter_image_compress

Dates / formatting:
intl

Instala versiones actuales compatibles entre sí y con la versión instalada de Flutter.

Preferiblemente usa `flutter pub add` para que Flutter resuelva versiones compatibles, en vez de hardcodear versiones arbitrariamente.

Dependencias runtime esperadas:

flutter_riverpod
dio
supabase_flutter
go_router
json_annotation
shared_preferences
image_picker
flutter_image_compress
intl

Dependencias de desarrollo:

build_runner
json_serializable

NO instales por ahora:

Firebase
Bloc
GetX
Hive
Drift
SQLite packages
Retrofit
WebSocket packages
GraphQL
FCM
APNs packages
printing packages

No necesitamos esas tecnologías todavía.

---

# 7. ARQUITECTURA DE CARPETAS

Dentro de `lib/`, quiero una arquitectura feature-first sencilla.

Crea:

lib/
│
├── app/
│   ├── app.dart
│   ├── router.dart
│   │
│   └── theme/
│       └── app_theme.dart
│
├── core/
│   │
│   ├── api/
│   │   ├── api_client.dart
│   │   └── api_exception.dart
│   │
│   ├── config/
│   │   └── app_config.dart
│   │
│   ├── storage/
│   │
│   └── utils/
│
├── features/
│   │
│   ├── auth/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   ├── orders/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   ├── locations/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   ├── menu/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   ├── promotions/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   ├── analytics/
│   │   ├── data/
│   │   ├── models/
│   │   ├── providers/
│   │   └── presentation/
│   │
│   └── account/
│       ├── data/
│       ├── models/
│       ├── providers/
│       └── presentation/
│
└── main.dart

Si Git no conserva carpetas vacías, puedes agregar `.gitkeep` únicamente donde sea necesario.

No agregues arquitectura adicional sin una razón concreta.

No quiero Clean Architecture excesivamente compleja.

---

# 8. RESPONSABILIDADES

Mantén estas reglas desde el comienzo:

### presentation/

Pantallas y widgets.

NO debe hacer llamadas HTTP directamente.

### providers/

Estado de aplicación mediante Riverpod.

### data/

Repositories y acceso a fuentes de datos.

### models/

Modelos Dart/DTOs correspondientes al dominio.

### core/api/

Configuración HTTP compartida.

### core/config/

Configuración de ambientes.

### app/

Bootstrap visual, router y theme.

---

# 9. APP CONFIG

Prepara `app_config.dart` para que posteriormente podamos manejar configuraciones como:

API Base URL
Supabase URL
Supabase Anon Key

IMPORTANTE:

NO escribas secretos reales.

NO copies secretos desde `Pelines-Catering`.

NO hardcodees credenciales.

Prepara solamente la estructura para recibir valores posteriormente mediante `--dart-define` o un mecanismo equivalente apropiado para Flutter.

Queremos poder diferenciar eventualmente:

development
staging
production

pero NO necesitamos configurar servidores reales todavía.

---

# 10. API CLIENT

Crea únicamente el esqueleto base de `ApiClient` utilizando Dio.

Debe quedar preparado conceptualmente para:

Flutter
↓
Dio
↓
Authorization: Bearer <Supabase access token>
↓
Pelines REST API

Pero NO conectes todavía con el backend real.

No implementes endpoints de Pelines.

No copies tokens.

No hagas requests de prueba al servidor de producción.

Debe ser sólo infraestructura reutilizable.

También crea una estructura sencilla `ApiException` que posteriormente permita normalizar errores HTTP.

No construyas un sistema complejo de errores todavía.

---

# 11. RIVERPOD

Configura correctamente:

ProviderScope

en el punto de entrada de la aplicación.

No crees todavía providers complejos.

Sólo deja Riverpod correctamente integrado y preparado para los módulos futuros.

---

# 12. ROUTER

Configura `go_router`.

Por ahora sólo necesitamos una ruta inicial sencilla.

Puede ser:

/

con una pantalla temporal que indique algo como:

Pelines Admin

Project foundation ready

No desarrolles todavía el Login real.

La intención es únicamente comprobar que:

main.dart
→ app.dart
→ router.dart
→ pantalla temporal

funcionan correctamente.

---

# 13. THEME

Crea un `AppTheme` mínimo usando Material 3.

No intentes todavía replicar el branding completo de Pelines.

No inviertas tiempo en diseño visual.

Sólo necesitamos una base organizada para posteriormente definir:

colors
typography
components

---

# 14. SUPABASE

La dependencia `supabase_flutter` debe quedar instalada.

Sin embargo:

NO inicialices Supabase con credenciales inventadas.

NO copies credenciales del backend.

Si la inicialización requiere valores para ejecutar la app, estructura el código de forma que el proyecto base pueda arrancar sin conexión/configuración real durante esta fase, o utiliza una estrategia segura y explícita de configuración pendiente.

La conexión real con Supabase será una tarea posterior.

---

# 15. ANDROID / IOS

No cambies innecesariamente configuración nativa.

Verifica que Android esté correctamente generado.

No configures todavía:

* signing de producción;
* Play Store;
* App Store;
* push notifications;
* deep links;
* permisos especiales.

Para iOS simplemente conserva el proyecto generado por Flutter.

No intentes ejecutar Xcode desde Windows.

---

# 16. PACKAGE / APP ID

Antes de cambiar el applicationId/package name definitivo, verifica cuál generó Flutter.

No inventes todavía un identificador empresarial definitivo si no se ha definido.

Documenta el identificador actual para que podamos decidir posteriormente el Bundle ID/package name oficial antes de publicar.

---

# 17. README

Actualiza o crea un README breve para este proyecto.

Debe explicar:

Pelines Admin App

Technology:

* Flutter
* Dart
* Riverpod
* Dio
* Supabase
* go_router

Architecture:
feature-first

Y explicar brevemente las carpetas:

app
core
features

Incluye también:

“Backend changes are outside the scope of this repository.”

No incluyas credenciales.

---

# 18. FORMATTING Y ANÁLISIS

Al terminar ejecuta:

dart format .

flutter analyze

Corrige únicamente problemas generados por ESTA configuración inicial.

No hagas refactors innecesarios.

---

# 19. PRUEBA DE COMPILACIÓN

Quiero verificar que el proyecto realmente funciona.

Primero ejecuta:

flutter devices

Si existe un dispositivo Android o emulador disponible, intenta ejecutar:

flutter run

Si no existe dispositivo disponible, al menos ejecuta una comprobación/build apropiada para Android, por ejemplo:

flutter build apk --debug

La finalidad NO es generar un release.

Sólo demostrar que los cimientos compilan.

---

# 20. GIT

Comprueba si `flutter create` inicializó Git.

Si existe repositorio Git:

* revisa `git status`;
* asegúrate de que no existan secretos;
* NO conectes todavía ningún remote;
* NO hagas push;
* NO crees repositorio GitHub todavía.

Puedes crear un commit inicial únicamente si el repositorio está limpio de secretos y consideras que es apropiado, con un mensaje similar a:

chore: initialize Pelines Flutter app foundation

Si prefieres no hacer commit automáticamente, deja los cambios preparados y explícame qué habría que commitear.

NO toques el Git del repositorio `Pelines-Catering`.

---

# 21. VERIFICACIÓN FINAL

Antes de terminar comprueba:

[ ] Proyecto creado en Desktop/pelines_admin_app
[ ] Flutter funciona
[ ] Dart funciona
[ ] Dependencias instaladas
[ ] Riverpod configurado
[ ] Dio instalado
[ ] Supabase Flutter instalado
[ ] go_router configurado
[ ] json_serializable/build_runner instalados
[ ] shared_preferences instalado
[ ] image_picker instalado
[ ] flutter_image_compress instalado
[ ] intl instalado
[ ] Arquitectura de carpetas creada
[ ] AppConfig preparado
[ ] ApiClient base preparado
[ ] ApiException base preparado
[ ] Theme base creado
[ ] Router base funcionando
[ ] App temporal abre
[ ] flutter analyze sin errores
[ ] Build/prueba Android exitosa si el entorno lo permite
[ ] No hay secretos
[ ] Pelines-Catering no fue modificado

---

# 22. REPORTE FINAL

Cuando termines NO continúes desarrollando funcionalidades.

Detente y entrégame un reporte con:

## Environment

* Flutter version
* Dart version
* Android status
* VS Code status
* warnings encontrados

## Project

* ruta exacta
* application/package ID actual
* plataformas generadas

## Dependencies

Lista de dependencias instaladas y versión resuelta.

## Architecture

Árbol de carpetas creado.

## Configuration

Explica brevemente cómo quedó preparado AppConfig.

## Verification

Resultados de:

flutter analyze
build/run

## Git

Estado actual del repositorio.

## Problems

Cualquier problema o warning pendiente.

## Next Step

NO ejecutes el siguiente paso.

Sólo indica que el proyecto está preparado para que revisemos juntos el resultado antes de comenzar autenticación o cualquier funcionalidad real.

IMPORTANTE FINAL:

No agregues funcionalidades por iniciativa propia.

Prefiero avanzar módulo por módulo:

preparar → revisar → probar → commit → siguiente paso.
