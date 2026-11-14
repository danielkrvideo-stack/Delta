#!/usr/bin/env python3
import json
import html
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import gi
gi.require_version("Gtk", "3.0")
try:
    gi.require_version("WebKit2", "4.1")
except ValueError:
    gi.require_version("WebKit2", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2


APP_ID = "com.delta.browser"
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "delta"
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "delta"
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "delta"
STATE_PATH = CONFIG_HOME / "browser-state.json"
_SHARED_STATE = None
_SHARED_CONTEXT = None
_SHARED_DATA_MANAGER = None
_WINDOWS = []
_ACTIVE_WINDOW = None
DEFAULT_BOOKMARKS = [
    {"title": "Google", "url": "https://www.google.com"},
    {"title": "YouTube", "url": "https://www.youtube.com"},
    {"title": "Wikipedia", "url": "https://www.wikipedia.org"},
    {"title": "GitHub", "url": "https://github.com"},
    {"title": "Roblox", "url": "https://www.roblox.com"},
]


def load_state():
    global _SHARED_STATE
    if _SHARED_STATE is not None:
        return _SHARED_STATE
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError:
        state = {}
    except (OSError, json.JSONDecodeError) as error:
        print(f"Delta: cannot read browser state: {error}", file=sys.stderr)
        state = {}
    state.setdefault("preferences", {})
    prefs = state["preferences"]
    prefs.setdefault("homepage", "https://www.google.com")
    prefs.setdefault("searchEngine", "Google")
    prefs.setdefault("newTabMode", "home")
    prefs.setdefault("startupMode", "restore")
    prefs.setdefault("theme", "System")
    prefs.setdefault("zoom", 1.0)
    prefs.setdefault("downloadFolder", str(Path.home() / "Downloads"))
    state.setdefault("bookmarks", DEFAULT_BOOKMARKS.copy())
    state.setdefault("history", [])
    state.setdefault("openTabs", [])
    _SHARED_STATE = state
    return state


def route_download(context, download):
    if _ACTIVE_WINDOW is not None:
        _ACTIVE_WINDOW.on_download_started(context, download)


def save_state(state):
    CONFIG_HOME.mkdir(parents=True, exist_ok=True)
    temporary = STATE_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(STATE_PATH)


def start_page(bookmarks, search_engine):
    links = "".join(
        f'<a href="{html.escape(item["url"], quote=True)}"><b>{html.escape(item["title"])}</b>'
        f'<small>{html.escape(urlparse(item["url"]).netloc)}</small></a>'
        for item in bookmarks[:10]
    )
    search_base = {
        "DuckDuckGo": "https://duckduckgo.com/",
        "Bing": "https://www.bing.com/search",
    }.get(search_engine, "https://www.google.com/search")
    return f"""<!doctype html><meta charset="utf-8"><style>
    *{{box-sizing:border-box}}body{{margin:0;min-height:100vh;display:grid;place-items:center;
    background:linear-gradient(145deg,#f6f8ff,#eaf0ff);color:#202538;
    font:16px system-ui,sans-serif}}.card{{text-align:center}}.logo{{font-size:58px;font-weight:750;
    letter-spacing:-4px;color:#4361ee}}.tag{{color:#69738c;margin:8px 0 32px}}
    nav{{display:flex;flex-wrap:wrap;justify-content:center;gap:12px;margin-top:24px}}
    form{{display:flex;gap:8px;max-width:560px;margin:0 auto 20px}}
    input{{flex:1;min-width:180px;padding:13px 16px;border:1px solid #dfe5f5;border-radius:12px;font:inherit}}
    button{{padding:0 18px;border:0;border-radius:12px;background:#4361ee;color:#fff;font:inherit}}
    a{{display:flex;flex-direction:column;gap:6px;min-width:120px;padding:14px;background:#fff;
    border:1px solid #e0e6f4;border-radius:12px;color:#283044;text-decoration:none}}
    a:hover{{border-color:#4361ee}}small{{color:#77819a}}
    </style><main class=card><div class=logo>Delta</div><div class=tag>Твой браузер. Твоя сеть.</div>
    <form action="{html.escape(search_base, quote=True)}" method="get"><input name="q" autofocus placeholder="Поиск в интернете"><button>Найти</button></form>
    <nav>{links}</nav></main>"""


class DeltaWindow(Gtk.Window):
    def __init__(self, open_file=None, smoke_test=False):
        global _ACTIVE_WINDOW
        super().__init__(title="Delta")
        self.set_default_size(1120, 760)
        self.set_icon_name("delta")
        self.state = load_state()
        self.webviews = {}
        self.downloads = []
        self.closed_tabs = []
        self.context, self.data_manager = self.create_context()
        self._build_ui()
        self.apply_theme()
        self.connect("delete-event", self.on_close)
        self.connect("key-press-event", self.on_key_press)
        self.connect("focus-in-event", self.on_focus)
        self.smoke_test = smoke_test
        _WINDOWS.append(self)
        _ACTIVE_WINDOW = self
        self.show_all()
        self.restore(open_file)
        if smoke_test:
            GLib.timeout_add_seconds(2, self.run_smoke_test)

    def create_context(self):
        global _SHARED_CONTEXT, _SHARED_DATA_MANAGER
        DATA_HOME.mkdir(parents=True, exist_ok=True)
        CACHE_HOME.mkdir(parents=True, exist_ok=True)
        if _SHARED_CONTEXT is None:
            _SHARED_DATA_MANAGER = WebKit2.WebsiteDataManager(
                base_data_directory=str(DATA_HOME / "web-profile"),
                base_cache_directory=str(CACHE_HOME / "web-cache"),
            )
            _SHARED_CONTEXT = WebKit2.WebContext.new_with_website_data_manager(_SHARED_DATA_MANAGER)
            _SHARED_CONTEXT.connect("download-started", route_download)
        return _SHARED_CONTEXT, _SHARED_DATA_MANAGER

    def _build_ui(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(outer)
        menu = Gtk.MenuBar()
        file_item = Gtk.MenuItem(label="Файл")
        file_menu = Gtk.Menu()
        file_item.set_submenu(file_menu)
        self.menu_item(file_menu, "Открыть HTML-файл…", self.open_html)
        self.menu_item(file_menu, "Новое окно", lambda *_: DeltaWindow().show_all())
        self.menu_item(file_menu, "Выход", lambda *_: self.close())
        menu.append(file_item)
        delta_item = Gtk.MenuItem(label="Delta")
        delta_menu = Gtk.Menu()
        delta_item.set_submenu(delta_menu)
        self.menu_item(delta_menu, "Добавить в закладки", self.add_bookmark)
        self.menu_item(delta_menu, "Повторно открыть закрытую вкладку", self.reopen_tab)
        menu.append(delta_item)
        outer.pack_start(menu, False, False, 0)

        nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        nav.set_border_width(8)
        nav.get_style_context().add_class("toolbar")
        for glyph, label, action in [
            ("←", "Назад", lambda *_: self.current_view().go_back() if self.current_view().can_go_back() else None),
            ("→", "Вперёд", lambda *_: self.current_view().go_forward() if self.current_view().can_go_forward() else None),
            ("⟳", "Обновить", lambda *_: self.current_view().reload()),
            ("⌂", "Домой", lambda *_: self.navigate(self.state["preferences"]["homepage"])),
        ]:
            button = Gtk.Button(label=glyph)
            button.set_tooltip_text(label)
            button.connect("clicked", action)
            nav.pack_start(button, False, False, 0)
        self.address = Gtk.Entry()
        self.address.set_placeholder_text("Поиск или введите адрес")
        self.address.connect("activate", lambda entry: self.navigate(entry.get_text()))
        self.address.connect("focus-in-event", lambda *_: GLib.idle_add(self.address.select_region, 0, -1))
        nav.pack_start(self.address, True, True, 3)
        for glyph, label, action in [
            ("☆", "Закладки", lambda *_: self.show_items("Закладки", "bookmarks")),
            ("◷", "История", lambda *_: self.show_items("История", "history")),
            ("⇩", "Загрузки", self.open_downloads),
            ("⚙", "Настройки", self.show_settings),
            ("+", "Новая вкладка", lambda *_: self.new_tab()),
        ]:
            button = Gtk.Button(label=glyph)
            button.set_tooltip_text(label)
            button.connect("clicked", action)
            nav.pack_start(button, False, False, 0)
        outer.pack_start(nav, False, False, 0)
        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        self.notebook.connect("switch-page", self.on_switch_page)
        outer.pack_start(self.notebook, True, True, 0)
        self.status = Gtk.Label(label="Готово", xalign=0)
        self.download_status = Gtk.Label(label="", xalign=1)
        status = Gtk.Box(spacing=8)
        status.set_border_width(5)
        status.pack_start(self.status, True, True, 6)
        status.pack_end(self.download_status, False, False, 6)
        outer.pack_end(status, False, False, 0)

    @staticmethod
    def menu_item(menu, label, callback):
        item = Gtk.MenuItem(label=label)
        item.connect("activate", callback)
        menu.append(item)

    def restore(self, open_file):
        if open_file:
            if open_file.lower() in ("about", "about:blank"):
                self.new_tab("about:blank")
                return
            if open_file.startswith("file://"):
                open_file = unquote(urlparse(open_file).path)
            if Path(open_file).is_file():
                self.new_tab(Path(open_file).resolve().as_uri())
                return
            if open_file.startswith(("http://", "https://")):
                self.new_tab(open_file)
                return
        prefs = self.state["preferences"]
        urls = self.state["openTabs"][:20] if prefs["startupMode"] == "restore" else []
        urls = [url for url in urls if self.is_restorable(url)]
        if urls:
            for url in urls:
                self.new_tab(url, save=False)
        elif prefs["startupMode"] == "homepage":
            self.new_tab(prefs["homepage"])
        elif prefs["startupMode"] == "about":
            self.new_tab("about:blank")
        else:
            self.new_tab()
        self.save_tabs()

    def run_smoke_test(self):
        global _SMOKE_FAILURE
        try:
            if self.notebook.get_n_pages() != 1:
                raise RuntimeError(f"Expected one initial tab, found {self.notebook.get_n_pages()}")
            first = self.current_view()
            if first.get_uri() != "about:blank":
                raise RuntimeError(f"about:blank did not load: {first.get_uri()!r}")

            second = self.new_tab("about:blank", save=False)
            if self.notebook.get_n_pages() != 2 or second.get_uri() != "about:blank":
                raise RuntimeError("Creating or switching to a second about tab failed")
            self.close_tab(second)
            if self.notebook.get_n_pages() != 1:
                raise RuntimeError("Closing a tab failed")

            game = Path(__file__).resolve().parents[1] / "Shared" / "dino.html"
            if not game.is_file():
                raise RuntimeError("Bundled offline game is missing")
            game_uri = game.resolve().as_uri()
            print(f"Delta Linux smoke test: opening local game {game_uri}", flush=True)
            self.new_tab(game_uri, save=False)
            if self.notebook.get_n_pages() != 2:
                raise RuntimeError("Opening the local offline game tab failed")

            self.smoke_deadline = time.monotonic() + 30
            GLib.timeout_add_seconds(2, self.verify_smoke_game)
        except Exception as error:
            self.fail_smoke_test(error)
            self.destroy()
        return GLib.SOURCE_REMOVE

    def verify_smoke_game(self):
        try:
            game_view = self.current_view()
            title = game_view.get_title() or ""
            if "Нет подключения к интернету" not in title:
                if time.monotonic() < self.smoke_deadline:
                    return GLib.SOURCE_CONTINUE
                raise RuntimeError(
                    f"Local Dino page did not finish loading: title={title!r}, "
                    f"uri={game_view.get_uri()!r}, status={self.status.get_text()!r}"
                )
            self.state["preferences"]["theme"] = "Dark"
            save_state(self.state)
            saved = json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if saved["preferences"]["theme"] != "Dark" or not saved["bookmarks"]:
                raise RuntimeError("Browser settings or bookmarks did not persist")
            print("Delta Linux smoke test passed: about, tabs, local Dino page, persistent settings/bookmarks")
        except Exception as error:
            self.fail_smoke_test(error)
        self.destroy()
        return GLib.SOURCE_REMOVE

    def fail_smoke_test(self, error):
        global _SMOKE_FAILURE
        _SMOKE_FAILURE = str(error)
        print(f"Delta Linux smoke test failed: {error}", file=sys.stderr)

    @staticmethod
    def is_restorable(url):
        return url.startswith(("http://", "https://", "file://", "about:"))

    def new_tab(self, initial_url=None, save=True):
        webview = WebKit2.WebView.new_with_context(self.context)
        webview.set_zoom_level(float(self.state["preferences"]["zoom"]))
        webview.connect("load-changed", self.on_load_changed)
        webview.connect("load-failed", self.on_load_failed)
        webview.connect("notify::title", self.on_title_changed)
        webview.connect("notify::uri", self.on_uri_changed)
        webview.connect("create", self.on_create_view)
        webview.connect("decide-policy", self.on_decide_policy)
        tab_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        label = Gtk.Label(label="Новая вкладка")
        close = Gtk.Button(label="×")
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.set_focus_on_click(False)
        close.connect("clicked", lambda *_: self.close_tab(webview))
        tab_box.pack_start(label, True, True, 3)
        tab_box.pack_start(close, False, False, 0)
        tab_box.show_all()
        index = self.notebook.append_page(webview, tab_box)
        self.webviews[webview] = {"label": label, "address": initial_url or ""}
        self.notebook.set_current_page(index)
        webview.show()
        if initial_url:
            self.navigate_in(webview, initial_url)
        elif self.state["preferences"]["newTabMode"] == "about":
            webview.load_uri("about:blank")
        else:
            webview.load_html(
                start_page(self.state["bookmarks"], self.state["preferences"]["searchEngine"]),
                "file:///",
            )
        if save:
            self.save_tabs()
        return webview

    def current_view(self):
        page = self.notebook.get_nth_page(self.notebook.get_current_page())
        return page

    def close_tab(self, webview):
        page = self.notebook.page_num(webview)
        if page < 0:
            return
        uri = webview.get_uri()
        if uri and self.is_restorable(uri):
            self.closed_tabs.append(uri)
        self.webviews.pop(webview, None)
        self.notebook.remove_page(page)
        if self.notebook.get_n_pages() == 0:
            self.new_tab()
        self.save_tabs()

    def reopen_tab(self, *_):
        if self.closed_tabs:
            self.new_tab(self.closed_tabs.pop())

    def navigate(self, text):
        self.navigate_in(self.current_view(), text)

    def navigate_in(self, webview, text):
        text = text.strip()
        if not text:
            return
        if text.lower() in ("about", "about:blank"):
            webview.load_uri("about:blank")
            return
        parsed = urlparse(text)
        if parsed.scheme == "file":
            webview.load_uri(text)
            return
        if parsed.scheme in ("http", "https") and parsed.netloc:
            webview.load_uri(text)
            return
        if "://" in text:
            self.status.set_text("Поддерживаются только HTTP, HTTPS и локальные файлы.")
            return
        if not any(char.isspace() for char in text) and "." in text:
            webview.load_uri("https://" + text)
            return
        engine = self.state["preferences"]["searchEngine"]
        base = {"DuckDuckGo": "https://duckduckgo.com/?q=", "Bing": "https://www.bing.com/search?q="}.get(
            engine, "https://www.google.com/search?q="
        )
        webview.load_uri(base + quote(text))

    def on_load_changed(self, webview, event):
        if getattr(self, "smoke_test", False):
            print(
                f"Delta Linux smoke test: WebKit load {event.name}: "
                f"{webview.get_uri()!r} ({webview.get_title()!r})",
                flush=True,
            )
        if event == WebKit2.LoadEvent.STARTED:
            if webview == self.current_view():
                self.status.set_text("Загрузка…")
        elif event == WebKit2.LoadEvent.FINISHED:
            if webview == self.current_view():
                self.status.set_text("Готово")
            uri, title = webview.get_uri(), webview.get_title() or webview.get_uri() or "Страница"
            if uri and uri.startswith(("http://", "https://")):
                self.state["history"].insert(0, {
                    "title": title, "url": uri,
                    "date": datetime.now(timezone.utc).isoformat(),
                })
                self.state["history"] = self.state["history"][:5000]
                save_state(self.state)
            self.save_tabs()

    def on_load_failed(self, webview, event, failing_uri, error):
        if getattr(self, "smoke_test", False):
            print(
                f"Delta Linux smoke test: load failed for {failing_uri!r}: {error}",
                file=sys.stderr,
                flush=True,
            )
        monitor = Gio.NetworkMonitor.get_default()
        disconnected = not monitor.get_network_available()
        if hasattr(monitor, "get_connectivity"):
            disconnected = monitor.get_connectivity() == Gio.NetworkConnectivity.NONE
        if disconnected:
            game = Path(__file__).resolve().parents[1] / "Shared" / "dino.html"
            if game.is_file():
                webview.load_uri(game.as_uri())
                return True
        if webview == self.current_view():
            self.status.set_text("Не удалось загрузить страницу")
        return False

    def on_title_changed(self, webview, *_):
        info = self.webviews.get(webview)
        if info:
            title = webview.get_title() or "Новая вкладка"
            info["label"].set_text(title[:28])
            info["label"].set_tooltip_text(title)

    def on_uri_changed(self, webview, *_):
        if webview == self.current_view():
            uri = webview.get_uri() or ""
            self.address.set_text("" if uri in ("about:blank", "file:///") else uri)
            info = self.webviews.get(webview)
            if info is not None:
                info["address"] = uri

    def on_switch_page(self, notebook, page, page_num):
        global _ACTIVE_WINDOW
        _ACTIVE_WINDOW = self
        self.address.set_text(page.get_uri() or "")

    def on_focus(self, *_):
        global _ACTIVE_WINDOW
        _ACTIVE_WINDOW = self
        return False

    def on_create_view(self, webview, navigation_action):
        new_view = self.new_tab(save=False)
        return new_view

    def on_decide_policy(self, webview, decision, decision_type):
        if decision_type == WebKit2.PolicyDecisionType.NEW_WINDOW_ACTION:
            decision.use()
            return True
        return False

    def on_download_started(self, context, download):
        directory = Path(self.state["preferences"]["downloadFolder"]).expanduser()
        directory.mkdir(parents=True, exist_ok=True)

        def choose_destination(item, suggested_filename):
            name = Path(suggested_filename or "download").name
            destination = directory / name
            suffix = 1
            while destination.exists():
                destination = directory / f"{Path(name).stem} ({suffix}){Path(name).suffix}"
                suffix += 1
            item.set_destination(destination.resolve().as_uri())
            self.downloads.append({"download": item, "path": str(destination)})
            self.download_status.set_text(f"Загрузка: {name}")
            return True

        download.connect("decide-destination", choose_destination)
        download.connect("received-data", lambda item, length: self.update_download_status(item))
        download.connect("finished", lambda item: self.finish_download(item, False))
        download.connect("failed", lambda item, error: self.finish_download(item, True, str(error)))

    def update_download_status(self, download):
        received = download.get_received_data_length()
        response = download.get_response()
        total = response.get_content_length() if response else 0
        percent = f"{int(received * 100 / total)}%" if total > 0 else f"{received // 1024} KB"
        self.download_status.set_text(f"Загрузка — {percent}")

    def finish_download(self, download, failed, message=""):
        record = next((item for item in self.downloads if item["download"] == download), None)
        if record:
            self.download_status.set_text(f"Ошибка загрузки: {message}" if failed else f"Загружено: {Path(record['path']).name}")

    def add_bookmark(self, *_):
        webview = self.current_view()
        url = webview.get_uri() or ""
        if not url.startswith(("http://", "https://")):
            return
        if any(item["url"] == url for item in self.state["bookmarks"]):
            return
        self.state["bookmarks"].insert(0, {"title": webview.get_title() or url, "url": url})
        save_state(self.state)
        self.status.set_text("Добавлено в закладки")

    def show_items(self, title, key):
        dialog = Gtk.Dialog(title=title, transient_for=self, flags=0)
        dialog.set_default_size(720, 440)
        box = dialog.get_content_area()
        search = Gtk.SearchEntry()
        search.set_placeholder_text("Поиск")
        box.pack_start(search, False, False, 6)
        store = Gtk.ListStore(str, str, str)
        for item in self.state[key]:
            store.append([item.get("title", ""), item.get("url", ""), item.get("date", "")])
        tree = Gtk.TreeView(model=store)
        for index, name in enumerate(("Название", "Адрес", "Дата")):
            tree.append_column(Gtk.TreeViewColumn(name, Gtk.CellRendererText(), text=index))
        box.pack_start(tree, True, True, 6)
        filtered = Gtk.TreeModelFilter(model=store)
        filtered.set_visible_func(lambda model, iterator, *_: not search.get_text() or
                                  search.get_text().casefold() in model.get_value(iterator, 0).casefold() or
                                  search.get_text().casefold() in model.get_value(iterator, 1).casefold())
        tree.set_model(filtered)
        search.connect("search-changed", lambda *_: filtered.refilter())
        open_button = dialog.add_button("Открыть", Gtk.ResponseType.ACCEPT)
        remove_button = dialog.add_button("Удалить", Gtk.ResponseType.APPLY)
        dialog.add_button("Закрыть", Gtk.ResponseType.CLOSE)
        remove_button.set_sensitive(key == "bookmarks")

        def respond(dlg, response):
            selection = tree.get_selection()
            model, iterator = selection.get_selected()
            if response == Gtk.ResponseType.ACCEPT and iterator:
                self.new_tab(model.get_value(iterator, 1))
                dlg.destroy()
            elif response == Gtk.ResponseType.APPLY and iterator and key == "bookmarks":
                url = model.get_value(iterator, 1)
                self.state[key] = [item for item in self.state[key] if item["url"] != url]
                save_state(self.state)
                child_path = model.convert_path_to_child_path(model.get_path(iterator))
                child_iterator = store.get_iter(child_path)
                store.remove(child_iterator)
            elif response == Gtk.ResponseType.CLOSE:
                dlg.destroy()
        dialog.connect("response", respond)
        dialog.show_all()

    def show_settings(self, *_):
        dialog = Gtk.Dialog(title="Настройки Delta", transient_for=self, flags=0)
        dialog.set_default_size(590, 490)
        notebook = Gtk.Notebook()
        dialog.get_content_area().pack_start(notebook, True, True, 6)
        prefs = self.state["preferences"]
        general = Gtk.Grid(column_spacing=12, row_spacing=12, margin=16)
        homepage = Gtk.Entry(text=prefs["homepage"])
        engine = Gtk.ComboBoxText()
        for item in ("Google", "DuckDuckGo", "Bing"):
            engine.append_text(item)
        engine.set_active(max(0, ("Google", "DuckDuckGo", "Bing").index(prefs["searchEngine"])))
        new_tab = Gtk.ComboBoxText()
        new_tab.append("home", "Стартовая страница")
        new_tab.append("about", "Пустая about")
        new_tab.set_active_id(prefs["newTabMode"])
        startup = Gtk.ComboBoxText()
        for key, label in (("restore", "Восстановить вкладки"), ("home", "Стартовая"), ("homepage", "Домашняя страница"), ("about", "Пустая about")):
            startup.append(key, label)
        startup.set_active_id(prefs["startupMode"])
        self.grid_row(general, 0, "Домашняя страница", homepage)
        self.grid_row(general, 1, "Поисковая система", engine)
        self.grid_row(general, 2, "Новая вкладка", new_tab)
        self.grid_row(general, 3, "При запуске", startup)
        notebook.append_page(general, Gtk.Label(label="Основные"))

        appearance = Gtk.Grid(column_spacing=12, row_spacing=12, margin=16)
        theme = Gtk.ComboBoxText()
        for item in ("System", "Light", "Dark"):
            theme.append_text(item)
        theme.set_active(max(0, ("System", "Light", "Dark").index(prefs["theme"])))
        zoom = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.5, 2.0, 0.05)
        zoom.set_value(float(prefs["zoom"]))
        zoom.set_digits(2)
        self.grid_row(appearance, 0, "Тема", theme)
        self.grid_row(appearance, 1, "Масштаб", zoom)
        notebook.append_page(appearance, Gtk.Label(label="Внешний вид"))

        privacy = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        for label, types in (
            ("Очистить cookies", WebKit2.WebsiteDataTypes.COOKIES),
            ("Очистить кэш", WebKit2.WebsiteDataTypes.DISK_CACHE),
            ("Очистить данные сайтов", WebKit2.WebsiteDataTypes.ALL),
        ):
            button = Gtk.Button(label=label)
            button.connect("clicked", lambda _, kind=types: self.clear_site_data(kind))
            privacy.pack_start(button, False, False, 0)
        clear_history = Gtk.Button(label="Очистить историю посещений")
        clear_history.connect("clicked", lambda *_: self.clear_history())
        privacy.pack_start(clear_history, False, False, 0)
        notebook.append_page(privacy, Gtk.Label(label="Приватность"))

        downloads = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, margin=16)
        folder = Gtk.Entry(text=prefs["downloadFolder"])
        choose = Gtk.Button(label="Выбрать…")
        choose.connect("clicked", lambda *_: self.choose_download_folder(folder))
        downloads.pack_start(folder, True, True, 0)
        downloads.pack_start(choose, False, False, 0)
        open_folder = Gtk.Button(label="Открыть папку загрузок")
        open_folder.connect("clicked", lambda *_: self.open_folder(folder.get_text()))
        download_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        download_page.pack_start(downloads, False, False, 0)
        download_page.pack_start(open_folder, False, False, 0)
        notebook.append_page(download_page, Gtk.Label(label="Загрузки"))

        dialog.add_button("Отмена", Gtk.ResponseType.CANCEL)
        dialog.add_button("Сохранить", Gtk.ResponseType.OK)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            prefs.update({
                "homepage": homepage.get_text().strip() or "https://www.google.com",
                "searchEngine": engine.get_active_text() or "Google",
                "newTabMode": new_tab.get_active_id() or "home",
                "startupMode": startup.get_active_id() or "restore",
                "theme": theme.get_active_text() or "System",
                "zoom": zoom.get_value(),
                "downloadFolder": folder.get_text().strip() or str(Path.home() / "Downloads"),
            })
            Path(prefs["downloadFolder"]).expanduser().mkdir(parents=True, exist_ok=True)
            for view in self.webviews:
                view.set_zoom_level(float(prefs["zoom"]))
            save_state(self.state)
            self.apply_theme()
        dialog.destroy()

    @staticmethod
    def grid_row(grid, row, label, control):
        grid.attach(Gtk.Label(label=label, xalign=0), 0, row, 1, 1)
        grid.attach(control, 1, row, 1, 1)

    def clear_site_data(self, types):
        def finish(manager, result):
            try:
                manager.clear_finish(result)
                self.status.set_text("Данные сайтов очищены")
            except GLib.Error as error:
                print(f"Delta: failed to clear site data: {error}", file=sys.stderr)
                self.status.set_text("Не удалось очистить данные сайтов")
        self.data_manager.clear(types, 0, None, finish)

    def clear_history(self):
        self.state["history"].clear()
        save_state(self.state)
        self.status.set_text("История очищена")

    def choose_download_folder(self, entry):
        dialog = Gtk.FileChooserDialog(title="Папка загрузок", parent=self,
                                       action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons("Отмена", Gtk.ResponseType.CANCEL, "Выбрать", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            entry.set_text(dialog.get_filename())
        dialog.destroy()

    @staticmethod
    def open_folder(path):
        Path(path).expanduser().mkdir(parents=True, exist_ok=True)
        Gio.AppInfo.launch_default_for_uri(Path(path).expanduser().resolve().as_uri(), None)

    def open_downloads(self, *_):
        folder = Path(self.state["preferences"]["downloadFolder"]).expanduser()
        folder.mkdir(parents=True, exist_ok=True)
        dialog = Gtk.Dialog(title="Загрузки", transient_for=self, flags=0)
        dialog.set_default_size(700, 420)
        tree = Gtk.TreeView()
        store = Gtk.ListStore(str, str, str, str)
        for path in sorted(folder.iterdir(), key=lambda item: item.stat().st_mtime, reverse=True):
            if path.is_file():
                info = path.stat()
                store.append([path.name, f"{info.st_size // 1024} КБ",
                              datetime.fromtimestamp(info.st_mtime).strftime("%Y-%m-%d %H:%M"),
                              str(path)])
        tree.set_model(store)
        for index, title in enumerate(("Файл", "Размер", "Дата", "Путь")):
            column = Gtk.TreeViewColumn(title, Gtk.CellRendererText(), text=index)
            if index == 3:
                column.set_visible(False)
            tree.append_column(column)
        dialog.get_content_area().pack_start(tree, True, True, 6)
        dialog.add_button("Открыть файл", Gtk.ResponseType.ACCEPT)
        dialog.add_button("Открыть папку", Gtk.ResponseType.APPLY)
        dialog.add_button("Закрыть", Gtk.ResponseType.CLOSE)

        def respond(dlg, response):
            model, iterator = tree.get_selection().get_selected()
            if response == Gtk.ResponseType.ACCEPT and iterator:
                Gio.AppInfo.launch_default_for_uri(Path(model.get_value(iterator, 3)).as_uri(), None)
            elif response == Gtk.ResponseType.APPLY:
                self.open_folder(str(folder))
            else:
                dlg.destroy()
        dialog.connect("response", respond)
        dialog.show_all()

    def on_key_press(self, _window, event):
        ctrl = bool(event.state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        if ctrl and event.keyval == Gdk.KEY_t:
            self.new_tab()
            return True
        if ctrl and event.keyval == Gdk.KEY_w:
            self.close_tab(self.current_view())
            return True
        if ctrl and shift and event.keyval == Gdk.KEY_t:
            self.reopen_tab()
            return True
        if ctrl and event.keyval == Gdk.KEY_l:
            self.address.grab_focus()
            self.address.select_region(0, -1)
            return True
        return False

    def open_html(self, *_):
        dialog = Gtk.FileChooserDialog(title="Открыть HTML-файл", parent=self,
                                       action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons("Отмена", Gtk.ResponseType.CANCEL, "Открыть", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            self.new_tab(Path(dialog.get_filename()).resolve().as_uri())
        dialog.destroy()

    def apply_theme(self):
        theme = self.state["preferences"]["theme"]
        if theme == "System":
            Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", False)
        else:
            Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", theme == "Dark")

    def save_tabs(self):
        self.state["openTabs"] = [
            (view.get_uri() or "")
            for window in _WINDOWS
            for view in window.webviews
            if self.is_restorable(view.get_uri() or "")
        ][:20]
        save_state(self.state)

    def on_close(self, *_):
        global _ACTIVE_WINDOW
        self.save_tabs()
        if self in _WINDOWS:
            _WINDOWS.remove(self)
        if _ACTIVE_WINDOW is self:
            _ACTIVE_WINDOW = _WINDOWS[-1] if _WINDOWS else None
        return False


def main():
    global _SMOKE_FAILURE
    DATA_HOME.mkdir(parents=True, exist_ok=True)
    CACHE_HOME.mkdir(parents=True, exist_ok=True)
    smoke_test = "--smoke-test" in sys.argv[1:]
    if smoke_test:
        state = load_state()
        state["preferences"]["newTabMode"] = "about"
        state["preferences"]["startupMode"] = "about"
        state["openTabs"] = []
        save_state(state)
    args = [arg for arg in sys.argv[1:] if arg != "--smoke-test"]
    open_file = args[0] if args else None
    window = DeltaWindow(open_file, smoke_test=smoke_test)
    window.connect("destroy", on_window_destroy)
    Gtk.main()
    if _SMOKE_FAILURE:
        raise SystemExit(1)


def on_window_destroy(window):
    if window in _WINDOWS:
        _WINDOWS.remove(window)
    if not _WINDOWS:
        Gtk.main_quit()


_SMOKE_FAILURE = None


if __name__ == "__main__":
    main()
