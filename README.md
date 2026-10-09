# NoMusic

**[English](#english) | [Español](#español)**

---

## English

Replace Apple Music with Spotify for media keys on macOS.

When you press Play/Pause without an audio app open, macOS launches Apple Music automatically. NoMusic intercepts that launch, kills Apple Music before it fully opens, and opens Spotify instead.

### How it works

Uses `NSWorkspace.willLaunchApplicationNotification` — a native macOS event that fires **before** Apple Music finishes launching. It's event-driven: **zero CPU at idle**, no polling or timers.

### Quick Install (recommended)

1. **Download** the latest `NoMusic.pkg` from [Releases](https://github.com/jorgesoto98/nomusic/releases)
2. **Double-click** the `.pkg` file
3. **Follow the installer** — click "Install" and enter your password
4. Done — NoMusic is running in the background

To uninstall, open **NoMusic Uninstaller** from your Applications folder.

### Requirements

- macOS Catalina (10.15) or later
- Spotify installed

### Manual Install (for developers)

Requires [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/).

1. **Install Xcode Command Line Tools** (skip if you already have them):

```bash
xcode-select --install
```

2. **Clone the repository** (click the green **Code** button above, or):

```bash
git clone https://github.com/jorgesoto98/nomusic.git
cd nomusic
```

3. **Run the installer**:

```bash
chmod +x install.sh
./install.sh
```

This compiles the Swift source, copies the binary to `~/.local/bin/`, sets up the LaunchAgent, and starts it.

4. **Verify it's running**:

```bash
launchctl print gui/$(id -u)/com.isdelnorte.nomusic
```

If you see process info and `state = running`, you're good.

### Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `xcode-select: error` | Run `xcode-select --install` and wait for the download |
| Installer says "failed to start" | Check the agent status with `launchctl print gui/$(id -u)/com.isdelnorte.nomusic` |
| Apple Music still opens | Run `launchctl print gui/$(id -u)/com.isdelnorte.nomusic` to check status |
| Want to see logs | Edit `~/Library/LaunchAgents/com.isdelnorte.nomusic.plist`, change `StandardErrorPath` from `/dev/null` to `/tmp/nomusic.log`, then restart the agent (see below) |

**Restart the agent manually:**

```bash
launchctl bootout gui/$(id -u)/com.isdelnorte.nomusic
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.isdelnorte.nomusic.plist
```

### Files

| File | Description |
|------|-------------|
| `nomusic.swift` | Source code (compiled during installation) |
| `install.sh` | Compiles and installs the binary + LaunchAgent |
| `uninstall.sh` | Removes everything cleanly |
| `com.isdelnorte.nomusic.plist` | LaunchAgent template |

---

## Español

Reemplaza Apple Music con Spotify para las media keys en macOS.

Cuando presionas Play/Pause sin una app de audio abierta, macOS abre Apple Music automaticamente. NoMusic intercepta ese lanzamiento, mata Apple Music antes de que aparezca y abre Spotify en su lugar.

### Como funciona

Usa `NSWorkspace.willLaunchApplicationNotification` — un evento nativo de macOS que se dispara **antes** de que Apple Music termine de abrir. Es event-driven: **zero CPU en idle**, sin polling ni timers.

### Instalacion rapida (recomendada)

1. **Descarga** el ultimo `NoMusic.pkg` de [Releases](https://github.com/jorgesoto98/nomusic/releases)
2. **Doble-click** en el archivo `.pkg`
3. **Sigue el instalador** — click en "Instalar" e ingresa tu contrasena
4. Listo — NoMusic esta corriendo en segundo plano

Para desinstalar, abre **NoMusic Uninstaller** desde tu carpeta de Aplicaciones.

### Requisitos

- macOS Catalina (10.15) o superior
- Spotify instalado

### Instalacion manual (para desarrolladores)

Requiere [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/).

1. **Instalar Xcode Command Line Tools** (omitir si ya los tienes):

```bash
xcode-select --install
```

2. **Clonar el repositorio** (click en el boton verde **Code** arriba, o):

```bash
git clone https://github.com/jorgesoto98/nomusic.git
cd nomusic
```

3. **Ejecutar el instalador**:

```bash
chmod +x install.sh
./install.sh
```

Esto compila el codigo Swift, copia el binario a `~/.local/bin/`, configura el LaunchAgent y lo activa.

4. **Verificar que esta corriendo**:

```bash
launchctl print gui/$(id -u)/com.isdelnorte.nomusic
```

Si ves info del proceso y `state = running`, todo esta bien.

### Desinstalacion

```bash
chmod +x uninstall.sh
./uninstall.sh
```

### Solucion de problemas

| Problema | Solucion |
|----------|----------|
| `xcode-select: error` | Ejecuta `xcode-select --install` y espera a que descargue |
| El instalador dice "failed to start" | Revisa el estado del agente con `launchctl print gui/$(id -u)/com.isdelnorte.nomusic` |
| Apple Music sigue abriendose | Ejecuta `launchctl print gui/$(id -u)/com.isdelnorte.nomusic` para ver el estado |
| Quieres ver logs | Edita `~/Library/LaunchAgents/com.isdelnorte.nomusic.plist`, cambia `StandardErrorPath` de `/dev/null` a `/tmp/nomusic.log`, y reinicia el agente (ver abajo) |

**Reiniciar el agente manualmente:**

```bash
launchctl bootout gui/$(id -u)/com.isdelnorte.nomusic
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.isdelnorte.nomusic.plist
```

### Archivos

| Archivo | Descripcion |
|---------|-------------|
| `nomusic.swift` | Codigo fuente (se compila durante instalacion) |
| `install.sh` | Compila e instala el binario + LaunchAgent |
| `uninstall.sh` | Elimina todo limpiamente |
| `com.isdelnorte.nomusic.plist` | Template del LaunchAgent |
