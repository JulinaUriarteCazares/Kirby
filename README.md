# Norte Compass para Wear OS

Aplicación nativa para relojes Android/Wear OS. Lee el sensor `TYPE_ROTATION_VECTOR` para actualizar el rumbo en tiempo real y muestra una brújula optimizada para pantalla circular.

## Abrir y ejecutar

1. Instala [Android Studio](https://developer.android.com/studio) con Android SDK 35.
2. Abre esta carpeta (`smartwatch`) como proyecto existente.
3. Espera a que Gradle sincronice las dependencias.
4. En el reloj activa **Opciones de desarrollador** y **Depuración por Wi-Fi** (o usa un emulador Wear OS).
5. Selecciona el reloj como dispositivo y pulsa **Run**.

La aplicación no requiere permisos peligrosos: el sensor de orientación se usa mientras la pantalla de la brújula está activa. Algunos modelos no incluyen magnetómetro; en esos relojes el rumbo puede ser menos preciso o no estar disponible.

## Solución de problemas de Gradle

Si Android Studio muestra `Could not load wrapper properties`, verifica que exista el archivo `gradle/wrapper/gradle-wrapper.properties` y vuelve a sincronizar el proyecto desde **File > Sync Project with Gradle Files**.

Este proyecto debe ejecutarse con **JDK 17**. En Android Studio selecciónalo en **File > Settings > Build, Execution, Deployment > Build Tools > Gradle > Gradle JDK**. Si no aparece, instala un JDK 17 y selecciónalo en ese mismo apartado. Después pulsa **File > Sync Project with Gradle Files**.

Si Gradle falla mostrando únicamente una versión como `25.0.3`, está usando JDK 25.
Instala JDK 17 y selecciónalo como **Gradle JDK**; cambiar el `jvmTarget` del
código no sustituye el JDK con el que se ejecuta Gradle.
