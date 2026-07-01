//
//  ContentView.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasSeededSamples") private var hasSeededSamples: Bool = false

    // DEBUG: Bypass SwiftData on device to ensure UI shows even if container/query misbehaves
    #if DEBUG
    private let debugBypassSwiftData = true
    #else
    private let debugBypassSwiftData = false
    #endif

    @State private var tracks: [Track] = []
    @State private var selectedTrack: Track?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 12)]
    }

    var body: some View {
        ZStack {
            Group {
                if sizeClass == .regular {
                    NavigationSplitView {
                        mainGrid
                            .navigationTitle("发现音乐")
                            .toolbar { actionsToolbar }
                            .safeAreaInset(edge: .bottom) { MiniPlayerBar(track: selectedTrack) }
                    } detail: {
                        if let track = selectedTrack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(track.title).font(.title2).bold()
                                Text(track.artistName).foregroundStyle(.secondary)
                                if let album = track.albumName { Text(album) }
                                Text(track.platform == .appleMusic ? "Apple Music" : "Spotify")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .padding()
                        } else {
                            Text("选择一首歌或生成推荐")
                        }
                    }
                } else {
                    NavigationStack {
                        mainGrid
                            .navigationTitle("发现音乐")
                            .toolbar { actionsToolbar }
                            .safeAreaInset(edge: .bottom) { MiniPlayerBar(track: selectedTrack) }
                    }
                }
            }

            // Root-level debug overlay to confirm view is rendered
            VStack {
                HStack {
                    Text("[DEBUG] Root Loaded")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
        .background(Color(.systemBackground))
        .onChange(of: tracks.count) { newValue in
            print("[DEBUG] tracks.count =", newValue)
        }
        .onAppear {
            if debugBypassSwiftData {
                if !hasSeededSamples && tracks.isEmpty {
                    seedInMemoryIfNeeded()
                }
            } else {
                loadTracks()
                if !hasSeededSamples && tracks.isEmpty {
                    addSampleGridData()
                    hasSeededSamples = true
                }
            }
        }
        .onAppear {
            let data = (debugBypassSwiftData && tracks.isEmpty) ? sampleTracks : tracks
            if selectedTrack == nil, let first = data.first { selectedTrack = first }
        }
        .task {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                if debugBypassSwiftData {
                    seedInMemoryIfNeeded()
                } else {
                    if !hasSeededSamples && tracks.isEmpty {
                        addSampleGridData()
                        hasSeededSamples = true
                        loadTracks()
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var actionsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("连接 Apple Music", action: connectAppleMusic)
                Button("连接 Spotify", action: connectSpotify)
                Button("刷新收藏", action: refreshLibrary)
                Button("生成推荐", action: generateRecommendations)
                Divider()
                Button("添加示例歌曲", action: addSampleTrack)
                Button("批量添加示例", action: addSampleGridData)
            } label: {
                Label("操作", systemImage: "ellipsis.circle")
            }
        }
    }

    private func loadTracks() {
        do {
            let descriptor = FetchDescriptor<Track>(sortBy: [SortDescriptor(\Track.dateAdded, order: .reverse)])
            let results = try modelContext.fetch(descriptor)
            self.tracks = results
            print("[DEBUG] loadTracks fetched:", results.count)
        } catch {
            print("[ERROR] loadTracks failed:", String(describing: error))
        }
    }

    private func seedInMemoryIfNeeded() {
        guard tracks.isEmpty else { return }
        let samples: [(String, String, String, String)] = [
            ("Miracle", "Calvin Harris & Ellie Goulding", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/1b/b5/1f/1bb51f86-2d1e-1f3b-6b9a-1b1d2d2f3f53/196871126262.jpg/400x400bb.jpg"),
            ("greedy", "Tate McRae", "Tate McRae", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/7a/6b/73/7a6b73b2-2a2c-9b1a-6c3a-fc9a9f9c0a4b/054391922915.jpg/400x400bb.jpg"),
            ("Paint The Town Red", "Doja Cat", "Doja Cat", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/1c/27/aa/1c27aa5b-2d3b-0b3f-8b2f-1b9fceefb2aa/23UM1IM16176.rgb.jpg/400x400bb.jpg"),
            ("One Kiss", "Calvin Harris & Dua Lipa", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/29/2a/5a/292a5a8b-1c9f-2e3a-5c2f-8e2e7d4c5a7b/886447585532.jpg/400x400bb.jpg"),
            ("Anti-Hero", "Taylor Swift", "Taylor Swift", "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/2a/40/f8/2a40f8c1-2d3c-2a1b-1e3d-2f4b5c6d7e8f/22UM1IM19271.rgb.jpg/400x400bb.jpg"),
            ("DESIRE", "Calvin Harris & Sam Smith", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/8f/3a/1d/8f3a1d9b-2d1c-3b2f-6a4b-1b2c3d4e5f6a/196871125707.jpg/400x400bb.jpg")
        ]
        self.tracks = samples.map { s in
            Track(title: s.0, artistName: s.1, albumName: s.2, platform: .appleMusic, platformID: nil, artworkURL: URL(string: s.3))
        }
        print("[DEBUG] seeded in-memory:", tracks.count)
    }
    
    private var sampleTracks: [Track] {
        [
            Track(title: "Miracle", artistName: "Calvin Harris & Ellie Goulding", albumName: "Calvin Harris", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/1b/b5/1f/1bb51f86-2d1e-1f3b-6b9a-1b1d2d2f3f53/196871126262.jpg/400x400bb.jpg")),
            Track(title: "greedy", artistName: "Tate McRae", albumName: "Tate McRae", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/7a/6b/73/7a6b73b2-2a2c-9b1a-6c3a-fc9a9f9c0a4b/054391922915.jpg/400x400bb.jpg")),
            Track(title: "Paint The Town Red", artistName: "Doja Cat", albumName: "Doja Cat", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/1c/27/aa/1c27aa5b-2d3b-0b3f-8b2f-1b9fceefb2aa/23UM1IM16176.rgb.jpg/400x400bb.jpg")),
            Track(title: "One Kiss", artistName: "Calvin Harris & Dua Lipa", albumName: "Calvin Harris", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/29/2a/5a/292a5a8b-1c9f-2e3a-5c2f-8e2e7d4c5a7b/886447585532.jpg/400x400bb.jpg")),
            Track(title: "Anti-Hero", artistName: "Taylor Swift", albumName: "Taylor Swift", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/2a/40/f8/2a40f8c1-2d3c-2a1b-1e3d-2f4b5c6d7e8f/22UM1IM19271.rgb.jpg/400x400bb.jpg")),
            Track(title: "DESIRE", artistName: "Calvin Harris & Sam Smith", albumName: "Calvin Harris", platform: .appleMusic, platformID: nil, artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/8f/3a/1d/8f3a1d9b-2d1c-3b2f-6a4b-1b2c3d4e5f6a/196871125707.jpg/400x400bb.jpg"))
        ]
    }

    private var mainGrid: some View {
        ZStack {
            // Debug banner
            VStack {
                HStack {
                    Text("tracks: \(tracks.count)  sizeClass: \(sizeClass == .regular ? "regular" : "compact/nil")")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                let data = (debugBypassSwiftData && tracks.isEmpty) ? sampleTracks : tracks
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, track in
                        Button { selectedTrack = track } label: {
                            ArtworkTile(track: track)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }

            if (debugBypassSwiftData && tracks.isEmpty) || (!debugBypassSwiftData && tracks.isEmpty) {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("还没有内容")
                        .font(.headline)
                    Text("点击右上角“操作”添加示例，或连接 Apple Music / Spotify。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("快速添加示例") { addSampleGridData() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
            }
        }
        .background(Color(.systemBackground))
    }

    private func connectAppleMusic() { /* TODO */ }
    private func connectSpotify() { /* TODO */ }
    private func refreshLibrary() { /* TODO */ }
    private func generateRecommendations() { /* TODO */ }

    private func addSampleTrack() {
        withAnimation {
            let sample = Track(
                title: "Sample Song",
                artistName: "Sample Artist",
                albumName: "Sample Album",
                platform: Platform.appleMusic,
                platformID: (nil as String?),
                artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/2d/93/2b/2d932b8a-2b8b-0e4a-6e87-9a1a3d4b55a7/23UM1IM04247.rgb.jpg/400x400bb.jpg")
            )
            if debugBypassSwiftData {
                tracks.append(sample)
            } else {
                modelContext.insert(sample)
                try? modelContext.save()
                loadTracks()
                if tracks.isEmpty { tracks.append(sample) }
            }
        }
    }

    private func addSampleGridData() {
        let samples: [(String, String, String, String)] = [
            ("Miracle", "Calvin Harris & Ellie Goulding", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/1b/b5/1f/1bb51f86-2d1e-1f3b-6b9a-1b1d2d2f3f53/196871126262.jpg/400x400bb.jpg"),
            ("greedy", "Tate McRae", "Tate McRae", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/7a/6b/73/7a6b73b2-2a2c-9b1a-6c3a-fc9a9f9c0a4b/054391922915.jpg/400x400bb.jpg"),
            ("Paint The Town Red", "Doja Cat", "Doja Cat", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/1c/27/aa/1c27aa5b-2d3b-0b3f-8b2f-1b9fceefb2aa/23UM1IM16176.rgb.jpg/400x400bb.jpg"),
            ("One Kiss", "Calvin Harris & Dua Lipa", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/29/2a/5a/292a5a8b-1c9f-2e3a-5c2f-8e2e7d4c5a7b/886447585532.jpg/400x400bb.jpg"),
            ("Anti-Hero", "Taylor Swift", "Taylor Swift", "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/2a/40/f8/2a40f8c1-2d3c-2a1b-1e3d-2f4b5c6d7e8f/22UM1IM19271.rgb.jpg/400x400bb.jpg"),
            ("DESIRE", "Calvin Harris & Sam Smith", "Calvin Harris", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/8f/3a/1d/8f3a1d9b-2d1c-3b2f-6a4b-1b2c3d4e5f6a/196871125707.jpg/400x400bb.jpg")
        ]

        var created: [Track] = []
        withAnimation {
            if debugBypassSwiftData {
                created = samples.map { s in
                    Track(title: s.0, artistName: s.1, albumName: s.2, platform: .appleMusic, platformID: nil, artworkURL: URL(string: s.3))
                }
                tracks.append(contentsOf: created)
            } else {
                for s in samples {
                    let track = Track(
                        title: s.0,
                        artistName: s.1,
                        albumName: s.2,
                        platform: Platform.appleMusic,
                        platformID: (nil as String?),
                        artworkURL: URL(string: s.3)
                    )
                    modelContext.insert(track)
                    created.append(track)
                }
                try? modelContext.save()
                loadTracks()
                if created.isEmpty == false && tracks.isEmpty {
                    tracks.append(contentsOf: created)
                }
            }
        }
    }
}

private struct ArtworkTile: View {
    let track: Track

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = track.artworkURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            } else {
                ZStack {
                    LinearGradient(colors: [.pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(initials(from: track.title))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            }
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(height: 50)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .padding(8)
                }
        }
    }

    private func initials(from text: String) -> String {
        let parts = text.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? String(text.prefix(1)) : initials
    }
}

private struct MiniPlayerBar: View {
    let track: Track?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let track = track {
                    if let url = track.artworkURL {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.gray.opacity(0.2))
                            .frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading) {
                        Text(track.title).font(.subheadline).lineLimit(1)
                        Text(track.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { /* TODO: Prev */ } label: { Image(systemName: "backward.fill") }
                    Button { /* TODO: Play/Pause */ } label: { Image(systemName: "play.fill") }
                    Button { /* TODO: Next */ } label: { Image(systemName: "forward.fill") }
                } else {
                    Text("未选择歌曲")
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(.ultraThinMaterial)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Track.self, inMemory: true)
}

