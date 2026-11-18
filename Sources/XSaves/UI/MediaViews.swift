import SwiftUI
import AVKit
import XSavesCore

struct MediaPlayer: NSViewRepresentable {
    let url: URL
    let looping: Bool

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
    @ViewState private var index = 0
    @FocusState private var focused: Bool
    var body: some View {
        if let first = items.first, items.indices.contains(index), let file = items[index].file {
            ZStack {
                if items[index].type == .photo { Thumbnail(url: file) }
                else { MediaPlayer(url: file, looping: items[index].type == .animatedGIF).id(file) }
            }
            .aspectRatio(1 / first.heightRatio, contentMode: .fit)
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
    private func page(_ delta: Int) { index = (index + delta + items.count) % items.count }
}
