# Pelines Admin · TestFlight interno

El workflow prepara **1.0.1 (11)** para `com.tkr.pelinesadmin`. El build 10 se exportó para pruebas internas únicamente. Antes de iniciar, verifica en App Store Connect que el 11 siga libre.

En el proyecto existente de Codemagic, verifica el perfil App Store y el certificado Apple Distribution vigentes para el equipo `B4YBH74VKG`. Conserva el grupo `apple_upload` y su cuenta autorizada. Configura estas variables de aplicación en `pelines_production`.

| Variable | Valor |
|---|---|
| `PELINES_PRODUCTION_SUPABASE_ANON_KEY` | Clave cliente **Secret** del proyecto de producción. El workflow rechaza claves secretas y JWT distintos de `anon` del proyecto. |

En Codemagic elige **Start new build**, la rama `feat/foreground-auto-print` y el workflow `ios-production-testflight`. La versión y el número ya están en `codemagic.yaml`. El workflow registra el SHA y los destinos de producción, pasa los defines al build iOS y valida el bundle y la firma. Tras validar el IPA, lo sube automáticamente con `altool` y el grupo existente `apple_upload`.

En App Store Connect, abre **Pelines Admin → TestFlight → Internal Testing** y verifica que el grupo autorizado tenga distribución automática. Apple procesa la carga antes de hacerla disponible. Si requiere información adicional, resuélvela en el build en App Store Connect. El IPA se exporta para App Store Connect con la opción de pruebas exclusivamente internas desactivada. Puedes probar el mismo build con el grupo interno y seleccionarlo más adelante para revisión pública. La revisión pública se inicia por separado en App Store Connect.

## Prueba física del build instalado

1. Mantén una sola tablet de autoimpresión por sucursal. Abre los ajustes de impresión, guarda la impresora de red y utiliza **Test Print**. Comprueba versión, build, enlace de privacidad y ausencia de controles de simulación en release.
2. Comprueba que las opciones automáticas empiecen apagadas en una instalación nueva o al actualizar desde una versión sin activación. Habilita la impresión y activa los tipos de pedido para la cuenta y sucursal elegidas. Mantén abierta la app autenticada.
3. Con pedidos de prueba autorizados, verifica un ASAP al confirmarlo y pagarlo, un regular antes y después del límite de 30 minutos y un catering cuyo ticket muestre la hora del evento. Comprueba que catering solo produzca un ticket automático.
4. Envía la app al fondo, vuelve al primer plano y verifica la recuperación de pendientes. Repite con una desconexión. Si se registra un fallo antes del envío, usa el reintento manual. Para un resultado incierto, revisa el papel antes de actuar. Comprueba que las actualizaciones repetidas y la impresión manual no dupliquen el ticket.
5. Contrasta `Submitted` con la salida física. `Submitted` indica que se transmitieron datos por la conexión.
