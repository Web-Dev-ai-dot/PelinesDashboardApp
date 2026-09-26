package com.tkr.pelinesadmin

/** A finite native effect, not a recurring alert/session coordinator.
 * All methods and callbacks execute on the main thread. Each gap starts only
 * after the preceding player has finished and released its resources.
 */
internal class FiniteAlertPattern(
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val playSound: ((Boolean) -> Unit) -> Unit,
    private val stopSound: () -> Unit,
) {
    var active = false
        private set
    private var generation = 0L
    private var cancelDelay: (() -> Unit)? = null

    fun start(soundCount: Int) {
        if (active) return
        val token = ++generation
        active = true
        ding(token, soundCount.coerceIn(1, 3))
    }

    private fun ding(token: Long, remaining: Int) {
        if (!active || token != generation) return
        var completed = false
        playSound { success ->
            if (completed || !active || token != generation) return@playSound
            completed = true
            if (!success || remaining == 1) {
                active = false
            } else {
                cancelDelay = schedule(350L) {
                    if (active && token == generation) {
                        cancelDelay = null
                        ding(token, remaining - 1)
                    }
                }
            }
        }
    }

    fun stop() {
        ++generation
        active = false
        cancelDelay?.invoke()
        cancelDelay = null
        stopSound()
    }
}
