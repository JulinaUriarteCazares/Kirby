package com.norte.compass

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.TimeText

private val Background = Color(0xFF171329)
private val Pink = Color(0xFFFF7EBD)
private val PinkLight = Color(0xFFFFB4D6)
private val Ink = Color(0xFF29213E)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { CompassScreen() }
    }
}

@Composable
private fun CompassScreen() {
    val context = LocalContext.current
    var heading by remember { mutableFloatStateOf(0f) }
    var active by remember { mutableStateOf(true) }
    var mouthOpen by remember { mutableStateOf(false) }

    DisposableEffect(active) {
        if (!active) return@DisposableEffect onDispose { }
        val manager = context.getSystemService(SensorManager::class.java)
        val rotation = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        val listener = object : SensorEventListener {
            private val matrix = FloatArray(9)
            private val orientation = FloatArray(3)

            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(matrix, event.values)
                SensorManager.getOrientation(matrix, orientation)
                heading = Math.toDegrees(orientation[0].toDouble()).toFloat().normalize()
            }

            override fun onAccuracyChanged(sensor: Sensor?, sensorAccuracy: Int) {
                Unit
            }
        }
        if (rotation != null) manager.registerListener(listener, rotation, SensorManager.SENSOR_DELAY_GAME)
        onDispose { manager.unregisterListener(listener) }
    }

    MaterialTheme {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Background)
        ) {
            Kirby(
                mouthOpen = mouthOpen,
                modifier = Modifier
                    .fillMaxSize()
                    .clickable { mouthOpen = !mouthOpen }
            )

            TimeText()
        }
    }
}

@Composable
private fun Kirby(mouthOpen: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val center = Offset(size.width / 2, size.height / 2)
        val unit = size.minDimension / 220f
        val scale = { value: Float -> value * unit }

        drawCircle(Color(0x332D234A), scale(99f), Offset(center.x, center.y + scale(8f)))
        drawOval(
            color = Color(0xFFEC5A9F),
            topLeft = Offset(center.x - scale(116f), center.y - scale(30f)),
            size = androidx.compose.ui.geometry.Size(scale(54f), scale(36f))
        )
        drawOval(
            color = Color(0xFFEC5A9F),
            topLeft = Offset(center.x + scale(62f), center.y - scale(30f)),
            size = androidx.compose.ui.geometry.Size(scale(54f), scale(36f))
        )
        drawOval(
            color = Color(0xFFE94C91),
            topLeft = Offset(center.x - scale(72f), center.y + scale(67f)),
            size = androidx.compose.ui.geometry.Size(scale(62f), scale(37f))
        )
        drawOval(
            color = Color(0xFFE94C91),
            topLeft = Offset(center.x + scale(10f), center.y + scale(67f)),
            size = androidx.compose.ui.geometry.Size(scale(62f), scale(37f))
        )
        drawCircle(Pink, scale(82f), Offset(center.x, center.y))
        drawCircle(PinkLight.copy(alpha = .35f), scale(51f), Offset(center.x - scale(28f), center.y - scale(29f)))

        drawOval(
            color = Ink,
            topLeft = Offset(center.x - scale(35f), center.y - scale(45f)),
            size = androidx.compose.ui.geometry.Size(scale(17f), scale(39f))
        )
        drawOval(
            color = Ink,
            topLeft = Offset(center.x + scale(18f), center.y - scale(45f)),
            size = androidx.compose.ui.geometry.Size(scale(17f), scale(39f))
        )
        drawOval(
            color = Color.White,
            topLeft = Offset(center.x - scale(31f), center.y - scale(39f)),
            size = androidx.compose.ui.geometry.Size(scale(7f), scale(13f))
        )
        drawOval(
            color = Color.White,
            topLeft = Offset(center.x + scale(22f), center.y - scale(39f)),
            size = androidx.compose.ui.geometry.Size(scale(7f), scale(13f))
        )
        drawOval(
            color = Color(0xFFE93F7E),
            topLeft = Offset(center.x - scale(66f), center.y - scale(2f)),
            size = androidx.compose.ui.geometry.Size(scale(29f), scale(16f))
        )
        drawOval(
            color = Color(0xFFE93F7E),
            topLeft = Offset(center.x + scale(37f), center.y - scale(2f)),
            size = androidx.compose.ui.geometry.Size(scale(29f), scale(16f))
        )

        if (mouthOpen) {
            drawOval(
                color = Ink,
                topLeft = Offset(center.x - scale(25f), center.y + scale(6f)),
                size = androidx.compose.ui.geometry.Size(scale(50f), scale(54f))
            )
            drawOval(
                color = Color(0xFFFF6F9F),
                topLeft = Offset(center.x - scale(17f), center.y + scale(29f)),
                size = androidx.compose.ui.geometry.Size(scale(34f), scale(24f))
            )
        } else {
            drawArc(
                color = Ink,
                startAngle = 20f,
                sweepAngle = 140f,
                useCenter = false,
                topLeft = Offset(center.x - scale(17f), center.y + scale(1f)),
                size = androidx.compose.ui.geometry.Size(scale(34f), scale(22f)),
                style = Stroke(scale(4f), cap = StrokeCap.Round)
            )
        }
    }
}

private fun Float.normalize(): Float = ((this % 360f) + 360f) % 360f
