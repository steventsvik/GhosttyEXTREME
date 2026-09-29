#if os(macOS)
import AppKit
import SwiftUI

extension ReviewInbox {
    static func toggle() {
        if AgentToolWindows.isOpen(windowID) {
            AgentToolWindows.close(id: windowID)
        } else {
            show()
        }
    }

    static func show(selecting item: ReviewItem? = nil) {
        if let item { ReviewSelection.shared.itemID = item.id }
        AgentToolWindows.show(id: windowID, title: "Review Changes", size: NSSize(width: 1240, height: 780)) {
            ReviewInboxView()
        }
    }
}

/// Which item and file the review window shows. Shared so "Review" buttons elsewhere can
/// open the window on a specific item.
final class ReviewSelection: ObservableObject {
    static let shared = ReviewSelection()
    @Published var itemID: UUID?
    @Published var filePath: String?
}

private enum ReviewColors {
    static let added = Color(red: 0.25, green: 0.85, blue: 0.5)
    static let removed = Color(red: 1.0, green: 0.4, blue: 0.42)
    static let accent = Color(red: 0.62, green: 0.45, blue: 1.0)

    static func status(_ status: ReviewFile.Status) -> Color {
        switch status {
        case .added: return added
        case .modified: return Color(red: 0.4, green: 0.65, blue: 1.0)
        case .deleted: return removed
        case .renamed: return accent
        }
    }
}

private struct ReviewInboxView: View {
    @ObservedObject private var inbox = ReviewInbox.shared
    @ObservedObject private var selection = ReviewSelection.shared

    private var item: ReviewItem? {
        inbox.items.first { $0.id == selection.itemID } ?? inbox.items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if inbox.items.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    itemList.frame(width: 270)
                    Divider()
                    if let item {
                        ReviewItemView(item: item)
                    }
                }
            }
        }
        .frame(minWidth: 880, minHeight: 520)
        .onAppear { if let item { inbox.markSeen(item) } }
        .onChange(of: selection.itemID) { _ in if let item { inbox.markSeen(item) } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [ReviewColors.accent, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "tray.full.fill").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: ReviewColors.accent.opacity(0.4), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Changes").font(.system(size: 17, weight: .bold))
                Text(inbox.items.isEmpty ? "Nothing waiting" :
                        "\(inbox.items.count) agent\(inbox.items.count == 1 ? "" : "s") with changes · \(inbox.unseenCount) new")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42))
                .foregroundStyle(LinearGradient(colors: [ReviewColors.added, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("All caught up").font(.system(size: 16, weight: .semibold))
            Text("When Claude Code or Codex finishes working in a git repository, its changes show up here to review: comment on lines and send them back, undo files, commit, or open a pull request.")
                .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(inbox.items) { entry in
                    ReviewItemRow(item: entry, selected: entry.id == item?.id)
                        .onTapGesture {
                            selection.itemID = entry.id
                            selection.filePath = nil
                        }
                }
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.025))
    }
}

