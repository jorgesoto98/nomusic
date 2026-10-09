# NoMusic .pkg Installer — Design Spec

> Actualizado el 2026-10-09: el agente se instala en `/Library/LaunchAgents` (para todos los
> usuarios) desde una sola plantilla, y hay `test.sh`. La versión original de abril
> instalaba el plist en la carpeta de cada usuario; ver "Historial" al final.

## Objetivo

Crear un instalador `.pkg` firmado y notarizado para que usuarios no técnicos instalen NoMusic con doble-click, sin necesidad de Terminal ni Xcode Command Line Tools.

## Decisiones de diseño

| Decisión | Elección | Razón |
|----------|----------|-------|
| Formato | `.pkg` | Estándar de macOS, wizard nativo, familiar para usuarios |
| Arquitectura | Universal (arm64 + x86_64) | Cubre todos los Macs sin costo adicional |
| Firma | Developer ID Installer + notarización | Experiencia sin fricción con Gatekeeper |
| Binario | `/usr/local/bin/nomusic` | Ubicación estándar del sistema; el plist no depende de `$HOME` |
| LaunchAgent | `/Library/LaunchAgents/com.isdelnorte.nomusic.plist`, dentro del payload | No depende de quién tenga la sesión abierta: funciona en instalaciones remotas/MDM y para todos los usuarios de la Mac |
| Plist | Una sola plantilla (`com.isdelnorte.nomusic.plist`) con el marcador `__NOMUSIC_BIN__` | Un único lugar con los ajustes del agente para el `.pkg` y para `install.sh` |
| Desinstalación | App + script | Cubre usuarios técnicos y no técnicos |

**Consecuencia:** con el `.pkg`, NoMusic corre para **todos** los usuarios de la Mac, no solo para quien la instaló.

## Componentes

### 1. `build-pkg.sh` — Script maestro

Script que orquesta todo el proceso de build:

1. Compila `nomusic.swift` dos veces (arm64 para macOS 11+, x86_64 para macOS 10.15+)
2. Une los binarios con `lipo -create` → binario universal
3. Firma el binario con `codesign` (Developer ID Application, hardened runtime, `entitlements.plist` con `com.apple.security.automation.apple-events` para poder darle play a Spotify)
4. Genera el plist del agente desde la plantilla, con `__NOMUSIC_BIN__` → `/usr/local/bin/nomusic`, en `staging/Library/LaunchAgents/` con permisos 644
5. Construye NoMusic Uninstaller.app
6. Firma el Uninstaller.app
7. Genera el `.pkg` con `pkgbuild` (los archivos quedan con dueño root:wheel, que launchd exige en `/Library/LaunchAgents`)
8. Envuelve en distribution pkg con `productbuild` (para personalizar UI del wizard)
9. Firma el `.pkg` con `productsign` (Developer ID Installer)
10. Notariza con `notarytool submit` + `stapler staple`

**Parámetros (variables de entorno, nunca en el repo):**
- `DEVELOPER_ID_APP` — identidad de firma para binarios (ej: "Developer ID Application: Nombre (TEAMID)")
- `DEVELOPER_ID_INSTALLER` — identidad de firma para .pkg (ej: "Developer ID Installer: Nombre (TEAMID)")
- `NOTARY_PROFILE` — opcional, perfil del llavero para notarizar, por omisión `isdelnorte-notary`
- `VERSION` — opcional, por omisión `1.1.0`. Es la única fuente del número de versión: `build-pkg.sh` lo pone en `distribution.xml` y en el `Info.plist` del desinstalador, que en el repo llevan el marcador `__VERSION__`

**Credenciales de notarización:** viven en el llavero de inicio de sesión, no en `.env`. El
perfil `isdelnorte-notary` usa la llave de la API de App Store Connect (`.p8`, en
`~/.appstoreconnect/private_keys/`, respaldada en Bitwarden con su Key ID e Issuer ID), no una
contraseña de app. Desklot usa el mismo perfil. Se crea una vez por Mac con
`xcrun notarytool store-credentials isdelnorte-notary --key <AuthKey.p8> --key-id <KEYID> --issuer <ISSUER_ID>`,
que valida la llave con Apple antes de guardarla. `build-pkg.sh` comprueba el perfil antes de
compilar y se detiene si no existe.

**Output:** `build/NoMusic-<version>.pkg`

**Payload del `.pkg`:**
```
/usr/local/bin/nomusic
/Library/LaunchAgents/com.isdelnorte.nomusic.plist
/Applications/NoMusic Uninstaller.app
```

### 2. Scripts de instalación del .pkg

Corren como root.

**`scripts/preinstall`:**
- Recorre `/Users/*`: para cada usuario hace `launchctl bootout gui/<uid>/com.isdelnorte.nomusic` y borra `~/Library/LaunchAgents/com.isdelnorte.nomusic.plist`, el plist por usuario que dejaba la 1.0.x (si quedara, habría dos agentes con el mismo nombre)
- Sale con 0 siempre (no bloquear instalación si no había versión previa)

**`scripts/postinstall`:**
- El payload ya dejó el binario y el plist; launchd arrancará NoMusic en cada inicio de sesión
- Si nadie tiene la sesión abierta (consola en `root`, `loginwindow` o vacía), sale con 0: arranca en el próximo inicio de sesión
- Si hay alguien, hace `launchctl bootstrap gui/<uid> /Library/LaunchAgents/com.isdelnorte.nomusic.plist` y verifica que esté corriendo (sale con 1 si no)

### 3. NoMusic Uninstaller.app

App mínima construida durante el build (no es un proyecto Xcode):

```
NoMusic Uninstaller.app/
└── Contents/
    ├── Info.plist
    └── MacOS/
        └── uninstall    (script bash como ejecutable)
```

