//
//  ContentView.swift
//  musicfind
//
//  Created by 项程锦 on 2026/6/30.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var activeTab: AppTab = .home
    @State private var nowPlaying = DemoSong.library[0]
    @State private var isPlayerCardVisible = false
    @State private var isPlayerCardExpanded = false
    @State private var isPlayerCardContentVisible = false
    @State private var isPlayerPillHiddenForExpansion = false
    @State private var playerPillFrame: CGRect = .zero
    @Namespace private var playerExpansionNamespace

    private let songs = DemoSong.library
    private let spacing: CGFloat = 8
    private let columns = 0..<4

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.027, blue: 0.098)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(columns), id: \.self) { column in
                        LazyVStack(spacing: spacing) {
                            ForEach(songsForColumn(column)) { song in
                                Button {
                                    nowPlaying = song
                                } label: {
                                    SongSquare(song: song, isPlaying: song.id == nowPlaying.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, topOffset(for: column))
                    }
                }
                .padding(.horizontal, spacing)
                .padding(.top, spacing)
                .padding(.bottom, 92)
            }

            TopGlassFade()
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            BottomGlassFade()
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    DateBadge()
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .offset(x: 20, y: 40)

                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                Spacer()
                BottomNavigationBar(
                    activeTab: $activeTab,
                    nowPlaying: nowPlaying,
                    namespace: playerExpansionNamespace,
                    isPlayerCardVisible: isPlayerPillHiddenForExpansion,
                    playerPillFrame: $playerPillFrame,
                    onPlayerTap: showPlayerCard
                )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }

            if isPlayerCardVisible {
                Color.black.opacity(isPlayerCardContentVisible ? 0.34 : 0.0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.18), value: isPlayerCardContentVisible)
                    .onTapGesture(perform: hidePlayerCard)

                GeometryReader { proxy in
                    let expandedWidth = proxy.size.width - 12
                    let expandedHeight = proxy.size.height - 36
                    let collapsedFrame = playerPillFrame == .zero
                        ? CGRect(x: (proxy.size.width - 226) / 2, y: proxy.size.height - 65, width: 226, height: 53)
                        : playerPillFrame
                    let currentWidth = isPlayerCardExpanded ? expandedWidth : collapsedFrame.width
                    let currentHeight = isPlayerCardExpanded ? expandedHeight : collapsedFrame.height
                    let currentCornerRadius: CGFloat = isPlayerCardExpanded ? 34 : collapsedFrame.height / 2
                    let currentSurfaceOpacity = isPlayerCardExpanded ? 1.0 : 0.74

                    ExpandedPlayerCard(
                        song: nowPlaying,
                        namespace: playerExpansionNamespace,
                        cornerRadius: currentCornerRadius,
                        surfaceOpacity: currentSurfaceOpacity,
                        isContentVisible: isPlayerCardContentVisible,
                        onClose: hidePlayerCard
                    )
                    .frame(
                        width: currentWidth,
                        height: currentHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
                    .position(
                        x: isPlayerCardExpanded ? proxy.size.width / 2 : collapsedFrame.midX,
                        y: isPlayerCardExpanded
                            ? proxy.size.height / 2
                            : collapsedFrame.midY
                    )
                    .animation(.smooth(duration: 0.28, extraBounce: 0.0), value: isPlayerCardExpanded)
                }
                .ignoresSafeArea()
                .transition(.identity)
            }
        }
    }

    private func showPlayerCard() {
        guard !isPlayerCardVisible else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeTab = .player
        isPlayerCardExpanded = false
        isPlayerCardContentVisible = false
        isPlayerPillHiddenForExpansion = false

        isPlayerCardVisible = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard isPlayerCardVisible else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                isPlayerPillHiddenForExpansion = true
            }
            withAnimation(.smooth(duration: 0.30, extraBounce: 0.02)) {
                isPlayerCardExpanded = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            guard isPlayerCardVisible else { return }
            withAnimation(.easeOut(duration: 0.1)) {
                isPlayerCardContentVisible = true
            }
        }
    }

    private func hidePlayerCard() {
        guard isPlayerCardVisible else { return }

        withAnimation(.easeIn(duration: 0.12)) {
            isPlayerCardContentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.smooth(duration: 0.26, extraBounce: 0.0)) {
                isPlayerCardExpanded = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            isPlayerCardVisible = false
            isPlayerPillHiddenForExpansion = false
            isPlayerCardContentVisible = false
            isPlayerCardExpanded = false
        }
    }

    private func songsForColumn(_ column: Int) -> [DemoSong] {
        songs.enumerated().compactMap { index, song in
            index % 4 == column ? song : nil
        }
    }

    private func topOffset(for column: Int) -> CGFloat {
        switch column {
        case 0: 18
        case 2: 28
        default: 0
        }
    }

}

