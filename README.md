# Pik

**Grabador de pantalla, cámara y voz para macOS. Todo queda en tu equipo.**

Pik es una app nativa (Swift, SwiftUI y AppKit) que vive en la barra de menús. Sirve para grabar reuniones, tutoriales y demos, y para compartir el resultado sin cuentas ni nube.

https://github.com/user-attachments/assets/8ee0fe1c-6dbe-476f-854a-a2beee5b6ff5

## Funciones

**Grabación**
- Pantalla completa, ventana, área a medida o solo cámara.
- Barra flotante con micrófono, cámara, privacidad, cuenta regresiva, pausa y reinicio.
- Burbuja de cámara con forma, tamaño y fondo difuminado o personalizado.
- Dibujo sobre la pantalla, resaltado de clics y ocultación de íconos, barra de menús y Dock.
- Audio de micrófono y del sistema con reducción de ruido.
- MP4 en H.264 o HEVC, a 24, 30 o 60 fps. Recupera la grabación si la app se cierra por sorpresa.

**Notas en pantalla**
- Crea todas las notas que necesites (guion, puntos de una demo, agenda) y elige cuál mostrar mientras grabas.
- Solo tú las ves: no aparecen en el video.

**Control sin tocar el mouse**
- Atajos globales configurables.
- Activación por voz: di «Pik» y empieza la grabación (macOS 26 o superior).
- Gestos de mano: graba tu propio gesto para iniciar, pausar y detener.

**Biblioteca y edición**
- Biblioteca de videos y de notas, con búsqueda y modo claro u oscuro.
- Vista previa con recorte y exportación a MP4, GIF, audio y subtítulos `.srt`.
- Transcripción automática en tu Mac, en español o inglés (detecta el idioma o se fija en Ajustes).

**Compartir**
- Enlace para ver el video desde cualquier dispositivo de tu red, con privacidad *Solo yo* o *Cualquiera con el enlace*.
- Compartir el archivo por AirDrop, Mensajes, Mail y otras apps del sistema.

**Idioma**
- Interfaz en español e inglés. Usa el idioma del sistema y se puede cambiar en Ajustes.

## Instalación

**Requisitos:** macOS 14 o superior (Apple Silicon e Intel).

1. Descarga `Pik.zip` desde [Releases](../../releases/latest) y descomprímelo.
2. Abre `Pik.app` con clic derecho → **Abrir**. La firma es *ad-hoc* (no está notarizada), por eso macOS lo pide solo la primera vez.
3. Concede **Grabación de pantalla** y, si los vas a usar, **Cámara**, **Micrófono** y **Reconocimiento de voz**. Tras dar la grabación de pantalla, pulsa **Reiniciar Pik**.
4. Busca el zorrito en la barra de menús o pulsa `⌃⌥P`.

### Atajos por defecto

| Acción | Atajo |
|---|---|
| Abrir controles | `⌃⌥P` |
| Iniciar / detener | `⌃⌥R` |
| Pausar / reanudar | `⌃⌥T` |
| Cancelar | `⌃⌥X` |

También hay un esquema de URL: `pik://record`, `pik://stop`, `pik://pause`, `pik://library`, `pik://settings`.

### Compilar desde el código

Requiere las Command Line Tools de Xcode.

```bash
git clone https://github.com/HANA0KA/Pik.git && cd Pik
scripts/build-app.sh --install   # compila, firma y copia Pik.app al Escritorio
swift test                       # pruebas
```

## Privacidad

- La grabación, la transcripción, la voz y los gestos se procesan en tu Mac. Pik no tiene cuentas ni servidores.
- El enlace para compartir lo sirve tu propio Mac, solo en tu red y mientras Pik esté abierto. Es HTTP sin cifrar: úsalo en redes de confianza.
- Videos en `~/Movies/Pik` (configurable). Datos en `~/Library/Application Support/Pik`.
