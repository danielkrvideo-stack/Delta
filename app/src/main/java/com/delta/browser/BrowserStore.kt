package com.delta.browser

import android.content.Context
import android.util.Log
import org.json.JSONException
import org.json.JSONArray
import org.json.JSONObject

internal data class BrowserPreferences(
    val homepage: String = "https://www.google.com",
    val searchEngine: String = "Google",
    val newTabMode: String = "home",
    val startupMode: String = "restore",
    val theme: String = "System"
)

internal data class BrowserTab(val id: Long, val url: String, val title: String)
internal data class BrowserItem(val title: String, val url: String, val date: Long = System.currentTimeMillis())
internal data class DownloadItem(
    val id: Long,
    val title: String,
    val status: Int,
    val uri: String?,
    val downloadedBytes: Long,
    val totalBytes: Long
) {
    val progress: Int
        get() = if (totalBytes <= 0L) 0 else ((downloadedBytes * 100) / totalBytes).toInt().coerceIn(0, 100)
}

internal class BrowserStore(context: Context) {
    private val preferences = context.getSharedPreferences("delta-browser", Context.MODE_PRIVATE)
    private val tag = "DeltaBrowserStore"

    fun loadPreferences(): BrowserPreferences = BrowserPreferences(
        homepage = preferences.getString("homepage", null) ?: "https://www.google.com",
        searchEngine = preferences.getString("searchEngine", null) ?: "Google",
        newTabMode = preferences.getString("newTabMode", null) ?: "home",
        startupMode = preferences.getString("startupMode", null) ?: "restore",
        theme = preferences.getString("theme", null) ?: "System"
    )

    fun savePreferences(value: BrowserPreferences) {
        preferences.edit()
            .putString("homepage", value.homepage)
            .putString("searchEngine", value.searchEngine)
            .putString("newTabMode", value.newTabMode)
            .putString("startupMode", value.startupMode)
            .putString("theme", value.theme)
            .apply()
    }

    fun loadBookmarks(): List<BrowserItem> = if (preferences.contains("bookmarks")) {
        readItems("bookmarks")
    } else {
        listOf(
            BrowserItem("Google", "https://www.google.com"),
            BrowserItem("YouTube", "https://www.youtube.com"),
            BrowserItem("Wikipedia", "https://www.wikipedia.org"),
            BrowserItem("GitHub", "https://github.com"),
            BrowserItem("Roblox", "https://www.roblox.com")
        )
    }

    fun saveBookmarks(items: List<BrowserItem>) = writeItems("bookmarks", items)

    fun loadShortcuts(): List<BrowserItem> = if (preferences.contains("shortcuts")) {
        readItems("shortcuts")
    } else if (preferences.contains("bookmarks")) {
        readItems("bookmarks")
    } else {
        loadBookmarks()
    }

    fun saveShortcuts(items: List<BrowserItem>) = writeItems("shortcuts", items)

    fun loadHistory(): List<BrowserItem> = readItems("history")

    fun addHistory(item: BrowserItem) {
        if (item.url.startsWith("about:", true) ||
            item.url.startsWith("file:", true) ||
            item.url.startsWith("content:", true) ||
            item.url.startsWith("delta:", true)
        ) return
        val updated = (listOf(item) + loadHistory().filterNot { it.url == item.url }).take(5000)
        writeItems("history", updated)
    }

    fun clearHistory() = preferences.edit().remove("history").apply()

    fun loadTabs(): List<String> {
        val source = preferences.getString("open-tabs", null) ?: return emptyList()
        return try {
            val array = JSONArray(source)
            List(array.length()) { index -> array.getString(index) }.filter { it.isNotBlank() }
        } catch (error: JSONException) {
            Log.w(tag, "Saved tabs are invalid; starting with a new tab", error)
            emptyList()
        }
    }

    fun saveTabs(tabs: List<BrowserTab>) {
        val array = JSONArray()
        tabs.forEach { array.put(it.url) }
        preferences.edit().putString("open-tabs", array.toString()).apply()
    }

    fun loadDownloadIds(): List<Long> {
        val source = preferences.getString("download-ids", null) ?: return emptyList()
        return try {
            val array = JSONArray(source)
            List(array.length()) { index -> array.getLong(index) }
        } catch (error: JSONException) {
            Log.w(tag, "Saved download list is invalid", error)
            emptyList()
        }
    }

    fun addDownloadId(id: Long) {
        val values = (loadDownloadIds() + id).takeLast(100)
        val array = JSONArray()
        values.forEach { array.put(it) }
        preferences.edit().putString("download-ids", array.toString()).apply()
    }

    private fun readItems(key: String): List<BrowserItem> {
        val source = preferences.getString(key, null) ?: return emptyList()
        return try {
            val array = JSONArray(source)
            List(array.length()) { index ->
                val item = array.getJSONObject(index)
                BrowserItem(
                    title = item.optString("title"),
                    url = item.optString("url"),
                    date = item.optLong("date", 0L)
                )
            }
        } catch (error: JSONException) {
            Log.w(tag, "Saved $key data is invalid", error)
            emptyList()
        }
    }

    private fun writeItems(key: String, items: List<BrowserItem>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(JSONObject().apply {
                put("title", item.title)
                put("url", item.url)
                put("date", item.date)
            })
        }
        preferences.edit().putString(key, array.toString()).apply()
    }
}
