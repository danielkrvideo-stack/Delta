using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System.Diagnostics;
using System.Net;

namespace Delta.CrossPlatform;

internal sealed class BrowserWindow : Form
{
    private static readonly Color Accent = Color.FromArgb(67, 97, 238);
    private static readonly object EnvironmentLock = new();
    private static Task<CoreWebView2Environment>? SharedEnvironmentTask;
    private static readonly List<BrowserWindow> OpenWindows = [];
    private readonly BrowserData _data = BrowserData.Shared;
    private readonly TabControl _tabs = new() { Dock = DockStyle.Fill, Padding = new Point(12, 5) };
    private readonly TextBox _address = new() { Dock = DockStyle.Fill, BorderStyle = BorderStyle.FixedSingle };
    private readonly ToolStripStatusLabel _status = new() { Spring = true, TextAlign = ContentAlignment.MiddleLeft };
    private readonly ToolStripStatusLabel _downloadStatus = new() { TextAlign = ContentAlignment.MiddleRight };
    private readonly Dictionary<TabPage, WebView2> _views = [];
    private readonly Dictionary<CoreWebView2DownloadOperation, string> _activeDownloads = [];
    private readonly List<string> _closedTabs = [];
    private bool _restoring;

    public BrowserWindow(string? openFile, bool restoreSession = true, bool smokeTest = false)
    {
        Text = "Delta";
        MinimumSize = new Size(920, 620);
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;
        BackColor = Color.FromArgb(248, 249, 252);
        BuildChrome();
        ApplyTheme();
        _tabs.SelectedIndexChanged += (_, _) => SyncAddress();
        KeyDown += HandleShortcut;
        FormClosing += (_, _) => SaveOpenTabs();
        FormClosed += (_, _) => OpenWindows.Remove(this);
        OpenWindows.Add(this);
        Shown += async (_, _) =>
        {
            await RestoreOrOpen(openFile, restoreSession);
            if (smokeTest) await RunSmokeTestAsync();
        };
    }

