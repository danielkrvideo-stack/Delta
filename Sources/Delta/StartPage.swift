import SwiftUI

struct StartPageView: View {
    @ObservedObject var store: BrowserStore
    let search: (String) -> Void
    @State private var query = ""
    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newURL = ""

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 16)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.17, blue: 0.34),
                    Color(red: 0.24, green: 0.27, blue: 0.49),
                    Color(red: 0.42, green: 0.29, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.055))
                .frame(width: 520, height: 520)
                .blur(radius: 3)
                .offset(x: 350, y: -210)
            ScrollView(.vertical) {
                VStack(spacing: 30) {
                    Spacer(minLength: 65)
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Delta")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .tracking(-1.5)
                            .foregroundStyle(.white)
                    }
                    Text("Весь интернет — в одном месте")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.72))
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск в интернете или введите адрес", text: $query)
                            .textFieldStyle(.plain)
                            .onSubmit { search(query) }
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 620, minHeight: 52)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)

                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Быстрые ссылки").font(.headline).foregroundStyle(.white)
                            Spacer()
                            Button { showingAdd = true } label: {
                                Label("Добавить сайт", systemImage: "plus")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.86))
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.bookmarks) { item in
                                Button { search(item.url) } label: {
                                    VStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 13)
                                                .fill(.white.opacity(0.17))
                                                .frame(width: 46, height: 46)
                                            Text(String(item.title.prefix(1)).uppercased())
                                                .font(.system(size: 21, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                        }
                                        Text(item.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.94))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 92)
                                    .padding(.vertical, 12)
                                    .background(.white.opacity(0.075))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Удалить из быстрых ссылок", role: .destructive) {
                                        store.removeBookmark(item)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 670)

                    if !store.history.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Недавно посещённые").font(.headline).foregroundStyle(.white)
                            ForEach(Array(store.history.prefix(5))) { item in
                                Button { search(item.url) } label: {
                                    HStack {
                                        Image(systemName: "clock").foregroundStyle(.white.opacity(0.65))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title).foregroundStyle(.white).lineLimit(1)
                                            Text(item.url).font(.caption).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.left").foregroundStyle(.white.opacity(0.5))
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 670)
                    }
                    Spacer(minLength: 35)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Добавить быстрый сайт", isPresented: $showingAdd) {
            TextField("Название", text: $newTitle)
            TextField("Адрес сайта", text: $newURL)
            Button("Добавить") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !url.isEmpty else { return }
                let resolved = (url.hasPrefix("http://") || url.hasPrefix("https://")) ? url : "https://" + url
                store.addBookmark(url: resolved, title: title)
                newTitle = ""
                newURL = ""
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ссылка будет добавлена в быстрые ссылки и закладки.")
        }
    }
}
