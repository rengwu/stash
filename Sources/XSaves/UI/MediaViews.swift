import SwiftUI
import AVKit
import XSavesCore

struct MediaPlayer: NSViewRepresentable {
    let url: URL
    let looping: Bool
    var autoplay = false

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        if looping {
            let player = AVQueuePlayer()
            player.isMuted = true
            context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            view.controlsStyle = .none
            view.player = player
            player.play()
        } else {
            view.controlsStyle = .inline
            view.player = AVPlayer(url: url)
            if autoplay { view.player?.play() }
        }
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {}
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
        view.player = nil
    }
}

struct Gallery: View {
    let items: [MediaView]
    let maxHeight: CGFloat
    @ViewState private var index = 0
    /// A video shows its poster and a play button until clicked, rather than a blank first frame.
    @ViewState private var playing = false
    @FocusState private var focused: Bool
    var body: some View {
        if let first = items.first, items.indices.contains(index), let file = items[index].file {
            ZStack {
                switch items[index].type {
                case .photo: Thumbnail(url: file, mode: .fit)
                case .animatedGIF: MediaPlayer(url: file, looping: true).id(file)
                case .video:
                    if playing { MediaPlayer(url: file, looping: false, autoplay: true).id(file) }
                    else {
                        Button { playing = true } label: {
                            Thumbnail(url: items[index].poster, mode: .fit).overlay {
                                Image(systemName: "play.fill").font(.title).foregroundStyle(.white)
                                    .frame(width: 56, height: 56).background(.black.opacity(0.5), in: Circle())
                            }
                        }
                        .buttonStyle(.plain).accessibilityLabel("Play video")
                    }
                }
            }
            .aspectRatio(1 / first.heightRatio, contentMode: .fit)
            .frame(maxHeight: maxHeight)
            .overlay {
                if items.count > 1 {
                    HStack {
                        pageButton(-1)
                        Spacer()
                        pageButton(1)
                    }.padding(.horizontal, 7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if items.count > 1 {
                    Text("\(index + 1) / \(items.count)").font(.caption.monospacedDigit()).padding(5)
                        .foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule()).padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.separator) }
            .focusable(items.count > 1)
            .focused($focused)
            .simultaneousGesture(TapGesture().onEnded { focused = true })
            .onKeyPress(.leftArrow) { page(-1); return .handled }
            .onKeyPress(.rightArrow) { page(1); return .handled }
        }
    }
    private func pageButton(_ delta: Int) -> some View {
        Button { focused = true; page(delta) } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right").frame(width: 18, height: 22)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityLabel(delta < 0 ? "Previous item" : "Next item")
    }
    private func page(_ delta: Int) {
        index = (index + delta + items.count) % items.count
        playing = false
    }
}