**Comportamiento del script `uninstall`:**
1. Muestra diálogo de confirmación con `osascript`
2. Si confirma: `launchctl bootout` del usuario con sesión abierta y borra el plist por usuario de la 1.0.x
3. Con permisos de administrador: borra `/usr/local/bin/nomusic`, `/Library/LaunchAgents/com.isdelnorte.nomusic.plist` y la propia `.app`, y quita el recibo con `pkgutil --forget com.isdelnorte.nomusic`
4. Muestra diálogo de éxito/error

En otros usuarios con sesión abierta, NoMusic sigue corriendo hasta que cierren sesión (el plist ya no existe, así que no vuelve a arrancar).

### 4. Distribution XML

Archivo XML para `productbuild` que personaliza el wizard del instalador:
- Título: "NoMusic"
- Mensaje de bienvenida (`pkg-resources/welcome.html`), que avisa que arranca para todos los usuarios
- Requisito mínimo de macOS 10.15
- Sin opción de elegir destino

## Instalación manual (`install.sh`)

Para desarrolladores: compila, copia el binario a `~/.local/bin/nomusic` y genera el plist en `~/Library/LaunchAgents/` desde la misma plantilla (`__NOMUSIC_BIN__` → `~/.local/bin/nomusic`). Solo para el usuario actual.

Si ya existe `/Library/LaunchAgents/com.isdelnorte.nomusic.plist` (instalación por `.pkg`), se detiene con error y pide correr NoMusic Uninstaller primero, para no dejar dos instalaciones. Se desinstala con `uninstall.sh`.

## Pruebas (`test.sh`)

Revisiones antes de publicar, sin credenciales de firma:
1. `nomusic.swift` compila para arm64 (macOS 11) y x86_64 (macOS 10.15), sin advertencias
2. Sintaxis (`bash -n`) de todos los scripts, y `shellcheck` si está instalado
3. La plantilla genera un plist válido con el `Label` y la ruta correctos para los dos caminos, y conserva el marcador
4. Un `.pkg` de prueba sin firmar con el mismo layout que `build-pkg.sh`: el plist queda root:wheel 644 y el binario root:wheel ejecutable

No cubre la prueba que más importa, que es manual: presionar Play con Apple Music cerrado y confirmar que se cierra y suena Spotify.

## Estructura de archivos

```
apple_spotify_button/
├── nomusic.swift                 # Código fuente
├── com.isdelnorte.nomusic.plist  # Plantilla del LaunchAgent (__NOMUSIC_BIN__)
├── entitlements.plist            # Permiso de Apple Events para el binario firmado
├── install.sh / uninstall.sh     # Instalación manual
├── test.sh                       # Revisiones antes de publicar
├── build-pkg.sh                  # Build, firma y notarización del .pkg
├── distribution.xml              # Configuración del wizard del .pkg
├── pkg-resources/welcome.html    # Pantalla de bienvenida
├── scripts/
│   ├── preinstall
│   └── postinstall
├── uninstaller/
│   ├── Info.plist
│   └── uninstall
└── build/                        # Output (gitignored)
    └── NoMusic-X.Y.Z.pkg
```

## Flujo del usuario final

### Instalación
1. Descarga `NoMusic-X.Y.Z.pkg` de GitHub Releases
2. Doble-click → wizard estándar de macOS
3. Click "Instalar" → pide contraseña de admin
4. NoMusic queda corriendo en segundo plano (o arranca al iniciar sesión, si se instaló sin nadie conectado)

### Desinstalación (no técnico)
1. Abre "NoMusic Uninstaller.app" desde /Applications
2. Confirma en el diálogo e ingresa la contraseña de admin
3. Todo limpio

## Flujo del desarrollador

```bash
# Revisiones rápidas (sin credenciales)
./test.sh

# Una sola vez por Mac: guardar la llave de notarización en el llavero
xcrun notarytool store-credentials isdelnorte-notary \
  --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>

# Identidades de firma (en la shell o en .env, que está en .gitignore)
export DEVELOPER_ID_APP="Developer ID Application: Nombre (XXXXXXXXXX)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: Nombre (XXXXXXXXXX)"

# Generar .pkg firmado y notarizado
VERSION=X.Y.Z ./build-pkg.sh

# Prueba manual: instalar el .pkg, cerrar Apple Music, presionar Play → debe sonar Spotify
# Subir build/NoMusic-X.Y.Z.pkg a GitHub Releases
```

## Fuera de alcance

- GUI app con menú bar (posible mejora futura)
- Auto-update mechanism
- Homebrew tap (se puede agregar después)
- Custom icon para el Uninstaller (usa icono genérico del sistema)
- Tests automáticos de la lógica de `nomusic.swift` (llama directo a NSWorkspace; no compensa separarla para unas 80 líneas)

## Historial

- **2026-04-01 (1.0.0):** diseño original. `postinstall` escribía el plist en `~/Library/LaunchAgents` del usuario con sesión abierta, con una copia de los ajustes dentro del script. Fallaba si nadie había iniciado sesión. Implementado según `plans/2026-04-01-pkg-installer.md`.
- **2026-10-09:** el plist pasa al payload en `/Library/LaunchAgents` desde la plantilla compartida; `preinstall` limpia la instalación por usuario de la 1.0.x; el desinstalador borra el plist del sistema y el recibo; se agrega `test.sh`. La contraseña de notarización pasa de `.env` al llavero
y ese mismo día el perfil pasa a usar la llave `.p8` de la API de App Store Connect en lugar de
la contraseña de app. Se llamó primero `nomusic-notary` y se renombró a `isdelnorte-notary`
porque lo comparten todas las apps (NoMusic y Desklot).