private enum AppTab {
    case home
    case player
    case settings
}

private struct DateBadge: View {
    private let dateText = Date.now.formatted(
        .dateTime
            .day()
            .month(.wide)
            .locale(Locale(identifier: "en_US_POSIX"))
    )
        .lowercased()

    var body: some View {
        Text(dateText)
            .font(.system(size: 50, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct BottomNavigationBar: View {
    @Binding var activeTab: AppTab
    let nowPlaying: DemoSong
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    @Binding var playerPillFrame: CGRect
    let onPlayerTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CircleActionButton(systemName: "house.fill", isActive: activeTab == .home) {
                activeTab = .home
            }

            PlayerPill(
                song: nowPlaying,
                isActive: activeTab == .player,
                namespace: namespace,
                isPlayerCardVisible: isPlayerCardVisible,
                playerPillFrame: $playerPillFrame,
                action: onPlayerTap
            )

            CircleActionButton(systemName: "magnifyingglass", isActive: activeTab == .settings) {
                activeTab = .settings
            }
        }
        .frame(maxWidth: 340)
    }
}

private struct ExpandedPlayerCard: View {
    let song: DemoSong
    let namespace: Namespace.ID
    let cornerRadius: CGFloat
    let surfaceOpacity: Double
    let isContentVisible: Bool
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(isContentVisible ? 0 : surfaceOpacity))
                .animation(.easeOut(duration: 0.12), value: isContentVisible)

            GeometryReader { proxy in
                let pageHeight = max(proxy.size.height - 6, 520)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        NowPlayingCard(song: song, onClose: onClose)
                            .frame(height: pageHeight)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            }

                        UpNextCard(song: DemoSong.library[song.id % DemoSong.library.count])
                            .frame(height: pageHeight)
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            }
                    }
                    .scrollTargetLayout()
                }
                .scrollDisabled(!isContentVisible)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollBounceBehavior(.basedOnSize)
            }
            .opacity(isContentVisible ? 1 : 0)
            .scaleEffect(isContentVisible ? 1 : 0.98)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(isContentVisible ? 0 : 0.12), lineWidth: 1)
                .animation(.easeOut(duration: 0.12), value: isContentVisible)
        }
    }
}

private struct NowPlayingCard: View {
    let song: DemoSong
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在播放")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.56))

                    Text(song.title)
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            BigAlbumDisc(song: song)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(song.artist)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)

                HStack(spacing: 18) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill")
                        .font(.system(size: 38, weight: .black))
                    Image(systemName: "forward.fill")
                }
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 12)
            }
        }
        .padding(22)
    }
}

private struct UpNextCard: View {
    let song: DemoSong

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("接下来")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 0)

            BigAlbumDisc(song: song)
                .scaleEffect(0.82)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(song.title)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(song.artist)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(24)
    }
}

private struct BigAlbumDisc: View {
    let song: DemoSong
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 108, height: 108)
                .offset(x: 48, y: -42)

            Circle()
                .fill(.black.opacity(0.28))
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.36), lineWidth: 2)
                }
        }
        .frame(width: 270, height: 270)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .id(song.id)
    }
}

