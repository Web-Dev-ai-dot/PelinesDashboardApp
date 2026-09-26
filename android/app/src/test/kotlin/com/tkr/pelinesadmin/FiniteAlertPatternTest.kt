package com.tkr.pelinesadmin

import org.junit.Assert.*
import org.junit.Test

class FiniteAlertPatternTest {
    private class Task(val at: Long, val run: () -> Unit, var cancelled: Boolean = false)
    private class Harness(val duration: Long = 420) {
        var now = 0L
        val tasks = mutableListOf<Task>()
        val starts = mutableListOf<Long>()
        val completions = mutableListOf<() -> Unit>()
        var activePlayer: Int? = null
        var maximumPlayers = 0
        var stops = 0
        var playbackTask: Task? = null
        fun schedule(ms: Long, action: () -> Unit): () -> Unit {
            val task = Task(now + ms, action)
            tasks.add(task)
            return { task.cancelled = true }
        }
        fun elapse(ms: Long) {
            val target = now + ms
            while (true) {
                val task = tasks.filter { !it.cancelled && it.at <= target }.minByOrNull { it.at } ?: break
                tasks.remove(task)
                now = task.at
                task.run()
            }
            now = target
        }
        val pattern = FiniteAlertPattern(
            schedule = ::schedule,
            playSound = { done ->
                maximumPlayers = maxOf(maximumPlayers, if (activePlayer == null) 1 else 2)
                val id = starts.size
                starts.add(now)
                activePlayer = id
                val complete = {
                    if (activePlayer == id) activePlayer = null
                    done(true)
                }
                completions.add(complete)
                val task = Task(now + duration, complete)
                playbackTask = task
                tasks.add(task)
            },
            stopSound = {
                stops++
                playbackTask?.cancelled = true
                activePlayer = null
            },
        )
    }

    @Test fun exactlyThreeDingsWith350msSilenceAfterEachCompletion() {
        val h = Harness()
        h.pattern.start(3)
        h.elapse(420)
        assertEquals(listOf(0L), h.starts)
        h.elapse(349)
        assertEquals(1, h.starts.size)
        h.elapse(1)
        assertEquals(listOf(0L, 770L), h.starts)
        h.elapse(770)
        assertEquals(listOf(0L, 770L, 1540L), h.starts)
        h.elapse(10000)
        assertEquals(3, h.starts.size)
        assertEquals(1, h.maximumPlayers)
        assertFalse(h.pattern.active)
    }

    @Test fun longWavMustFinishBeforeDelayAndNextDing() {
        val h = Harness(duration = 2000)
        h.pattern.start(3)
        h.elapse(1999)
        assertEquals(1, h.starts.size)
        h.pattern.start(3) // A new cycle cannot overlap a still-active pattern.
        h.elapse(351)
        assertEquals(listOf(0L, 2350L), h.starts)
        h.elapse(5000)
        assertEquals(listOf(0L, 2350L, 4700L), h.starts)
        assertEquals(1, h.maximumPlayers)
    }

    @Test fun stopDuringFirstOrSecondDingOrTheirGapsPreventsAllRemainingDings() {
        for (stopAt in listOf(200L, 500L, 1000L, 1250L)) {
            val h = Harness()
            h.pattern.start(3)
            h.elapse(stopAt)
            val count = h.starts.size
            val staleTasks = h.tasks.toList()
            h.pattern.stop()
            assertNull(h.activePlayer)
            assertFalse(h.pattern.active)
            // Even force-delivering removed Handler callbacks must be harmless.
            staleTasks.forEach { it.run() }
            h.completions.toList().forEach { it() }
            h.elapse(10000)
            assertEquals("stop at $stopAt", count, h.starts.size)
            assertTrue(h.tasks.none { !it.cancelled })
        }
    }

    @Test fun oldCompletionAndOldDelayCannotAffectNextOrder() {
        val h = Harness()
        h.pattern.start(3)
        h.elapse(500)
        val staleDelay = h.tasks.single { !it.cancelled }.run
        val staleCompletion = h.completions.first()
        h.pattern.stop()
        h.pattern.start(3)
        staleDelay()
        staleCompletion()
        h.elapse(3000)
        assertEquals(listOf(0L, 500L, 1270L, 2040L), h.starts)
        assertEquals(1, h.maximumPlayers)
    }

    @Test fun repeatedStartsAndDuplicateCompletionCannotAddExtraDings() {
        val h = Harness()
        h.pattern.start(3)
        repeat(5) { h.pattern.start(3) }
        h.elapse(420)
        repeat(5) { h.completions.first()() }
        h.elapse(3000)
        assertEquals(3, h.starts.size)
        assertEquals(1, h.maximumPlayers)
    }

    @Test fun confirmedSinglePulseAndCountClamping() {
        for (count in listOf(-1, 0, 1, 3, 99)) {
            val h = Harness()
            h.pattern.start(count)
            h.elapse(10000)
            assertEquals(count.coerceIn(1, 3), h.starts.size)
        }
    }

    @Test fun failedPlaybackDoesNotScheduleMoreDings() {
        var scheduled = 0
        val pattern = FiniteAlertPattern(
            schedule = { _, _ -> scheduled++; {} },
            playSound = { it(false) },
            stopSound = {},
        )
        pattern.start(3)
        assertFalse(pattern.active)
        assertEquals(0, scheduled)
    }
}