private struct ReviewItemRow: View {
    let item: ReviewItem
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(item.agent.brandColor)
                    VerticalTabAgentLogo(kind: item.agent, tint: item.agent.glyphOnBrand).frame(width: 11, height: 11)
                }
                .frame(width: 22, height: 22)
                Text(item.repoName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if item.unseen && item.stage == .ready {
                    Circle().fill(ReviewColors.accent).frame(width: 7, height: 7)
                }
            }
            if let task = item.task {
                Text(task).font(.system(size: 11.5)).foregroundColor(.primary.opacity(0.8)).lineLimit(2)
            }
            HStack(spacing: 6) {
                stageChip
                Text("\(item.files.count) file\(item.files.count == 1 ? "" : "s")").foregroundColor(.secondary)
                Text("+\(item.added)").foregroundColor(ReviewColors.added)
                Text("−\(item.removed)").foregroundColor(ReviewColors.removed)
                Spacer(minLength: 0)
                Text(RelativeDateTimeFormatter().localizedString(for: item.updated, relativeTo: Date()))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 10.5).monospacedDigit())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? ReviewColors.accent.opacity(0.16) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? ReviewColors.accent.opacity(0.7) : Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var stageChip: some View {
        let (label, color): (String, Color) = {
            switch item.stage {
            case .ready: return ("Ready", ReviewColors.added)
            case .feedbackSent: return ("Feedback sent", .orange)
            case .working: return ("Working", Color(red: 0.36, green: 0.62, blue: 1.0))
            }
        }()
        Text(label)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

// MARK: - One agent's changes

private struct ReviewItemView: View {
    let item: ReviewItem
    @ObservedObject private var selection = ReviewSelection.shared
    @State private var commitMessage = ""
    @State private var showCommit = false
    @State private var message: String?

    private var file: ReviewFile? {
        item.files.first { $0.path == selection.filePath } ?? item.files.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                fileList.frame(width: 250)
                Divider()
                if let file {
                    ReviewDiffView(item: item, file: file)
                } else {
                    Spacer()
                }
            }
            Divider()
            actionBar
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                if let task = item.task {
                    Text(task).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                }
                Text((item.repoRoot as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10.5, design: .monospaced)).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(item.files) { entry in
                        ReviewFileRow(item: item, file: entry, selected: entry.path == file?.path)
                            .onTapGesture { selection.filePath = entry.path }
                    }
                }
                .padding(6)
            }
        }
        .background(Color.primary.opacity(0.02))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let message {
                Text(message).font(.system(size: 11.5)).foregroundColor(.orange).lineLimit(2).textSelection(.enabled)
            } else {
                let reviewed = item.files.filter { item.decision($0) == .accepted }.count
                Text("\(reviewed)/\(item.files.count) files approved · \(item.comments.count) comment\(item.comments.count == 1 ? "" : "s")")
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            Spacer()
            if ReviewInbox.shared.surface(for: item) != nil {
                Button { ReviewInbox.shared.focusAgent(item) } label: { Label("Go to agent", systemImage: "arrow.right.circle") }
            }
            Button { ReviewInbox.shared.openPullRequest(item) } label: { Label("Pull request", systemImage: "arrow.triangle.pull") }
                .help("Push this branch and open GitHub's pull request page (in a new tab)")
            Button { showCommit = true } label: { Label("Commit…", systemImage: "checkmark.circle") }
                .popover(isPresented: $showCommit, arrowEdge: .top) { commitPopover }
            Button { ReviewInbox.shared.acceptAll(item) } label: { Label("Looks good", systemImage: "hand.thumbsup.fill") }
                .help("Accept everything; the next review starts from here")
            sendButton
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private var sendButton: some View {
        let count = item.comments.count
        let canSend = count > 0 && ReviewInbox.shared.surface(for: item) != nil
        return Button {
            if !ReviewInbox.shared.sendFeedback(item) {
                message = "The agent's tab is closed, so the feedback can't be sent. Copy it from a comment instead."
            } else {
                message = nil
                ReviewInbox.shared.focusAgent(item)
            }
        } label: {
            HStack(spacing: 6) {
                VerticalTabAgentLogo(kind: item.agent, tint: .white).frame(width: 12, height: 12)
                Text(count == 0 ? "Send feedback" : "Send \(count) comment\(count == 1 ? "" : "s") to \(item.agent.displayName)")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                Capsule().fill(canSend
                    ? AnyShapeStyle(LinearGradient(colors: [item.agent == .codex ? Color(red: 0.06, green: 0.64, blue: 0.5) : item.agent.brandColor, ReviewColors.accent],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.gray.opacity(0.35))))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(count == 0 ? "Add comments on lines first (hover a line and click +)" : "Types your comments into the agent's prompt and sends them")
    }

    private var commitPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commit \(item.files.count) file\(item.files.count == 1 ? "" : "s")").font(.system(size: 13, weight: .semibold))
            TextEditor(text: $commitMessage)
                .font(.system(size: 12))
                .frame(width: 340, height: 90)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
            HStack {
                Spacer()
                Button("Cancel") { showCommit = false }
                Button("Commit") {
                    ReviewInbox.shared.commit(item, message: commitMessage) { error in
                        message = error.map { "Commit failed: \($0)" }
                        showCommit = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .onAppear { if commitMessage.isEmpty { commitMessage = item.task ?? "" } }
    }
}

private struct ReviewFileRow: View {
    let item: ReviewItem
    let file: ReviewFile
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(file.status.rawValue)
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .foregroundColor(.black.opacity(0.75))
                .frame(width: 15, height: 15)
                .background(RoundedRectangle(cornerRadius: 3.5).fill(ReviewColors.status(file.status)))
            VStack(alignment: .leading, spacing: 0) {
                Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if !file.folder.isEmpty {
                    Text(file.folder).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            let comments = item.comments(on: file).count
            if comments > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "text.bubble.fill")
                    Text("\(comments)")
                }
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(ReviewColors.accent)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("+\(file.added)").foregroundColor(ReviewColors.added)
                Text("−\(file.removed)").foregroundColor(ReviewColors.removed)
            }
            .font(.system(size: 9.5).monospacedDigit())
            Image(systemName: item.decision(file) == .accepted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(item.decision(file) == .accepted ? ReviewColors.added : .secondary.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? ReviewColors.accent.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }
}

// MARK: - Diff with comments

private struct ReviewDiffView: View {
    let item: ReviewItem
    let file: ReviewFile
    @State private var composing: ReviewComment.Anchor?
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(file.status.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black.opacity(0.75))
                    .frame(width: 17, height: 17)
                    .background(RoundedRectangle(cornerRadius: 4).fill(ReviewColors.status(file.status)))
                Text(file.path).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                if let old = file.oldPath {
                    Text("← \(old)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    confirmUndo()
                } label: { Label("Undo file", systemImage: "arrow.uturn.backward") }
                    .help("Put this file back the way it was before the agent changed it")
                let accepted = item.decision(file) == .accepted
                Button {
                    ReviewInbox.shared.setDecision(accepted ? .pending : .accepted, for: file, in: item)
                    if !accepted { selectNextFile() }
                } label: {
                    Label(accepted ? "Approved" : "Approve", systemImage: accepted ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .tint(ReviewColors.added)
                .buttonStyle(.borderedProminent)
                .opacity(accepted ? 1 : 0.9)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if file.isBinary {
                Text("Binary file changed.").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(file.hunks) { hunk in
                            Text(hunk.header)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(ReviewColors.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(ReviewColors.accent.opacity(0.08))
                            ForEach(hunk.lines) { line in
                                ReviewLineRow(line: line) {
                                    composing = line.anchor
                                    draft = ""
                                }
                                ForEach(item.comments(on: file).filter { $0.anchor == line.anchor }) { comment in
                                    commentBubble(comment)
                                }
                                if composing == line.anchor {
                                    composer(for: line)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func commentBubble(_ comment: ReviewComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient(colors: [ReviewColors.accent, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "person.fill").font(.system(size: 9)).foregroundColor(.white)
            }
            .frame(width: 20, height: 20)
            Text(comment.text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer()
            Button { ReviewInbox.shared.removeComment(comment, in: item) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(ReviewColors.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReviewColors.accent.opacity(0.5)))
        .padding(.leading, 96).padding(.trailing, 14).padding(.vertical, 4)
    }

    private func composer(for line: ReviewLine) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .frame(height: 64)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ReviewColors.accent.opacity(0.7), lineWidth: 1.2))
            HStack {
                Text("Line \(line.anchor.line) · sent to \(item.agent.displayName) with your other comments")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { composing = nil }
                Button("Add comment") {
                    ReviewInbox.shared.addComment(draft, on: line, file: file, in: item)
                    composing = nil
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(ReviewColors.accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .padding(.leading, 96).padding(.trailing, 14).padding(.vertical, 4)
    }

    private func selectNextFile() {
        guard let index = item.files.firstIndex(of: file) else { return }
        let rest = item.files[(index + 1)...] + item.files[..<index]
        if let next = rest.first(where: { item.decision($0) != .accepted && $0.path != file.path }) {
            ReviewSelection.shared.filePath = next.path
        }
    }

    private func confirmUndo() {
        let alert = NSAlert()
        alert.messageText = "Undo the agent's changes to \(file.name)?"
        alert.informativeText = file.status == .added
            ? "The file was created by the agent and will be deleted."
            : "The file goes back to how it was before the agent started. Other files aren't touched."
        alert.addButton(withTitle: "Undo file")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ReviewInbox.shared.undo(file, in: item)
    }
}

private struct ReviewLineRow: View {
    let line: ReviewLine
    let onComment: () -> Void
    @State private var hovering = false

    var body: some View {
        let color: Color? = line.kind == .added ? ReviewColors.added : line.kind == .removed ? ReviewColors.removed : nil
        HStack(spacing: 0) {
            ZStack {
                Text(line.oldNumber.map(String.init) ?? "")
                    .frame(width: 38, alignment: .trailing)
                    .opacity(hovering ? 0 : 1)
                if hovering {
                    Button(action: onComment) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 17, height: 17)
                            .background(RoundedRectangle(cornerRadius: 4).fill(ReviewColors.accent))
                    }
                    .buttonStyle(.plain)
                    .help("Comment on this line")
                }
            }
            .frame(width: 42)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 38, alignment: .trailing)
            Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                .foregroundColor(color ?? .secondary)
                .frame(width: 16)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundColor(.primary.opacity(line.kind == .context ? 0.72 : 0.95))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.vertical, 1)
        .background((color ?? .clear).opacity(hovering ? 0.2 : 0.11))
        .overlay(alignment: .leading) {
            if let color { Rectangle().fill(color).frame(width: 2.5) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Sidebar

/// Sidebar header button: opens the review window, with the number of new reviews.
struct ReviewHeaderButton: View {
    @ObservedObject private var inbox = ReviewInbox.shared
    @State private var hovering = false

    var body: some View {
        Button(action: ReviewInbox.toggle) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: inbox.items.isEmpty ? "tray" : "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(inbox.unseenCount > 0
                        ? AnyShapeStyle(LinearGradient(colors: [ReviewColors.accent, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.primary))
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.14), lineWidth: 1))
                if inbox.unseenCount > 0 {
                    Text("\(inbox.unseenCount)")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Circle().fill(ReviewColors.accent))
                        .offset(x: 4, y: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Review changes (⌃⌘I)")
    }
}

/// "Review 3 files" on a pane's row when its agent has changes waiting.
struct ReviewPaneChip: View {
    let surface: Ghostty.SurfaceView?
    @ObservedObject private var inbox = ReviewInbox.shared

    var body: some View {
        if let surface, let item = inbox.item(for: surface), item.stage == .ready {
            Button {
                ReviewInbox.show(selecting: item)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tray.full.fill").font(.system(size: 8.5, weight: .bold))
                    Text("Review \(item.files.count)")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(Capsule().fill(LinearGradient(colors: [ReviewColors.accent, .pink], startPoint: .leading, endPoint: .trailing)))
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Review this agent's changes")
        }
    }
}
#endif