private struct CircleActionButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 29, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isActive ? Color(red: 1.0, green: 0.18, blue: 0.35) : .white.opacity(0.92))
                .frame(width: 53, height: 53)
                .background(.black.opacity(0.74))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .liquidGlassSurface(cornerRadius: 27, isInteractive: true)
    }
}

private struct PlayerPill: View {
    let song: DemoSong
    let isActive: Bool
    let namespace: Namespace.ID
    let isPlayerCardVisible: Bool
    @Binding var playerPillFrame: CGRect
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(.black.opacity(0.74))

                HStack(spacing: 10) {
                    RotatingAlbumArt(song: song)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Text(song.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "pause.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 35)
                }
                .padding(.leading, 11)
                .padding(.trailing, 14)
                .opacity(isPlayerCardVisible ? 0 : 1)
            }
            .frame(height: 53)
            .clipShape(RoundedRectangle(cornerRadius: 27))
            .overlay {
                RoundedRectangle(cornerRadius: 27)
                    .stroke(.white.opacity(isActive ? 0.20 : 0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .liquidGlassSurface(cornerRadius: 27, isInteractive: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PlayerPillFramePreferenceKey.self, value: proxy.frame(in: .global))
            }
        }
        .onPreferenceChange(PlayerPillFramePreferenceKey.self) { frame in
            playerPillFrame = frame
        }
        .opacity(isPlayerCardVisible ? 0 : 1)
    }
}

