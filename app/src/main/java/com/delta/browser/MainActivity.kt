package com.delta.browser

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.URLUtil
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewStartUpConfig
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tab
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.io.FileNotFoundException
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val HOME_URL = "delta://home"
private const val OFFLINE_URL = "delta://offline"
private const val DINO_ASSET_URL = "https://appassets.androidplatform.net/assets/dino.html"
private const val LOG_TAG = "DeltaBrowser"

class MainActivity : ComponentActivity() {
    private val pendingUri = mutableStateOf<Uri?>(null)
    private val webViewStartupReady = mutableStateOf(false)
    private val webViewStartupExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingUri.value = intent?.data
        WebViewCompat.startUpWebView(
            WebViewStartUpConfig.Builder(webViewStartupExecutor)
                .setShouldRunUiThreadStartUpTasks(true)
                .build(),
            object : WebViewCompat.WebViewStartUpCallback {
                override fun onSuccess(result: androidx.webkit.WebViewStartUpResult) {
                    if (!isFinishing && !isDestroyed) webViewStartupReady.value = true
                }
            }
        )
        setContent {
            DeltaBrowserApp(
                incomingUri = pendingUri.value,
                consumeIncomingUri = { pendingUri.value = null },
                webViewStartupReady = webViewStartupReady.value
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingUri.value = intent.data
    }

    override fun onDestroy() {
        webViewStartupExecutor.shutdown()
        super.onDestroy()
    }
}

private enum class BrowserPanel { Tabs, Bookmarks, History, Downloads, Settings }
private enum class AddItemTarget { Bookmark, Shortcut }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DeltaBrowserApp(
    incomingUri: Uri?,
    consumeIncomingUri: () -> Unit,
    webViewStartupReady: Boolean
) {
    val context = LocalContext.current
    val activity = context as ComponentActivity
    val store = remember { BrowserStore(context) }
    var preferences by remember { mutableStateOf(store.loadPreferences()) }
    val tabs = remember { mutableStateListOf<BrowserTab>() }
    val bookmarks = remember { mutableStateListOf<BrowserItem>().apply { addAll(store.loadBookmarks()) } }
    val shortcuts = remember { mutableStateListOf<BrowserItem>().apply { addAll(store.loadShortcuts()) } }
    val history = remember { mutableStateListOf<BrowserItem>().apply { addAll(store.loadHistory()) } }
    val webViews = remember { mutableStateMapOf<Long, WebView>() }
    val documentHtml = remember { mutableStateMapOf<Long, String>() }
    val loadedDocuments = remember { mutableStateListOf<Long>() }
    var currentTabId by remember { mutableLongStateOf(0L) }
    var panel by remember { mutableStateOf<BrowserPanel?>(null) }
    var menuExpanded by remember { mutableStateOf(false) }
    var addressValue by remember { mutableStateOf(TextFieldValue("")) }
    var addressFocused by remember { mutableStateOf(false) }
    var downloads by remember { mutableStateOf(emptyList<DownloadItem>()) }
    var bookmarkTitle by remember { mutableStateOf("") }
    var bookmarkUrl by remember { mutableStateOf("") }
    var addItemTarget by remember { mutableStateOf<AddItemTarget?>(null) }
    var pageProgress by remember { mutableStateOf(0) }
    var pageLoading by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    fun loadHtmlUri(uri: Uri) {
        runCatching {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        scope.launch {
            try {
                val html = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                        ?: throw FileNotFoundException("Cannot read selected HTML file")
                }
                var tab = tabs.firstOrNull { it.id == currentTabId }
                if (tab == null) {
                    tab = BrowserTab(newTabId(), HOME_URL, "Новая вкладка")
                    tabs.add(tab)
                    currentTabId = tab.id
                }
                documentHtml[tab.id] = html
                loadedDocuments.remove(tab.id)
                updateTab(tabs, tab.id, uri.toString(), displayName(context, uri))
                addressValue = TextFieldValue(displayName(context, uri))
            } catch (error: Exception) {
                Toast.makeText(context, "Не удалось открыть HTML: ${error.localizedMessage}", Toast.LENGTH_LONG).show()
            }
        }
    }

    val openHtml = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) loadHtmlUri(uri)
    }

    val currentTab = tabs.firstOrNull { it.id == currentTabId }
    val isDark = when (preferences.theme) {
        "Dark" -> true
        "Light" -> false
        else -> androidx.compose.foundation.isSystemInDarkTheme()
    }

    SideEffect {
        activity.window.statusBarColor = (if (isDark) Color(0xFF121318) else Color(0xFFF8F9FC)).toArgb()
        activity.window.navigationBarColor = (if (isDark) Color(0xFF121318) else Color(0xFFF8F9FC)).toArgb()
        WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
            isAppearanceLightStatusBars = !isDark
            isAppearanceLightNavigationBars = !isDark
        }
    }

    fun saveTabs() {
        store.saveTabs(tabs)
    }

    fun newTab(url: String? = null) {
        val target = url ?: if (preferences.newTabMode == "about") "about:blank" else HOME_URL
        val tab = BrowserTab(newTabId(), target, if (target == HOME_URL) "Новая вкладка" else target)
        tabs.add(tab)
        currentTabId = tab.id
        addressValue = TextFieldValue(if (target == HOME_URL) "" else target)
        saveTabs()
    }

    fun navigateTo(raw: String, tabId: Long = currentTabId) {
        val tab = tabs.firstOrNull { it.id == tabId } ?: return
        val destination = when {
            raw == HOME_URL || raw == OFFLINE_URL -> raw
            raw.startsWith("content://", true) || raw.startsWith("file://", true) -> raw
            else -> BrowserUrlResolver.resolve(raw, preferences.searchEngine)
        }
        if (destination.isBlank()) return
        documentHtml.remove(tabId)
        loadedDocuments.remove(tabId)
        updateTab(tabs, tabId, destination, if (destination == HOME_URL) "Новая вкладка" else destination)
        if (tabId == currentTabId) {
            addressValue = TextFieldValue(if (destination == HOME_URL) "" else destination)
            addressFocused = false
        }
        saveTabs()
    }

    fun loadDownloadedItems() {
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val result = mutableListOf<DownloadItem>()
        store.loadDownloadIds().forEach { id ->
            val cursor = manager.query(DownloadManager.Query().setFilterById(id)) ?: return@forEach
            cursor.use {
                if (it.moveToFirst()) {
                    val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    val title = it.getString(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)) ?: "Файл"
                    val downloaded = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    val uri = if (status == DownloadManager.STATUS_SUCCESSFUL) {
                        manager.getUriForDownloadedFile(id)?.toString()
                    } else null
                    result.add(DownloadItem(id, title, status, uri, downloaded, total))
                }
            }
        }
        downloads = result.reversed()
    }

    fun downloadFile(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        try {
            val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val name = URLUtil.guessFileName(url, contentDisposition, mimeType)
            val request = DownloadManager.Request(Uri.parse(url))
                .setTitle(name)
                .setDescription("Загрузка в Delta")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, name)
            userAgent?.takeIf { it.isNotBlank() }?.let { request.addRequestHeader("User-Agent", it) }
            CookieManager.getInstance().getCookie(url)?.let { request.addRequestHeader("Cookie", it) }
            store.addDownloadId(manager.enqueue(request))
            Toast.makeText(context, "Загрузка началась: $name", Toast.LENGTH_SHORT).show()
        } catch (error: Exception) {
            Toast.makeText(context, "Не удалось начать загрузку: ${error.localizedMessage}", Toast.LENGTH_LONG).show()
        }
    }

    fun openDownload(item: DownloadItem) {
        val uri = item.uri?.let(Uri::parse) ?: return
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, context.contentResolver.getType(uri) ?: "*/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(intent) }
            .onFailure {
                Toast.makeText(context, "Не найдено приложение для открытия файла", Toast.LENGTH_SHORT).show()
            }
    }

    fun createTabWebView(tabId: Long): WebView = createBrowserWebView(
        context = context,
        tabId = tabId,
        onLocation = { id, url ->
            val actualUrl = if (url.startsWith(DINO_ASSET_URL)) OFFLINE_URL else url
            updateTab(tabs, id, actualUrl, if (actualUrl == OFFLINE_URL) "Нет подключения" else url)
            if (id == currentTabId && !addressFocused) {
                addressValue = TextFieldValue(if (actualUrl == OFFLINE_URL) "" else actualUrl)
            }
        },
        onTitle = { id, title ->
            val existing = tabs.firstOrNull { it.id == id }
            if (existing != null && title.isNotBlank()) updateTab(tabs, id, existing.url, title)
        },
        onPageFinished = { id, title, url ->
            if (id == currentTabId) {
                pageLoading = false
                pageProgress = 100
            }
            if (!url.startsWith("file:", true) &&
                !url.startsWith("about:", true) &&
                !url.startsWith(DINO_ASSET_URL)
            ) {
                val item = BrowserItem(title.ifBlank { url }, url)
                store.addHistory(item)
                history.removeAll { it.url == url }
                history.add(0, item)
                if (history.size > 5000) history.removeAt(history.lastIndex)
            }
            if (id == currentTabId && !addressFocused &&
                url.startsWith("http", true) &&
                !url.startsWith(DINO_ASSET_URL)
            ) {
                addressValue = TextFieldValue(url)
            }
        },
        onLoading = { loading, progress ->
            if (tabId == currentTabId) {
                pageLoading = loading
                pageProgress = progress
            }
        },
        onOffline = { id ->
            updateTab(tabs, id, OFFLINE_URL, "Нет подключения")
            if (id == currentTabId) addressValue = TextFieldValue("")
        },
        onOpenInNewTab = { url -> newTab(url) },
        onDownload = { url, userAgent, disposition, mimeType ->
            downloadFile(url, userAgent, disposition, mimeType)
        }
    )

    fun closeTabWebView(id: Long) {
        webViews.remove(id)?.let { view ->
            (view.parent as? ViewGroup)?.removeView(view)
            view.stopLoading()
            view.destroy()
        }
    }

    LaunchedEffect(Unit) {
        val restored = if (preferences.startupMode == "restore") store.loadTabs() else emptyList()
        restored.forEach { url ->
            tabs.add(BrowserTab(newTabId(), url, if (url == HOME_URL) "Новая вкладка" else url))
        }
        if (tabs.isEmpty()) newTab()
        else {
            currentTabId = tabs.last().id
            addressValue = TextFieldValue(if (tabs.last().url == HOME_URL) "" else tabs.last().url)
        }
    }

    LaunchedEffect(incomingUri, tabs.isEmpty()) {
        val uri = incomingUri ?: return@LaunchedEffect
        if (tabs.isEmpty()) return@LaunchedEffect
        when (uri.scheme?.lowercase(Locale.ROOT)) {
            "http", "https" -> {
                navigateTo(uri.toString())
            }
            "about" -> {
                navigateTo("about:blank")
            }
            "content", "file" -> loadHtmlUri(uri)
            else -> Unit
        }
        consumeIncomingUri()
    }

    LaunchedEffect(panel) {
        while (panel == BrowserPanel.Downloads) {
            loadDownloadedItems()
            delay(1000)
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) store.saveTabs(tabs)
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            if (activity.isFinishing) webViews.keys.toList().forEach { closeTabWebView(it) }
        }
    }

    BackHandler(enabled = currentTab != null) {
        val view = webViews[currentTabId]
        when {
            view?.canGoBack() == true -> view.goBack()
            tabs.size > 1 -> {
                closeTabWebView(currentTabId)
                tabs.removeAll { it.id == currentTabId }
                currentTabId = tabs.last().id
                addressValue = TextFieldValue(if (tabs.last().url == HOME_URL) "" else tabs.last().url)
                saveTabs()
            }
            else -> navigateTo(HOME_URL)
        }
    }

    MaterialTheme(colorScheme = if (isDark) darkColorScheme(primary = Color(0xFF91A4FF)) else lightColorScheme(primary = Color(0xFF4361EE))) {
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .onPreviewKeyEvent { event ->
                    if (event.type != KeyEventType.KeyUp || !event.isCtrlPressed) return@onPreviewKeyEvent false
                    when (event.key) {
                        Key.T -> { newTab(); true }
                        Key.W -> {
                            if (tabs.size > 1) {
                                closeTabWebView(currentTabId)
                                tabs.removeAll { it.id == currentTabId }
                                currentTabId = tabs.last().id
                                saveTabs()
                            }
                            true
                        }
                        Key.L -> { focusRequester.requestFocus(); true }
                        else -> false
                    }
                },
            color = MaterialTheme.colorScheme.background
        ) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars)) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 4.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { webViews[currentTabId]?.takeIf { it.canGoBack() }?.goBack() }) {
                        Icon(Icons.Default.ArrowBack, "Назад")
                    }
                    IconButton(onClick = { webViews[currentTabId]?.takeIf { it.canGoForward() }?.goForward() }) {
                        Icon(Icons.Default.ArrowForward, "Вперёд")
                    }
                    IconButton(onClick = {
                        val view = webViews[currentTabId]
                        if (pageLoading) view?.stopLoading() else view?.reload()
                    }) {
                        Icon(if (pageLoading) Icons.Default.Close else Icons.Default.Refresh, "Обновить")
                    }
                    val addressFocusRequester = focusRequester
                    Surface(
                        modifier = Modifier.weight(1f).height(44.dp),
                        shape = RoundedCornerShape(24.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp)) {
                            Icon(Icons.Default.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.width(8.dp))
                            BasicTextField(
                                value = addressValue,
                                onValueChange = { addressValue = it },
                                modifier = Modifier
                                    .weight(1f)
                                    .focusRequester(addressFocusRequester)
                                    .onFocusChanged { state ->
                                        if (state.isFocused && !addressFocused) {
                                            addressValue = addressValue.copy(selection = TextRange(0, addressValue.text.length))
                                        }
                                        addressFocused = state.isFocused
                                    },
                                singleLine = true,
                                textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface),
                                keyboardOptions = KeyboardOptions(
                                    keyboardType = KeyboardType.Uri,
                                    imeAction = ImeAction.Go,
                                    autoCorrectEnabled = false
                                ),
                                keyboardActions = KeyboardActions(onGo = { navigateTo(addressValue.text) }),
                                decorationBox = { inner ->
                                    Box {
                                        if (addressValue.text.isEmpty()) {
                                            Text("Искать", color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                        inner()
                                    }
                                }
                            )
                            if (addressFocused && addressValue.text.isNotEmpty()) {
                                IconButton(onClick = { addressValue = TextFieldValue("") }, modifier = Modifier.size(30.dp)) {
                                    Icon(Icons.Default.Close, "Очистить адрес", modifier = Modifier.size(17.dp))
                                }
                            }
                        }
                    }
                    IconButton(onClick = { navigateTo(addressValue.text) }) {
                        Icon(Icons.Default.OpenInBrowser, "Перейти")
                    }
                    IconButton(onClick = { newTab() }) {
                        Icon(Icons.Default.Add, "Новая вкладка")
                    }
                }

                if (tabs.size > 1) {
                    Row(
                        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        tabs.forEach { tab ->
                            Surface(
                                shape = RoundedCornerShape(14.dp),
                                color = if (tab.id == currentTabId) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
                                modifier = Modifier.width(150.dp).clickable {
                                    currentTabId = tab.id
                                    addressValue = TextFieldValue(if (tab.url == HOME_URL) "" else tab.url)
                                }
                            ) {
                                Row(Modifier.padding(start = 10.dp, end = 2.dp, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(tab.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp)
                                    IconButton(onClick = {
                                        if (tabs.size > 1) {
                                            tabs.removeAll { it.id == tab.id }
                                            closeTabWebView(tab.id)
                                            currentTabId = tabs.last().id
                                            saveTabs()
                                        } else newTab()
                                    }, modifier = Modifier.size(30.dp)) {
                                        Icon(Icons.Default.Close, "Закрыть вкладку", modifier = Modifier.size(15.dp))
                                    }
                                }
                            }
                        }
                    }
                }

                Box(Modifier.weight(1f).fillMaxWidth()) {
                    val tab = currentTab
                    AndroidView(
                        modifier = Modifier.fillMaxSize(),
                        factory = {
                            FrameLayout(it).apply {
                                setBackgroundColor(android.graphics.Color.WHITE)
                            }
                        },
                        update = { host ->
                            tabs.forEach { browserTab ->
                                var view = webViews[browserTab.id]
                                if (view == null && browserTab.url != HOME_URL && webViewStartupReady) {
                                    view = createTabWebView(browserTab.id)
                                    webViews[browserTab.id] = view
                                    host.addView(
                                        view,
                                        FrameLayout.LayoutParams(
                                            ViewGroup.LayoutParams.MATCH_PARENT,
                                            ViewGroup.LayoutParams.MATCH_PARENT
                                        )
                                    )
                                }
                                if (view != null) {
                                    if (view.parent == null) {
                                        host.addView(
                                            view,
                                            FrameLayout.LayoutParams(
                                                ViewGroup.LayoutParams.MATCH_PARENT,
                                                ViewGroup.LayoutParams.MATCH_PARENT
                                            )
                                        )
                                    }
                                    val active = browserTab.id == currentTabId && browserTab.url != HOME_URL
                                    view.visibility = if (active) View.VISIBLE else View.GONE
                                    if (active) view.onResume() else view.onPause()

                                    if (browserTab.url != HOME_URL) {
                                        val target = when {
                                            browserTab.url == OFFLINE_URL -> DINO_ASSET_URL
                                            else -> browserTab.url
                                        }
                                        if (browserTab.url.startsWith("content:", true) ||
                                            browserTab.url.startsWith("file:", true)
                                        ) {
                                            val html = documentHtml[browserTab.id]
                                            if (html != null && !loadedDocuments.contains(browserTab.id)) {
                                                loadedDocuments.add(browserTab.id)
                                                view.loadDataWithBaseURL(
                                                    browserTab.url,
                                                    html,
                                                    "text/html",
                                                    "UTF-8",
                                                    browserTab.url
                                                )
                                            }
                                        } else if (view.url != target) {
                                            view.loadUrl(target)
                                        }
                                    }
                                }
                            }
                            val openIds = tabs.mapTo(mutableSetOf()) { it.id }
                            webViews.keys.filter { it !in openIds }.forEach { closeTabWebView(it) }
                        }
                    )
                    when {
                        tab == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text("Загрузка Delta…")
                        }
                        tab.url == HOME_URL -> StartPage(
                            shortcuts = shortcuts,
                            history = history,
                            onNavigate = { navigateTo(it) },
                            onAddSite = {
                                bookmarkTitle = ""
                                bookmarkUrl = ""
                                addItemTarget = AddItemTarget.Shortcut
                            }
                        )
                        !webViewStartupReady -> Column(
                            Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            CircularProgressIndicator()
                            Spacer(Modifier.height(12.dp))
                            Text("Подготовка веб-движка Delta…")
                        }
                    }
                    if (pageLoading && pageProgress in 1..99) {
                        androidx.compose.material3.LinearProgressIndicator(
                            progress = { pageProgress / 100f },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = {
                        navigateTo(if (preferences.homepage.equals("about", true)) "about:blank" else preferences.homepage)
                    }) { Icon(Icons.Default.Home, "Домой") }
                    IconButton(onClick = {
                        val tab = currentTab
                        if (tab != null && !tab.url.startsWith("about:") && !tab.url.startsWith("delta:")) {
                            val exists = bookmarks.any { it.url == tab.url }
                            if (exists) {
                                bookmarks.removeAll { it.url == tab.url }
                                store.saveBookmarks(bookmarks)
                                Toast.makeText(context, "Удалено из закладок", Toast.LENGTH_SHORT).show()
                            } else {
                                bookmarks.add(0, BrowserItem(tab.title.ifBlank { tab.url }, tab.url))
                                store.saveBookmarks(bookmarks)
                                Toast.makeText(context, "Добавлено в закладки", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }) {
                        Icon(
                            Icons.Default.Bookmark,
                            if (bookmarks.any { it.url == currentTab?.url }) "Удалить из закладок" else "Добавить в закладки"
                        )
                    }
                    IconButton(onClick = { panel = BrowserPanel.Tabs }) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Tab, "Вкладки")
                            Text(tabs.size.toString(), fontSize = 9.sp, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                    Box {
                        IconButton(onClick = { menuExpanded = true }) { Icon(Icons.Default.MoreVert, "Меню") }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(text = { Text("Закладки") }, leadingIcon = { Icon(Icons.Default.Bookmarks, null) }, onClick = { menuExpanded = false; panel = BrowserPanel.Bookmarks })
                            DropdownMenuItem(text = { Text("История") }, leadingIcon = { Icon(Icons.Default.History, null) }, onClick = { menuExpanded = false; panel = BrowserPanel.History })
                            DropdownMenuItem(text = { Text("Загрузки") }, leadingIcon = { Icon(Icons.Default.Download, null) }, onClick = { menuExpanded = false; loadDownloadedItems(); panel = BrowserPanel.Downloads })
                            DropdownMenuItem(text = { Text("Открыть HTML-файл") }, leadingIcon = { Icon(Icons.Default.OpenInBrowser, null) }, onClick = { menuExpanded = false; openHtml.launch(arrayOf("text/html", "application/xhtml+xml")) })
                            DropdownMenuItem(text = { Text("Настройки") }, leadingIcon = { Icon(Icons.Default.Settings, null) }, onClick = { menuExpanded = false; panel = BrowserPanel.Settings })
                        }
                    }
                }
            }
        }
    }

    LaunchedEffect(currentTab?.id, currentTab?.url) {
        val tab = currentTab ?: return@LaunchedEffect
        if (!addressFocused) {
            addressValue = TextFieldValue(if (tab.url == HOME_URL || tab.url == OFFLINE_URL) "" else tab.url)
        }
    }

    addItemTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { addItemTarget = null },
            title = { Text(if (target == AddItemTarget.Shortcut) "Добавить быстрый сайт" else "Добавить закладку") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(bookmarkTitle, { bookmarkTitle = it }, label = { Text("Название") }, singleLine = true)
                    OutlinedTextField(bookmarkUrl, { bookmarkUrl = it }, label = { Text("Адрес") }, singleLine = true)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val url = BrowserUrlResolver.resolve(bookmarkUrl, preferences.searchEngine)
                    if (bookmarkTitle.isNotBlank() && url.startsWith("http")) {
                        val item = BrowserItem(bookmarkTitle.trim(), url)
                        if (target == AddItemTarget.Shortcut) {
                            shortcuts.removeAll { it.url == url }
                            shortcuts.add(0, item)
                            store.saveShortcuts(shortcuts)
                        } else {
                            bookmarks.removeAll { it.url == url }
                            bookmarks.add(0, item)
                            store.saveBookmarks(bookmarks)
                        }
                        addItemTarget = null
                    }
                }) { Text("Сохранить") }
            },
            dismissButton = { TextButton(onClick = { addItemTarget = null }) { Text("Отмена") } }
        )
    }

    panel?.let { activePanel ->
        when (activePanel) {
            BrowserPanel.Tabs -> TabsDialog(
                tabs = tabs,
                selectedId = currentTabId,
                onSelect = { id ->
                    currentTabId = id
                    panel = null
                },
                onClose = { id ->
                    if (tabs.size > 1) {
                        closeTabWebView(id)
                        tabs.removeAll { it.id == id }
                        if (id == currentTabId) currentTabId = tabs.last().id
                        saveTabs()
                    } else newTab()
                },
                onNew = { newTab(); panel = null },
                onDismiss = { panel = null }
            )
            BrowserPanel.Bookmarks -> ItemsDialog(
                title = "Закладки",
                items = bookmarks,
                emptyMessage = "Закладок пока нет",
                onOpen = { navigateTo(it.url); panel = null },
                onDelete = { item -> bookmarks.remove(item); store.saveBookmarks(bookmarks) },
                onDismiss = { panel = null }
            )
            BrowserPanel.History -> HistoryDialog(
                items = history,
                onOpen = { navigateTo(it.url); panel = null },
                onClear = {
                    history.clear()
                    store.clearHistory()
                    webViews.values.forEach { it.clearHistory() }
                },
                onDismiss = { panel = null }
            )
            BrowserPanel.Downloads -> DownloadsDialog(
                items = downloads,
                onRefresh = ::loadDownloadedItems,
                onOpen = ::openDownload,
                onDismiss = { panel = null }
            )
            BrowserPanel.Settings -> SettingsDialog(
                preferences = preferences,
                downloadDirectory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.absolutePath
                    ?: "Папка приложения",
                onPreferencesChange = {
                    preferences = it
                    store.savePreferences(it)
                },
                onClearHistory = {
                    history.clear()
                    store.clearHistory()
                    webViews.values.forEach { it.clearHistory() }
                },
                onClearSiteData = {
                    CookieManager.getInstance().removeAllCookies(null)
                    CookieManager.getInstance().flush()
                    WebStorage.getInstance().deleteAllData()
                    webViews.values.forEach { it.clearCache(true); it.clearHistory() }
                },
                onDismiss = { panel = null }
            )
        }
    }
}

