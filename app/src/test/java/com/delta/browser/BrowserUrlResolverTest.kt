package com.delta.browser

import org.junit.Assert.assertEquals
import org.junit.Test

class BrowserUrlResolverTest {
    @Test
    fun resolvesWebAddressesWithoutChangingExplicitSchemes() {
        assertEquals("https://example.com/path", BrowserUrlResolver.resolve("example.com/path", "Google"))
        assertEquals("http://example.com", BrowserUrlResolver.resolve("http://example.com", "Google"))
        assertEquals("https://example.com:8443/path", BrowserUrlResolver.resolve("example.com:8443/path", "Google"))
        assertEquals("https://localhost:8080", BrowserUrlResolver.resolve("localhost:8080", "Google"))
    }

    @Test
    fun mapsAboutToAnEmptyPage() {
        assertEquals("about:blank", BrowserUrlResolver.resolve("about", "Google"))
        assertEquals("about:blank", BrowserUrlResolver.resolve("ABOUT:BLANK", "Google"))
    }

    @Test
    fun searchesQueriesAndUnsupportedSchemes() {
        assertEquals(
            "https://www.google.com/search?q=delta+browser",
            BrowserUrlResolver.resolve("delta browser", "Google")
        )
        assertEquals(
            "https://duckduckgo.com/?q=javascript%3Aalert%281%29",
            BrowserUrlResolver.resolve("javascript:alert(1)", "DuckDuckGo")
        )
    }
}
