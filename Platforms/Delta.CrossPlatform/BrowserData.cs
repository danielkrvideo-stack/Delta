using System.Text.Json;
using System.Diagnostics;

namespace Delta.CrossPlatform;

internal sealed class BrowserItem
{
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";
    public DateTimeOffset Date { get; set; } = DateTimeOffset.Now;
}

internal sealed class BrowserPreferences
{
    public string Homepage { get; set; } = "https://www.google.com";
    public string SearchEngine { get; set; } = "Google";
    public string NewTabMode { get; set; } = "home";
    public string StartupMode { get; set; } = "restore";
    public string Theme { get; set; } = "System";
    public double Zoom { get; set; } = 1.0;
    public string DownloadFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
}

internal sealed class BrowserData
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    public static BrowserData Shared { get; } = new();
    private readonly string _dataDirectory;
    private readonly string _statePath;

    public BrowserPreferences Preferences { get; private set; } = new();
    public List<BrowserItem> Bookmarks { get; private set; } = [];
    public List<BrowserItem> History { get; private set; } = [];
    public List<string> OpenTabs { get; set; } = [];
    public string UserDataDirectory { get; }
    public string DownloadsDirectory => Preferences.DownloadFolder;
    public string DinoFile => Path.Combine(AppContext.BaseDirectory, "dino.html");

    public BrowserData()
    {
        _dataDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Delta");
        UserDataDirectory = Path.Combine(_dataDirectory, "WebView2");
        _statePath = Path.Combine(_dataDirectory, "browser-state.json");
        Directory.CreateDirectory(_dataDirectory);
        Load();
    }

    public void AddHistory(string title, string url)
    {
        if (string.IsNullOrWhiteSpace(url) || url.StartsWith("about:", StringComparison.OrdinalIgnoreCase) ||
            url.StartsWith("file:", StringComparison.OrdinalIgnoreCase) ||
            url.StartsWith("delta:", StringComparison.OrdinalIgnoreCase))
            return;

        History.Insert(0, new BrowserItem { Title = string.IsNullOrWhiteSpace(title) ? url : title, Url = url });
        if (History.Count > 5000) History.RemoveRange(5000, History.Count - 5000);
        Save();
    }

    public void Save()
    {
        Directory.CreateDirectory(_dataDirectory);
        File.WriteAllText(_statePath, JsonSerializer.Serialize(new State
        {
            Preferences = Preferences,
            Bookmarks = Bookmarks,
            History = History,
            OpenTabs = OpenTabs
        }, JsonOptions));
    }

    private void Load()
    {
        try
        {
            if (File.Exists(_statePath))
            {
                var state = JsonSerializer.Deserialize<State>(File.ReadAllText(_statePath));
                if (state is not null)
                {
                    Preferences = state.Preferences ?? new BrowserPreferences();
                    Bookmarks = state.Bookmarks ?? [];
                    History = state.History ?? [];
                    OpenTabs = state.OpenTabs ?? [];
                }
            }
        }
        catch (JsonException ex)
        {
            Trace.TraceError("Delta browser state is invalid: {0}", ex);
        }

        if (Bookmarks.Count == 0)
        {
            Bookmarks =
            [
                new() { Title = "Google", Url = "https://www.google.com" },
                new() { Title = "YouTube", Url = "https://www.youtube.com" },
                new() { Title = "Wikipedia", Url = "https://www.wikipedia.org" },
                new() { Title = "GitHub", Url = "https://github.com" },
                new() { Title = "Roblox", Url = "https://www.roblox.com" }
            ];
        }
        Directory.CreateDirectory(Preferences.DownloadFolder);
    }

    private sealed class State
    {
        public BrowserPreferences? Preferences { get; set; }
        public List<BrowserItem>? Bookmarks { get; set; }
        public List<BrowserItem>? History { get; set; }
        public List<string>? OpenTabs { get; set; }
    }
}