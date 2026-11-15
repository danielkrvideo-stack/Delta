package com.delta.browser

import java.net.URLEncoder
import java.nio.charset.StandardCharsets

internal object BrowserUrlResolver {
    fun resolve(input: String, searchEngine: String): String {
        val value = input.trim()
        if (value.isEmpty()) return ""
        if (value.equals("about", ignoreCase = true) ||
            value.equals("about:blank", ignoreCase = true)
        ) {
            return "about:blank"
        }

        val encoded = URLEncoder.encode(value, StandardCharsets.UTF_8)
        val searchBase = when (searchEngine) {
            "Bing" -> "https://www.bing.com/search?q="
            "DuckDuckGo" -> "https://duckduckgo.com/?q="
            else -> "https://www.google.com/search?q="
        }
        val scheme = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")
        if (scheme.containsMatchIn(value)) {
            if (value.startsWith("https://", true) ||
                value.startsWith("http://", true) ||
                value.startsWith("file://", true)
            ) return value
            val hostWithOptionalPort = Regex("^(?:localhost|[\\w.-]+)(?::\\d+)?(?:/|$)", RegexOption.IGNORE_CASE)
            if (!hostWithOptionalPort.containsMatchIn(value)) return searchBase + encoded
        }
        if (value.any(Char::isWhitespace)) return searchBase + encoded

        val host = value.substringBefore('/')
        if (host.contains('.') || host.startsWith("localhost", ignoreCase = true)) {
            return "https://$value"
        }
        return searchBase + encoded
    }
}