    private void BuildChrome()
    {
        var navigation = new TableLayoutPanel
        {
            Dock = DockStyle.Top, Height = 54, ColumnCount = 10,
            Padding = new Padding(12, 8, 12, 8), BackColor = Color.White
        };
        for (var i = 0; i < 4; i++) navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 36));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (var i = 0; i < 4; i++) navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 42));
        AddButton(navigation, "←", "Назад", 0, (_, _) =>
        {
            if (SelectedView?.CoreWebView2?.CanGoBack == true) SelectedView.GoBack();
        });
        AddButton(navigation, "→", "Вперёд", 1, (_, _) =>
        {
            if (SelectedView?.CoreWebView2?.CanGoForward == true) SelectedView.GoForward();
        });
        AddButton(navigation, "⟳", "Обновить", 2, (_, _) => SelectedView?.CoreWebView2?.Reload());
        AddButton(navigation, "⌂", "Домой", 3, (_, _) => Navigate(_data.Preferences.Homepage));
        _address.Margin = new Padding(4, 3, 5, 3);
        _address.Font = new Font("Segoe UI", 10);
        _address.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter) { Navigate(_address.Text); e.SuppressKeyPress = true; }
        };
        _address.GotFocus += (_, _) => _address.SelectAll();
        navigation.Controls.Add(_address, 4, 0);
        AddButton(navigation, "☆", "Закладки", 5, (_, _) => ShowItems("Закладки", _data.Bookmarks, true));
        AddButton(navigation, "◷", "История", 6, (_, _) => ShowItems("История", _data.History, false));
        AddButton(navigation, "⇩", "Загрузки", 7, (_, _) => OpenDownloads());
        AddButton(navigation, "⚙", "Настройки", 8, (_, _) => ShowSettings());
        AddButton(navigation, "+", "Новая вкладка", 9, (_, _) => NewTab());

        var status = new StatusStrip { Dock = DockStyle.Bottom, SizingGrip = false, BackColor = Color.White };
        status.Items.Add(_status);
        status.Items.Add(_downloadStatus);
        var menu = new MenuStrip { Dock = DockStyle.Top, BackColor = Color.White };
        var fileMenu = new ToolStripMenuItem("Файл");
        fileMenu.DropDownItems.Add(new ToolStripMenuItem("Открыть HTML-файл…", null, (_, _) => OpenHtmlFile()));
        fileMenu.DropDownItems.Add(new ToolStripMenuItem("Новое окно", null, (_, _) => new BrowserWindow(null, false).Show()));
        fileMenu.DropDownItems.Add(new ToolStripMenuItem("Выход", null, (_, _) => Close()));
        menu.Items.Add(fileMenu);
        var browserMenu = new ToolStripMenuItem("Delta");
        browserMenu.DropDownItems.Add(new ToolStripMenuItem("Добавить страницу в закладки", null, (_, _) => AddBookmark()));
        browserMenu.DropDownItems.Add(new ToolStripMenuItem("Повторно открыть закрытую вкладку", null, (_, _) => ReopenTab()));
        menu.Items.Add(browserMenu);
        Controls.Add(_tabs);
        Controls.Add(status);
        Controls.Add(navigation);
        Controls.Add(menu);
        MainMenuStrip = menu;
    }

    private void AddButton(TableLayoutPanel panel, string text, string tooltip, int column, EventHandler click)
    {
        var button = new Button
        {
            Text = text, Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, ForeColor = Accent,
            Font = new Font("Segoe UI", 12), Margin = new Padding(2), TabStop = false,
            AccessibleName = tooltip
        };
        button.FlatAppearance.BorderSize = 0;
        button.Click += click;
        new ToolTip().SetToolTip(button, tooltip);
        panel.Controls.Add(button, column, 0);
    }

    private WebView2? SelectedView => _tabs.SelectedTab is { } tab && _views.TryGetValue(tab, out var view) ? view : null;

    private async Task RestoreOrOpen(string? openFile, bool restoreSession)
    {
        if (openFile is "about" or "about:blank")
        {
            NewTab("about:blank");
            return;
        }
        if (!string.IsNullOrWhiteSpace(openFile) && File.Exists(openFile))
        {
            NewTab(new Uri(Path.GetFullPath(openFile)).AbsoluteUri);
            return;
        }
        if (!restoreSession)
        {
            NewTab();
            return;
        }
        var urls = _data.Preferences.StartupMode == "restore"
            ? _data.OpenTabs.Where(IsRestorable).Take(20).ToList()
            : [];
        if (urls.Count > 0)
        {
            _restoring = true;
            foreach (var url in urls) NewTab(url);
            _restoring = false;
        }
        else
        {
            var initial = _data.Preferences.StartupMode switch
            {
                "homepage" => _data.Preferences.Homepage,
                "about" => "about:blank",
                _ => null
            };
            NewTab(initial);
        }
        await Task.CompletedTask;
    }

    private async Task RunSmokeTestAsync()
    {
        try
        {
            var first = await WaitForCoreAsync(SelectedView, view => view.Source == "about:blank");
            if (_tabs.TabCount != 1) throw new InvalidOperationException("Initial blank tab was not created.");

            NewTab("about:blank");
            await WaitForCoreAsync(SelectedView, view => view.Source == "about:blank");
            if (_tabs.TabCount != 2) throw new InvalidOperationException("Creating a second tab failed.");
            CloseSelectedTab();
            if (_tabs.TabCount != 1) throw new InvalidOperationException("Closing a tab failed.");

            var gameUrl = new Uri(_data.DinoFile).AbsoluteUri;
            NewTab(gameUrl);
            var game = await WaitForCoreAsync(SelectedView,
                core => core.Source == gameUrl &&
                        core.DocumentTitle.Contains("Нет подключения к интернету", StringComparison.Ordinal));
            if (_tabs.TabCount != 2) throw new InvalidOperationException("Opening the local offline page failed.");

            _data.Save();
            var reloaded = new BrowserData();
            if (reloaded.Bookmarks.Count < 5 || !File.Exists(_data.DinoFile))
                throw new InvalidOperationException("Browser data or local Dino asset did not persist.");

            Console.WriteLine($"Delta Windows smoke test passed: {first.CoreWebView2.Source}, tabs, Dino ({game.CoreWebView2.DocumentTitle}), saved browser state.");
            Environment.ExitCode = 0;
        }
        catch (Exception ex)
        {
            Trace.TraceError("Delta Windows smoke test failed: {0}", ex);
            Console.Error.WriteLine($"Delta Windows smoke test failed: {ex}");
            Environment.ExitCode = 1;
        }
        finally
        {
            Close();
        }
    }

    private static async Task<WebView2> WaitForCoreAsync(WebView2? view, Func<CoreWebView2, bool> condition)
    {
        var deadline = DateTime.UtcNow.AddSeconds(20);
        while (DateTime.UtcNow < deadline)
        {
            if (view?.CoreWebView2 is { } core && condition(core)) return view;
            await Task.Delay(100);
        }
        throw new TimeoutException("Timed out waiting for the WebView2 page to load.");
    }

    private static bool IsRestorable(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        (uri.Scheme is "http" or "https" or "file" || url.StartsWith("about:", StringComparison.OrdinalIgnoreCase));

    private void NewTab(string? initialUrl = null)
    {
        var page = new TabPage("Новая вкладка") { Padding = Padding.Empty };
        var view = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.White };
        _views.Add(page, view);
        page.Controls.Add(view);
        _tabs.TabPages.Add(page);
        _tabs.SelectedTab = page;
        _ = InitializeView(page, view, initialUrl);
        if (!_restoring) SaveOpenTabs();
    }

    private async Task InitializeView(TabPage page, WebView2 view, string? initialUrl)
    {
        try
        {
            var environment = await GetBrowserEnvironmentAsync();
            await view.EnsureCoreWebView2Async(environment);
            var core = view.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = true;
            core.Settings.AreDevToolsEnabled = true;
            core.Settings.IsStatusBarEnabled = false;
            view.ZoomFactor = _data.Preferences.Zoom;
            core.DocumentTitleChanged += (_, _) => UpdateTabTitle(page, core.DocumentTitle);
            core.SourceChanged += (_, _) => { if (_tabs.SelectedTab == page) _address.Text = DisplayAddress(core.Source); };
            core.NavigationStarting += (_, _) => { if (_tabs.SelectedTab == page) _status.Text = "Загрузка…"; };
            core.NavigationCompleted += (_, e) =>
            {
                if (_tabs.SelectedTab == page) _status.Text = e.IsSuccess ? "Готово" : "Не удалось загрузить страницу";
                if (e.IsSuccess && Uri.TryCreate(core.Source, UriKind.Absolute, out var uri) && uri.Scheme is "http" or "https")
                    _data.AddHistory(core.DocumentTitle, core.Source);
                else if (!e.IsSuccess && IsNetworkFailure(e.WebErrorStatus.ToString()))
                    ShowOfflinePage(page, view);
            };
            core.NewWindowRequested += (_, e) => { e.Handled = true; NewTab(e.Uri); };
            core.DownloadStarting += (_, e) => ConfigureDownload(e);
            core.ProcessFailed += (_, _) =>
            {
                if (File.Exists(_data.DinoFile)) core.Navigate(new Uri(_data.DinoFile).AbsoluteUri);
                else _status.Text = "WebView2 завершил работу; обновите вкладку.";
            };
            if (initialUrl is not null) NavigateIn(view, initialUrl);
            else if (_data.Preferences.NewTabMode == "about") NavigateIn(view, "about:blank");
            else LoadStartPage(view);
        }
        catch (Exception ex)
        {
            _status.Text = "WebView2 недоступен";
            MessageBox.Show(this,
                $"Не удалось запустить WebView2. Установите Microsoft Edge WebView2 Runtime:\nhttps://developer.microsoft.com/microsoft-edge/webview2/\n\n{ex.Message}",
                "Delta", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private Task<CoreWebView2Environment> GetBrowserEnvironmentAsync()
    {
        lock (EnvironmentLock)
        {
            SharedEnvironmentTask ??= CoreWebView2Environment.CreateAsync(
                userDataFolder: _data.UserDataDirectory);
            return SharedEnvironmentTask;
        }
    }

    private static bool IsNetworkFailure(string status) =>
        status is "Disconnected" or "InternetDisconnected";

    private void ShowOfflinePage(TabPage page, WebView2 view)
    {
        if (!File.Exists(_data.DinoFile))
        {
            _status.Text = "Сетевая ошибка; офлайн-игра не найдена в приложении.";
            return;
        }
        page.Text = "Офлайн";
        _address.Text = "";
        view.CoreWebView2?.Navigate(new Uri(_data.DinoFile).AbsoluteUri);
    }

    private void ConfigureDownload(CoreWebView2DownloadStartingEventArgs e)
    {
        Directory.CreateDirectory(_data.DownloadsDirectory);
        var operation = e.DownloadOperation;
        var fileName = Path.GetFileName(operation.ResultFilePath);
        if (string.IsNullOrWhiteSpace(fileName)) fileName = "download";
        var destination = Path.Combine(_data.DownloadsDirectory, fileName);
        var suffix = 1;
        while (File.Exists(destination))
        {
            destination = Path.Combine(
                _data.DownloadsDirectory,
                $"{Path.GetFileNameWithoutExtension(fileName)} ({suffix++}){Path.GetExtension(fileName)}");
        }
        e.ResultFilePath = destination;
        _activeDownloads[operation] = fileName;
        operation.BytesReceivedChanged += (_, _) => UpdateDownloadStatus(operation);
        operation.StateChanged += (_, _) =>
        {
            UpdateDownloadStatus(operation);
            if (operation.State is CoreWebView2DownloadState.Completed or CoreWebView2DownloadState.Interrupted)
            {
                _activeDownloads.Remove(operation);
                _status.Text = operation.State == CoreWebView2DownloadState.Completed
                    ? $"Загрузка завершена: {fileName}" : $"Загрузка прервана: {fileName}";
            }
        };
        UpdateDownloadStatus(operation);
    }

    private void UpdateDownloadStatus(CoreWebView2DownloadOperation operation)
    {
        if (InvokeRequired) { BeginInvoke(new Action(() => UpdateDownloadStatus(operation))); return; }
        var total = operation.TotalBytesToReceive;
        var progress = total is > 0
            ? Math.Clamp((int)(operation.BytesReceived * 100d / total.Value), 0, 100)
            : 0;
        _downloadStatus.Text = _activeDownloads.TryGetValue(operation, out var name)
            ? $"{name} — {(total is > 0 ? $"{progress}%" : $"{operation.BytesReceived / 1024} КБ")}" : "";
    }

    private void Navigate(string input)
    {
        if (SelectedView is { } view) NavigateIn(view, input);
    }

    private void NavigateIn(WebView2 view, string input)
    {
        var text = input.Trim();
        if (text.Length == 0) return;
        if (text.Equals("about", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("about:blank", StringComparison.OrdinalIgnoreCase))
        {
            view.CoreWebView2?.Navigate("about:blank");
            return;
        }
        if (Uri.TryCreate(text, UriKind.Absolute, out var parsed) && parsed.IsFile)
        {
            view.CoreWebView2?.Navigate(parsed.AbsoluteUri);
            return;
        }
        if (text.Contains("://", StringComparison.Ordinal))
        {
            if (Uri.TryCreate(text, UriKind.Absolute, out parsed) && parsed.Scheme is "http" or "https")
                view.CoreWebView2?.Navigate(parsed.AbsoluteUri);
            else _status.Text = "Поддерживаются только HTTP, HTTPS и локальные файлы.";
            return;
        }
        if (!text.Any(char.IsWhiteSpace) && text.Contains('.') &&
            Uri.TryCreate("https://" + text, UriKind.Absolute, out parsed))
        {
            view.CoreWebView2?.Navigate(parsed.AbsoluteUri);
            return;
        }
        var searchBase = _data.Preferences.SearchEngine switch
        {
            "DuckDuckGo" => "https://duckduckgo.com/?q=",
            "Bing" => "https://www.bing.com/search?q=",
            _ => "https://www.google.com/search?q="
        };
        view.CoreWebView2?.Navigate(searchBase + Uri.EscapeDataString(text));
    }

    private void LoadStartPage(WebView2 view)
    {
        var links = string.Join("", _data.Bookmarks.Take(10).Select(item =>
        {
            var host = Uri.TryCreate(item.Url, UriKind.Absolute, out var uri) ? uri.Host : item.Url;
            return $"<a href=\"{WebUtility.HtmlEncode(item.Url)}\"><b>{WebUtility.HtmlEncode(item.Title)}</b><small>{WebUtility.HtmlEncode(host)}</small></a>";
        }));
        var searchBase = _data.Preferences.SearchEngine switch
        {
            "DuckDuckGo" => "https://duckduckgo.com/",
            "Bing" => "https://www.bing.com/search",
            _ => "https://www.google.com/search"
        };
        view.NavigateToString($$"""
            <!doctype html><meta charset="utf-8"><style>
            *{box-sizing:border-box}body{margin:0;background:linear-gradient(145deg,#f6f8ff,#eaf0ff);
            color:#202538;font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;min-height:100vh;
            display:grid;place-items:center}.card{text-align:center;max-width:760px;padding:32px}.logo{font-size:58px;font-weight:750;
            letter-spacing:-4px;color:#4361ee}.tag{color:#69738c;margin:8px 0 32px}
            .links{display:flex;flex-wrap:wrap;justify-content:center;gap:12px;margin-top:24px}
            form{display:flex;gap:8px;max-width:560px;margin:0 auto 20px}
            input{flex:1;min-width:180px;padding:13px 16px;border:1px solid #dfe5f5;border-radius:12px;font:inherit}
            button{padding:0 18px;border:0;border-radius:12px;background:#4361ee;color:#fff;font:inherit}
            a{display:flex;flex-direction:column;gap:6px;min-width:120px;padding:14px;background:#fff;
            border:1px solid #e0e6f4;border-radius:12px;color:#283044;text-decoration:none}
            a:hover{border-color:#4361ee}small{color:#77819a}
            </style><main class=card><div class=logo>Delta</div><div class=tag>Твой браузер. Твоя сеть.</div>
            <form action="{{WebUtility.HtmlEncode(searchBase)}}" method="get"><input name="q" autofocus placeholder="Поиск в интернете"><button>Найти</button></form>
            <nav class=links>{{links}}</nav></main>
            """);
    }

    private void UpdateTabTitle(TabPage page, string title)
    {
        if (!page.IsDisposed) page.Text = string.IsNullOrWhiteSpace(title) ? "Новая вкладка" : title[..Math.Min(24, title.Length)];
    }

    private void SyncAddress() =>
        _address.Text = SelectedView?.CoreWebView2?.Source is { } source ? DisplayAddress(source) : "";

    private static string DisplayAddress(string source) =>
        source.StartsWith("file:", StringComparison.OrdinalIgnoreCase) ? Uri.UnescapeDataString(source) : source;

    private void HandleShortcut(object? sender, KeyEventArgs e)
    {
        if (e.Control && e.KeyCode == Keys.T) { NewTab(); e.Handled = true; }
        else if (e.Control && e.KeyCode == Keys.W) { CloseSelectedTab(); e.Handled = true; }
        else if (e.Control && e.Shift && e.KeyCode == Keys.T) { ReopenTab(); e.Handled = true; }
        else if (e.Control && e.KeyCode == Keys.L) { _address.Focus(); _address.SelectAll(); e.Handled = true; }
        else if (e.Alt && e.KeyCode == Keys.Left) { SelectedView?.GoBack(); e.Handled = true; }
        else if (e.Alt && e.KeyCode == Keys.Right) { SelectedView?.GoForward(); e.Handled = true; }
    }

    private void CloseSelectedTab()
    {
        if (_tabs.SelectedTab is not { } page) return;
        if (_views.TryGetValue(page, out var view))
        {
            var current = view.CoreWebView2?.Source;
            if (current is not null && IsRestorable(current)) _closedTabs.Add(current);
            view.Dispose();
            _views.Remove(page);
        }
        _tabs.TabPages.Remove(page);
        page.Dispose();
        if (_tabs.TabCount == 0) NewTab();
        SaveOpenTabs();
    }

    private void ReopenTab()
    {
        if (_closedTabs.Count == 0) return;
        var url = _closedTabs[^1];
        _closedTabs.RemoveAt(_closedTabs.Count - 1);
        NewTab(url);
    }

    private void SaveOpenTabs()
    {
        if (_restoring) return;
        _data.OpenTabs = OpenWindows.SelectMany(window => window._views.Values)
            .Select(view => view.CoreWebView2?.Source ?? "")
            .Where(IsRestorable).Take(20).ToList();
        _data.Save();
    }

    private void AddBookmark()
    {
        var core = SelectedView?.CoreWebView2;
        if (core is null || !Uri.TryCreate(core.Source, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) return;
        if (_data.Bookmarks.Any(item => item.Url == core.Source)) return;
        _data.Bookmarks.Insert(0, new BrowserItem { Title = core.DocumentTitle, Url = core.Source });
        _data.Save();
        _status.Text = "Страница добавлена в закладки";
    }

    private void ShowItems(string title, List<BrowserItem> source, bool allowDelete)
    {
        using var dialog = new Form { Text = title, Size = new Size(680, 460), StartPosition = FormStartPosition.CenterParent };
        var list = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, HideSelection = false };
        list.Columns.Add("Название", 190);
        list.Columns.Add("Адрес", 360);
        list.Columns.Add("Дата", 100);
        void RefreshRows(string filter = "")
        {
            list.Items.Clear();
            foreach (var item in source.Where(item =>
                         string.IsNullOrWhiteSpace(filter) ||
                         item.Title.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                         item.Url.Contains(filter, StringComparison.OrdinalIgnoreCase)))
            {
                var row = new ListViewItem(item.Title);
                row.SubItems.Add(item.Url);
                row.SubItems.Add(item.Date.ToLocalTime().ToString("g"));
                row.Tag = item;
                list.Items.Add(row);
            }
        }
        RefreshRows();
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
        var open = new Button { Text = "Открыть", AutoSize = true };
        open.Click += (_, _) => { if (list.SelectedItems.Count > 0) { NewTab(((BrowserItem)list.SelectedItems[0].Tag!).Url); dialog.Close(); } };
        buttons.Controls.Add(open);
        if (allowDelete)
        {
            var remove = new Button { Text = "Удалить", AutoSize = true };
            remove.Click += (_, _) =>
            {
                if (list.SelectedItems.Count == 0) return;
                source.Remove((BrowserItem)list.SelectedItems[0].Tag!);
                RefreshRows();
                _data.Save();
            };
            buttons.Controls.Add(remove);
        }
        else
        {
            var search = new TextBox { Width = 190, PlaceholderText = "Поиск по истории" };
            search.TextChanged += (_, _) => RefreshRows(search.Text);
            buttons.Controls.Add(search);
            var clear = new Button { Text = "Очистить историю", AutoSize = true };
            clear.Click += (_, _) => { _data.History.Clear(); _data.Save(); list.Items.Clear(); };
            buttons.Controls.Add(clear);
        }
        list.DoubleClick += (_, _) => open.PerformClick();
        dialog.Controls.Add(list);
        dialog.Controls.Add(buttons);
        dialog.ShowDialog(this);
    }

    private void OpenDownloads()
    {
        Directory.CreateDirectory(_data.DownloadsDirectory);
        using var dialog = new Form
        {
            Text = "Загрузки",
            Size = new Size(660, 430),
            StartPosition = FormStartPosition.CenterParent
        };
        var files = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true };
        files.Columns.Add("Файл", 360);
        files.Columns.Add("Размер", 120);
        files.Columns.Add("Дата изменения", 150);
        void RefreshFiles()
        {
            files.Items.Clear();
            foreach (var path in Directory.EnumerateFiles(_data.DownloadsDirectory)
                         .OrderByDescending(File.GetLastWriteTimeUtc))
            {
                var info = new FileInfo(path);
                var row = new ListViewItem(info.Name) { Tag = path };
                row.SubItems.Add(info.Length >= 1024 * 1024
                    ? $"{info.Length / 1024d / 1024d:F1} МБ"
                    : $"{info.Length / 1024d:F0} КБ");
                row.SubItems.Add(info.LastWriteTime.ToString("g"));
                files.Items.Add(row);
            }
        }
        RefreshFiles();
        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 48,
            FlowDirection = FlowDirection.RightToLeft,
            Padding = new Padding(8)
        };
        var openFile = new Button { Text = "Открыть файл", AutoSize = true };
        openFile.Click += (_, _) =>
        {
            if (files.SelectedItems.Count == 0) return;
            Process.Start(new ProcessStartInfo((string)files.SelectedItems[0].Tag!) { UseShellExecute = true });
        };
        var openFolder = new Button { Text = "Открыть папку", AutoSize = true };
        openFolder.Click += (_, _) =>
            Process.Start(new ProcessStartInfo("explorer.exe", _data.DownloadsDirectory) { UseShellExecute = true });
        buttons.Controls.Add(openFile);
        buttons.Controls.Add(openFolder);
        files.DoubleClick += (_, _) => openFile.PerformClick();
        dialog.Controls.Add(files);
        dialog.Controls.Add(buttons);
        dialog.ShowDialog(this);
    }

    private void ShowSettings()
    {
        using var dialog = new SettingsDialog(_data, _views.Values.ToList());
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _data.Save();
            ApplyTheme();
            foreach (var view in _views.Values) view.ZoomFactor = _data.Preferences.Zoom;
        }
    }

    private void ApplyTheme()
    {
        var dark = _data.Preferences.Theme == "Dark" ||
                   (_data.Preferences.Theme == "System" && SystemInformation.HighContrast);
        BackColor = dark ? Color.FromArgb(31, 33, 40) : Color.FromArgb(248, 249, 252);
    }

    private void OpenHtmlFile()
    {
        using var dialog = new OpenFileDialog { Filter = "HTML files|*.html;*.htm;*.xhtml|All files|*.*", Title = "Открыть HTML-файл" };
        if (dialog.ShowDialog(this) == DialogResult.OK) NewTab(new Uri(dialog.FileName).AbsoluteUri);
    }
}

