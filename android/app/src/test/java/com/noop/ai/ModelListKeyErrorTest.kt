package com.noop.ai

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The model-list key gate: a key saved for one provider is never sent to another provider's
 * (or a Custom) endpoint, so a cross-provider key must REPORT "saved for X" instead of going
 * out without a key and surfacing as a bare 401/empty list.
 */
class ModelListKeyErrorTest {

    @Test
    fun `matching key proceeds`() {
        assertNull(AiCoach.modelListKeyError(AiProvider.OPENAI, "sk-x", true, AiProvider.OPENAI))
        assertNull(AiCoach.modelListKeyError(AiProvider.CUSTOM, "secret", true, AiProvider.CUSTOM))
    }

    @Test
    fun `keyless custom server proceeds unauthenticated`() {
        assertNull(AiCoach.modelListKeyError(AiProvider.CUSTOM, null, false, null))
    }

    @Test
    fun `cross-provider key names its owner instead of sending`() {
        val customErr = AiCoach.modelListKeyError(AiProvider.CUSTOM, null, true, AiProvider.OPENAI)
        assertNotNull(customErr)
        assert(customErr!!.contains("OpenAI")) { "must name the owner: $customErr" }
        val cloudErr = AiCoach.modelListKeyError(AiProvider.ANTHROPIC, null, true, AiProvider.OPENAI)
        assertNotNull(cloudErr)
        assert(cloudErr!!.contains("OpenAI")) { "must name the owner: $cloudErr" }
    }

    @Test
    fun `legacy key serves cloud but never a custom URL`() {
        // Owner null = saved before provider tracking: keeps working for cloud (guarded read allows).
        assertNull(AiCoach.modelListKeyError(AiProvider.OPENAI, "sk-x", true, null))
        // ...but is withheld from a Custom endpoint, never leaked to it.
        val err = AiCoach.modelListKeyError(AiProvider.CUSTOM, "sk-x", true, null)
        assertNotNull(err)
    }

    @Test
    fun `no key at all asks for one on cloud`() {
        val err = AiCoach.modelListKeyError(AiProvider.GEMINI, null, false, null)
        assertNotNull(err)
        assert(err!!.contains("API key")) { "must ask for a key: $err" }
    }
}