private fun newTabId(): Long = System.nanoTime().takeIf { it > 0 } ?: AtomicLong().incrementAndGet()

private fun updateTab(tabs: MutableList<BrowserTab>, id: Long, url: String, title: String) {
    val index = tabs.indexOfFirst { it.id == id }
    if (index >= 0) tabs[index] = tabs[index].copy(url = url, title = title.ifBlank { url })
}

private fun displayName(context: Context, uri: Uri): String {
    if (uri.scheme == "file") return uri.lastPathSegment ?: "HTML-файл"
    return runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment ?: "HTML-файл"
}

private fun createBrowserWebView(
    context: Context,
    tabId: Long,
    onLocation: (Long, String) -> Unit,
    onTitle: (Long, String) -> Unit,
    onPageFinished: (Long, String, String) -> Unit,
    onLoading: (Boolean, Int) -> Unit,
    onOffline: (Long) -> Unit,
    onOpenInNewTab: (String) -> Unit,
    onDownload: (String, String?, String?, String?) -> Unit
): WebView = WebView(context).apply {
    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    isFocusable = true
    isFocusableInTouchMode = true
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = true
    settings.databaseEnabled = true
    settings.javaScriptCanOpenWindowsAutomatically = false
    settings.setSupportMultipleWindows(false)
    settings.allowFileAccess = false
    settings.allowContentAccess = true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) settings.safeBrowsingEnabled = true
    val assetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
        .build()
    CookieManager.getInstance().setAcceptCookie(true)
    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
    webChromeClient = object : WebChromeClient() {
        override fun onReceivedTitle(view: WebView, title: String?) {
            onTitle(tabId, title.orEmpty())
        }

        override fun onProgressChanged(view: WebView, newProgress: Int) {
            onLoading(newProgress < 100, newProgress)
        }
    }
    webViewClient = object : WebViewClient() {
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest) =
            assetLoader.shouldInterceptRequest(request.url)

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val url = request.url.toString()
            if (request.isForMainFrame && url.startsWith("about:", true)) return false
            val scheme = request.url.scheme?.lowercase(Locale.ROOT)
            if (scheme == "http" || scheme == "https" || scheme == "file" || scheme == "content") return false
            if (scheme != null) {
                runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, request.url)) }
                    .onFailure { Toast.makeText(context, "Нет приложения для этой ссылки", Toast.LENGTH_SHORT).show() }
                return true
            }
            return false
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            onLoading(true, 0)
            if (!url.startsWith(DINO_ASSET_URL)) onLocation(tabId, url)
        }

        override fun onPageFinished(view: WebView, url: String) {
            onPageFinished(tabId, view.title.orEmpty(), url)
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            super.onReceivedError(view, request, error)
            if (!request.isForMainFrame) return
            val validatedInternet = hasValidatedInternet(context)
            Log.w(LOG_TAG, "Main-frame WebView error ${error.errorCode}; validated internet: $validatedInternet")
            val networkErrors = setOf(
                ERROR_HOST_LOOKUP,
                ERROR_CONNECT,
                ERROR_TIMEOUT,
                ERROR_IO
            )
            if (error.errorCode in networkErrors && !validatedInternet) {
                onOffline(tabId)
                view.stopLoading()
                view.loadUrl(DINO_ASSET_URL)
            }
        }
    }
    setDownloadListener(DownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
        onDownload(url, userAgent, contentDisposition, mimeType)
    })
    setOnLongClickListener {
        val result = hitTestResult
        val link = result.extra
        if (link != null &&
            (result.type == WebView.HitTestResult.ANCHOR_TYPE ||
                result.type == WebView.HitTestResult.SRC_ANCHOR_TYPE)
        ) {
            onOpenInNewTab(link)
            true
        } else {
            false
        }
    }
}