internal sealed class SettingsDialog : Form
{
    private readonly BrowserData _data;
    private readonly List<WebView2> _views;
    private readonly TextBox _homepage = new();
    private readonly ComboBox _search = new();
    private readonly ComboBox _newTab = new();
    private readonly ComboBox _startup = new();
    private readonly ComboBox _theme = new();
    private readonly NumericUpDown _zoom = new();
    private readonly TextBox _downloads = new();

    public SettingsDialog(BrowserData data, List<WebView2> views)
    {
        _data = data;
        _views = views;
        Text = "Настройки Delta";
        Size = new Size(560, 520);
        StartPosition = FormStartPosition.CenterParent;
        var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(12, 6) };
        tabs.TabPages.Add(CreateGeneralPage());
        tabs.TabPages.Add(CreateAppearancePage());
        tabs.TabPages.Add(CreatePrivacyPage());
        tabs.TabPages.Add(CreateDownloadsPage());
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10) };
        var save = new Button { Text = "Сохранить", DialogResult = DialogResult.OK, AutoSize = true };
        save.Click += (_, _) => SavePreferences();
        var cancel = new Button { Text = "Отмена", DialogResult = DialogResult.Cancel, AutoSize = true };
        buttons.Controls.Add(save);
        buttons.Controls.Add(cancel);
        Controls.Add(tabs);
        Controls.Add(buttons);
        AcceptButton = save;
        CancelButton = cancel;
    }

    private TabPage CreateGeneralPage()
    {
        var page = NewPage("Основные");
        _homepage.Text = _data.Preferences.Homepage;
        _search.Items.AddRange(["Google", "DuckDuckGo", "Bing"]);
        _search.SelectedItem = _data.Preferences.SearchEngine;
        _newTab.Items.AddRange(["Стартовая", "Пустая about"]);
        _newTab.SelectedIndex = _data.Preferences.NewTabMode == "about" ? 1 : 0;
        _startup.Items.AddRange(["Восстановить вкладки", "Стартовая", "Домашняя страница", "Пустая about"]);
        _startup.SelectedIndex = _data.Preferences.StartupMode switch { "home" => 1, "homepage" => 2, "about" => 3, _ => 0 };
        AddRow(page, "Домашняя страница", _homepage);
        AddRow(page, "Поисковая система", _search);
        AddRow(page, "Новая вкладка", _newTab);
        AddRow(page, "При запуске", _startup);
        return page;
    }

    private TabPage CreateAppearancePage()
    {
        var page = NewPage("Внешний вид");
        _theme.Items.AddRange(["System", "Light", "Dark"]);
        _theme.SelectedItem = _data.Preferences.Theme;
        _zoom.DecimalPlaces = 2;
        _zoom.Increment = 0.05M;
        _zoom.Minimum = 0.5M;
        _zoom.Maximum = 2.0M;
        _zoom.Value = (decimal)Math.Clamp(_data.Preferences.Zoom, 0.5, 2.0);
        AddRow(page, "Тема (System / Light / Dark)", _theme);
        AddRow(page, "Масштаб (50–200%)", _zoom);
        return page;
    }

    private TabPage CreatePrivacyPage()
    {
        var page = NewPage("Приватность");
        foreach (var (caption, kinds) in new[]
        {
            ("Очистить cookies", CoreWebView2BrowsingDataKinds.Cookies),
            ("Очистить кэш", CoreWebView2BrowsingDataKinds.DiskCache),
            ("Очистить данные сайтов", CoreWebView2BrowsingDataKinds.AllSite)
        })
        {
            var button = new Button { Text = caption, AutoSize = true, Margin = new Padding(4, 10, 4, 4) };
            button.Click += async (_, _) =>
            {
                foreach (var view in _views)
                    if (view.CoreWebView2 is { } core) await core.Profile.ClearBrowsingDataAsync(kinds);
                MessageBox.Show(this, "Данные сайта очищены.", "Delta", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };
            page.Controls.Add(button);
        }
        return page;
    }

    private TabPage CreateDownloadsPage()
    {
        var page = NewPage("Загрузки");
        _downloads.Text = _data.Preferences.DownloadFolder;
        var browse = new Button { Text = "Выбрать…", AutoSize = true };
        browse.Click += (_, _) =>
        {
            using var dialog = new FolderBrowserDialog { SelectedPath = _downloads.Text, ShowNewFolderButton = true };
            if (dialog.ShowDialog(this) == DialogResult.OK) _downloads.Text = dialog.SelectedPath;
        };
        AddRow(page, "Папка загрузок", _downloads, browse);
        var open = new Button { Text = "Открыть папку", AutoSize = true };
        open.Click += (_, _) => Process.Start(new ProcessStartInfo("explorer.exe", _downloads.Text) { UseShellExecute = true });
        page.Controls.Add(open);
        return page;
    }

    private static TabPage NewPage(string title) => new(title) { Padding = new Padding(16), AutoScroll = true };

    private static void AddRow(Control parent, string label, Control field, Control? extra = null)
    {
        var row = new TableLayoutPanel { Dock = DockStyle.Top, Height = 56, ColumnCount = extra is null ? 2 : 3 };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        if (extra is not null) row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        row.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        field.Dock = DockStyle.Fill;
        field.Margin = new Padding(4, 12, 4, 12);
        row.Controls.Add(field, 1, 0);
        if (extra is not null) row.Controls.Add(extra, 2, 0);
        parent.Controls.Add(row);
    }

    private void SavePreferences()
    {
        _data.Preferences.Homepage = string.IsNullOrWhiteSpace(_homepage.Text) ? "https://www.google.com" : _homepage.Text.Trim();
        _data.Preferences.SearchEngine = _search.SelectedItem?.ToString() ?? "Google";
        _data.Preferences.NewTabMode = _newTab.SelectedIndex == 1 ? "about" : "home";
        _data.Preferences.StartupMode = _startup.SelectedIndex switch { 1 => "home", 2 => "homepage", 3 => "about", _ => "restore" };
        _data.Preferences.Theme = _theme.SelectedItem?.ToString() ?? "System";
        _data.Preferences.Zoom = (double)_zoom.Value;
        if (!string.IsNullOrWhiteSpace(_downloads.Text)) _data.Preferences.DownloadFolder = _downloads.Text;
        Directory.CreateDirectory(_data.Preferences.DownloadFolder);
    }
}