private struct PlayerPillFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct RotatingAlbumArt: View {
    let song: DemoSong
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 18, height: 18)
                .offset(x: 10, y: -9)

            Circle()
                .fill(.black.opacity(0.24))
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.42), lineWidth: 1)
                }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .id(song.id)
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, isInteractive: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isInteractive {
                self.glassEffect(.regular.tint(.white.opacity(0.14)).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular.tint(.white.opacity(0.10)), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

private struct TopGlassFade: View {
    private let background = Color.black

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.78)
                    .mask(
                        LinearGradient(
                            colors: [
                                .black,
                                .black.opacity(0.86),
                                .black.opacity(0.58),
                                .black.opacity(0.22),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        background,
                        background.opacity(0.94),
                        background.opacity(0.78),
                        background.opacity(0.54),
                        background.opacity(0.30),
                        background.opacity(0.12),
                        background.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        .white.opacity(0.06),
                        .white.opacity(0.018),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
            }
            .frame(height: 320)

            Spacer(minLength: 0)
        }
    }
}

private struct BottomGlassFade: View {
    private let background = Color.black

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.78)
                    .mask(
                        LinearGradient(
                            colors: [
                                .clear,
                                .black.opacity(0.22),
                                .black.opacity(0.58),
                                .black.opacity(0.86),
                                .black
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                LinearGradient(
                    colors: [
                        background.opacity(0.0),
                        background.opacity(0.12),
                        background.opacity(0.30),
                        background.opacity(0.54),
                        background.opacity(0.78),
                        background.opacity(0.94),
                        background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.018),
                        .white.opacity(0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.screen)
            }
            .frame(height: 220)
        }
    }
}

private struct DemoSong: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let colors: [Color]

    static let library: [DemoSong] = [
        .init(id: 1, title: "DESIRE", artist: "Calvin Harris", colors: [.red, .orange]),
        .init(id: 2, title: "Anti-Hero", artist: "Taylor Swift", colors: [.indigo, .cyan]),
        .init(id: 3, title: "One Kiss", artist: "Dua Lipa", colors: [.purple, .blue]),
        .init(id: 4, title: "greedy", artist: "Tate McRae", colors: [.green, .mint]),
        .init(id: 5, title: "Miracle", artist: "Ellie Goulding", colors: [.pink, .yellow]),
        .init(id: 6, title: "Paint The Town Red", artist: "Doja Cat", colors: [.black, .red]),
        .init(id: 7, title: "Rush", artist: "Troye Sivan", colors: [.teal, .blue]),
        .init(id: 8, title: "Dance The Night", artist: "Dua Lipa", colors: [.orange, .pink]),
        .init(id: 9, title: "Ocean Eyes", artist: "Billie Eilish", colors: [.blue, .gray]),
        .init(id: 10, title: "Golden Hour", artist: "JVKE", colors: [.yellow, .orange]),
        .init(id: 11, title: "As It Was", artist: "Harry Styles", colors: [.mint, .cyan]),
        .init(id: 12, title: "Save Your Tears", artist: "The Weeknd", colors: [.purple, .red]),
        .init(id: 13, title: "Flowers", artist: "Miley Cyrus", colors: [.pink, .red]),
        .init(id: 14, title: "Levitating", artist: "Dua Lipa", colors: [.blue, .purple]),
        .init(id: 15, title: "Blinding Lights", artist: "The Weeknd", colors: [.red, .yellow]),
        .init(id: 16, title: "Bad Guy", artist: "Billie Eilish", colors: [.green, .black]),
        .init(id: 17, title: "Cruel Summer", artist: "Taylor Swift", colors: [.orange, .red]),
        .init(id: 18, title: "Heat Waves", artist: "Glass Animals", colors: [.yellow, .pink]),
        .init(id: 19, title: "Peaches", artist: "Justin Bieber", colors: [.orange, .mint]),
        .init(id: 20, title: "Stay", artist: "The Kid LAROI", colors: [.cyan, .blue]),
        .init(id: 21, title: "Watermelon Sugar", artist: "Harry Styles", colors: [.pink, .green]),
        .init(id: 22, title: "Houdini", artist: "Dua Lipa", colors: [.purple, .orange]),
        .init(id: 23, title: "vampire", artist: "Olivia Rodrigo", colors: [.black, .purple]),
        .init(id: 24, title: "Espresso", artist: "Sabrina Carpenter", colors: [.brown, .orange]),
        .init(id: 25, title: "Birds Of A Feather", artist: "Billie Eilish", colors: [.cyan, .mint]),
        .init(id: 26, title: "Fortnight", artist: "Taylor Swift", colors: [.gray, .black]),
        .init(id: 27, title: "Training Season", artist: "Dua Lipa", colors: [.blue, .pink]),
        .init(id: 28, title: "Illusion", artist: "Dua Lipa", colors: [.teal, .purple]),
        .init(id: 29, title: "Chemical", artist: "Post Malone", colors: [.yellow, .green]),
        .init(id: 30, title: "Sunroof", artist: "Nicky Youre", colors: [.orange, .cyan]),
        .init(id: 31, title: "Easy On Me", artist: "Adele", colors: [.indigo, .gray]),
        .init(id: 32, title: "Shivers", artist: "Ed Sheeran", colors: [.red, .pink]),
        .init(id: 33, title: "Nonsense", artist: "Sabrina Carpenter", colors: [.mint, .purple]),
        .init(id: 34, title: "Late Night Talking", artist: "Harry Styles", colors: [.orange, .blue]),
        .init(id: 35, title: "Lavender Haze", artist: "Taylor Swift", colors: [.purple, .indigo]),
        .init(id: 36, title: "About Damn Time", artist: "Lizzo", colors: [.yellow, .pink]),
        .init(id: 37, title: "Karma", artist: "Taylor Swift", colors: [.cyan, .indigo]),
        .init(id: 38, title: "Woman", artist: "Doja Cat", colors: [.red, .purple]),
        .init(id: 39, title: "Snap", artist: "Rosa Linn", colors: [.mint, .blue]),
        .init(id: 40, title: "abcdefu", artist: "GAYLE", colors: [.black, .pink])
    ]
}

private struct SongSquare: View {
    let song: DemoSong
    let isPlaying: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: song.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 58, height: 58)
                .offset(x: 36, y: -34)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPlaying ? .white.opacity(0.82) : .clear, lineWidth: 2)
        }
    }
}

#Preview {
    ContentView()
}