private fun hasValidatedInternet(context: Context): Boolean {
    val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
    val network = manager.activeNetwork ?: return false
    val capabilities = manager.getNetworkCapabilities(network) ?: return false
    return capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
        capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
}

@Composable
private fun StartPage(
    shortcuts: List<BrowserItem>,
    history: List<BrowserItem>,
    onNavigate: (String) -> Unit,
    onAddSite: () -> Unit
) {
    var query by remember { mutableStateOf("") }
    BoxWithConstraints(
        Modifier.fillMaxSize().background(
            androidx.compose.ui.graphics.Brush.linearGradient(
                listOf(Color(0xFF1A2B57), Color(0xFF3D477C), Color(0xFF6B4A78))
            )
        )
    ) {
        val columns = if (maxWidth > 600.dp) 4 else 3
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item { Spacer(Modifier.height(if (maxHeight > 700.dp) 64.dp else 24.dp)) }
            item {
                Text("◈  Delta", color = Color.White, fontSize = 38.sp)
                Spacer(Modifier.height(6.dp))
                Text("Весь интернет — в одном месте", color = Color.White.copy(alpha = 0.75f))
            }
            item {
                Row(
                    Modifier.fillMaxWidth().background(Color.White, RoundedCornerShape(18.dp)).padding(start = 16.dp, end = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        modifier = Modifier.weight(1f).padding(vertical = 16.dp),
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = Color(0xFF202638)),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = { onNavigate(query) }),
                        decorationBox = { inner ->
                            Box {
                                if (query.isEmpty()) Text("Поиск в интернете или адрес сайта", color = Color.Gray)
                                inner()
                            }
                        }
                    )
                    IconButton(onClick = { onNavigate(query) }) { Icon(Icons.Default.Search, "Искать", tint = Color(0xFF4361EE)) }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Быстрые ссылки", color = Color.White, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    TextButton(onClick = onAddSite) { Text("Добавить", color = Color.White) }
                }
            }
            items(shortcuts.chunked(columns)) { rowItems ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    rowItems.forEach { item ->
                        Card(
                            modifier = Modifier.weight(1f).clickable { onNavigate(item.url) },
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.11f)),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Column(
                                Modifier.fillMaxWidth().padding(vertical = 15.dp, horizontal = 5.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Box(Modifier.size(42.dp).background(Color.White.copy(alpha = 0.17f), RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
                                    Text(item.title.take(1).uppercase(), color = Color.White, fontSize = 20.sp)
                                }
                                Spacer(Modifier.height(8.dp))
                                Text(item.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 12.sp)
                            }
                        }
                    }
                    repeat(columns - rowItems.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            if (history.isNotEmpty()) {
                item { Text("Недавно посещённые", Modifier.fillMaxWidth(), color = Color.White, fontSize = 17.sp) }
                items(history.take(5)) { item ->
                    Column(
                        Modifier.fillMaxWidth().clickable { onNavigate(item.url) }.padding(vertical = 5.dp)
                    ) {
                        Text(item.title, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(item.url, color = Color.White.copy(alpha = 0.65f), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            item { Spacer(Modifier.height(20.dp)) }
        }
    }
}

@Composable
private fun TabsDialog(
    tabs: List<BrowserTab>,
    selectedId: Long,
    onSelect: (Long) -> Unit,
    onClose: (Long) -> Unit,
    onNew: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Вкладки (${tabs.size})") },
        text = {
            Column(Modifier.fillMaxWidth()) {
                tabs.forEach { tab ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onSelect(tab.id) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(if (tab.id == selectedId) "● " else "○ ", color = MaterialTheme.colorScheme.primary)
                        Text(tab.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        IconButton(onClick = { onClose(tab.id) }) { Icon(Icons.Default.Close, "Закрыть") }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onNew) { Text("Новая вкладка") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Готово") } }
    )
}

@Composable
private fun ItemsDialog(
    title: String,
    items: List<BrowserItem>,
    emptyMessage: String,
    onOpen: (BrowserItem) -> Unit,
    onDelete: (BrowserItem) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            if (items.isEmpty()) Text(emptyMessage)
            else LazyColumn(Modifier.fillMaxWidth().height(360.dp)) {
                items(items) { item ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).clickable { onOpen(item) }.padding(vertical = 9.dp)) {
                            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(item.url, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        IconButton(onClick = { onDelete(item) }) { Icon(Icons.Default.Close, "Удалить") }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Закрыть") } }
    )
}

@Composable
private fun HistoryDialog(
    items: List<BrowserItem>,
    onOpen: (BrowserItem) -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit
) {
    var query by remember { mutableStateOf("") }
    val filtered = items.filter {
        query.isBlank() || it.title.contains(query, true) || it.url.contains(query, true)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("История") },
        text = {
            Column {
                OutlinedTextField(query, { query = it }, label = { Text("Поиск по истории") }, singleLine = true)
                Spacer(Modifier.height(8.dp))
                if (filtered.isEmpty()) Text("История пуста")
                else LazyColumn(Modifier.fillMaxWidth().height(300.dp)) {
                    items(filtered) { item ->
                        Column(Modifier.fillMaxWidth().clickable { onOpen(item) }.padding(vertical = 8.dp)) {
                            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(item.url, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Закрыть") } },
        dismissButton = { TextButton(onClick = onClear) { Text("Очистить") } }
    )
}

@Composable
private fun DownloadsDialog(
    items: List<DownloadItem>,
    onRefresh: () -> Unit,
    onOpen: (DownloadItem) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Загрузки") },
        text = {
            if (items.isEmpty()) Text("Загрузок пока нет")
            else LazyColumn(Modifier.fillMaxWidth().height(320.dp)) {
                items(items) { item ->
                    Column(Modifier.fillMaxWidth().clickable(enabled = item.uri != null) { onOpen(item) }.padding(vertical = 9.dp)) {
                        Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val status = when (item.status) {
                            DownloadManager.STATUS_SUCCESSFUL -> "Загружено · нажмите, чтобы открыть"
                            DownloadManager.STATUS_RUNNING -> if (item.totalBytes > 0) {
                                "Загружается: ${item.progress}%"
                            } else {
                                "Загружается…"
                            }
                            DownloadManager.STATUS_FAILED -> "Ошибка загрузки"
                            else -> "Ожидание"
                        }
                        Text(status, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onRefresh() }) { Text("Обновить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Закрыть") } }
    )
}

@Composable
private fun SettingsDialog(
    preferences: BrowserPreferences,
    downloadDirectory: String,
    onPreferencesChange: (BrowserPreferences) -> Unit,
    onClearHistory: () -> Unit,
    onClearSiteData: () -> Unit,
    onDismiss: () -> Unit
) {
    var homepage by remember(preferences.homepage) { mutableStateOf(preferences.homepage) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Настройки Delta") },
        text = {
            LazyColumn(Modifier.fillMaxWidth().height(430.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    Text("Основные", color = MaterialTheme.colorScheme.primary)
                    OutlinedTextField(homepage, { homepage = it }, label = { Text("Домашняя страница") }, singleLine = true)
                    TextButton(onClick = {
                        val normalized = BrowserUrlResolver.resolve(homepage, preferences.searchEngine)
                        onPreferencesChange(preferences.copy(homepage = normalized))
                    }) { Text("Сохранить домашнюю страницу") }
                }
                item {
                    Text("Поисковая система")
                    ChoiceRow("Google", preferences.searchEngine == "Google") {
                        onPreferencesChange(preferences.copy(searchEngine = "Google"))
                    }
                    ChoiceRow("Bing", preferences.searchEngine == "Bing") {
                        onPreferencesChange(preferences.copy(searchEngine = "Bing"))
                    }
                    ChoiceRow("DuckDuckGo", preferences.searchEngine == "DuckDuckGo") {
                        onPreferencesChange(preferences.copy(searchEngine = "DuckDuckGo"))
                    }
                }
                item {
                    Text("Новая вкладка")
                    ChoiceRow("Стартовая Delta", preferences.newTabMode == "home") {
                        onPreferencesChange(preferences.copy(newTabMode = "home"))
                    }
                    ChoiceRow("Пустая about:blank", preferences.newTabMode == "about") {
                        onPreferencesChange(preferences.copy(newTabMode = "about"))
                    }
                }
                item {
                    Text("При запуске")
                    ChoiceRow("Восстановить вкладки", preferences.startupMode == "restore") {
                        onPreferencesChange(preferences.copy(startupMode = "restore"))
                    }
                    ChoiceRow("Новая стартовая страница", preferences.startupMode == "home") {
                        onPreferencesChange(preferences.copy(startupMode = "home"))
                    }
                }
                item {
                    Text("Тема")
                    ChoiceRow("Системная", preferences.theme == "System") {
                        onPreferencesChange(preferences.copy(theme = "System"))
                    }
                    ChoiceRow("Светлая", preferences.theme == "Light") {
                        onPreferencesChange(preferences.copy(theme = "Light"))
                    }
                    ChoiceRow("Тёмная", preferences.theme == "Dark") {
                        onPreferencesChange(preferences.copy(theme = "Dark"))
                    }
                }
                item {
                    Text("Загрузки", color = MaterialTheme.colorScheme.primary)
                    Text(downloadDirectory, fontSize = 12.sp)
                }
                item {
                    Text("Приватность", color = MaterialTheme.colorScheme.primary)
                    TextButton(onClick = onClearHistory) { Text("Очистить историю") }
                    TextButton(onClick = onClearSiteData) { Text("Очистить cookies, кэш и данные сайтов") }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Готово") } }
    )
}

@Composable
private fun ChoiceRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(if (selected) "●" else "○", color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(end = 10.dp))
        Text(label)
    }
}
