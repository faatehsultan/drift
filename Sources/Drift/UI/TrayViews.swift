import SwiftUI
import AppKit

struct TrayView: View {
    let model: NotchModel
    @ObservedObject var tray: TrayModel

    var body: some View {
        let items = tray.visibleItems
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Chip(title: "Shelf · \(tray.shelfCount)", on: !tray.showPocket) {
                    withAnimation(Anim.quick) { tray.showPocket = false }
                }
                Chip(title: "Pocket · \(tray.pocketCount)", on: tray.showPocket) {
                    withAnimation(Anim.quick) { tray.showPocket = true }
                }
                Spacer(minLength: 0)
                if !items.isEmpty {
                    if tray.visiblePDFs.count >= 2 {
                        SmallButton(title: "Merge PDFs", icon: "doc.on.doc") { tray.mergeVisiblePDFs() }
                    }
                    SmallButton(title: "AirDrop", icon: "paperplane") { tray.airdrop(items.map { $0.url }) }
                    SmallButton(title: "Clear", icon: "trash") { withAnimation(Anim.quick) { tray.clearVisible() } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if items.isEmpty {
                DropZone(pocket: tray.showPocket)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(items) { i in FileTile(item: i, tray: tray) }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let t = tray.toast {
                Text(t).font(.system(size: 11)).foregroundColor(.dim).lineLimit(1).transition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DropZone: View {
    let pocket: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .medium)).foregroundColor(.white.opacity(0.5))
            Text(pocket ? "Pocket is empty" : "Drop files here").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            Text(pocket ? "Use ··· on a file to keep it here for good." : "Drag files onto the notch from anywhere. They clear after a day.")
                .font(.system(size: 11))
                .foregroundColor(.dim)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .padding(.horizontal, 16)
    }
}

struct ThumbView: View {
    @ObservedObject var thumb: FileThumb
    var body: some View {
        Image(nsImage: thumb.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct FileTile: View {
    let item: TrayItem
    @ObservedObject var tray: TrayModel

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ThumbView(thumb: FileThumb.of(item.url)).frame(width: 64, height: 64)
                if tray.busy.contains(item.id) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.55))
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 64, height: 64)
            Text(item.name)
                .font(.system(size: 11))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 84, height: 28, alignment: .top)
        }
        .padding(6)
        .background(HoverFill(selected: false, radius: 12))
        .overlay(alignment: .topTrailing) {
            Menu {
                TileMenu(item: item, tray: tray)
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(2)
        }
        .overlay(alignment: .topLeading) {
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(.yellow).padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { tray.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu { TileMenu(item: item, tray: tray) }
    }
}

struct TileMenu: View {
    let item: TrayItem
    let tray: TrayModel

    var body: some View {
        Button("Open") { tray.open(item) }
        Button("Show in Finder") { tray.reveal(item) }
        Button("AirDrop") { tray.airdrop([item.url]) }
        Button(item.pinned ? "Move to Shelf" : "Keep in Pocket") { tray.togglePin(item) }
        let actions = Converter.actions(for: item.url)
        if !actions.isEmpty {
            Menu("Convert to") {
                ForEach(actions) { a in
                    Button(a.title) { tray.convert(item, a) }
                }
            }
        }
        Divider()
        Button("Remove from tray") { tray.remove(item) }
    }
}
