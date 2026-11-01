import SwiftUI
import StrandDesign
import WhoopStore

/// The Coach conversations (personal fork, Coach mockup 4), presented as a sheet from the header's
/// left button: pinned first, then by day, with a search over titles and messages.
///
/// Opening, renaming, pinning and deleting all go through `AICoachEngine`, which writes the store and
/// reloads `conversations`. The previews are read once per change of that list
/// (`conversationDigests()`), so the list itself never waits on the store.
struct CoachHistoryView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var digests: [String: CoachConversationDigest] = [:]
    @State private var pendingDelete: CoachConversationRow?
    @State private var renaming: CoachConversationRow?
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            NoopLiquidGlassSearchField(text: $query,
                                       prompt: String(localized: "Search conversations"))
            content
        }
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560, idealHeight: 640)
        #endif
        // Rebuilt whenever the list changes (a save, a rename, a pin, a delete), so a preview follows
        // the conversation's latest answer.
        .task(id: coach.conversations) {
            digests = await coach.conversationDigests()
        }
        .confirmationDialog("Delete this conversation?",
                            isPresented: deleteBinding,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { row in
            Button("Delete", role: .destructive) { coach.deleteConversation(id: row.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is removed from this device and from your conversations.")
        }
        .alert("Rename conversation", isPresented: renameBinding) {
            TextField("Name", text: $renameDraft)
            Button("Rename") {
                if let row = renaming { coach.renameConversation(id: row.id, to: renameDraft) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Conversations")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                coach.startNewConversation()
                dismiss()
            } label: {
                Label("New", systemImage: "square.and.pencil")
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .padding(.leading, 12)
                    .padding(.trailing, 16)
                    .frame(minHeight: 44)
                    .overlay(Capsule(style: .continuous)
                        .strokeBorder(StrandPalette.accent.opacity(0.5), lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(coach.sending)
            .accessibilityLabel(Text("New conversation"))
            #if os(macOS)
            // A Mac sheet has no swipe to close it.
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.accent)
                .padding(.leading, 8)
            #endif
        }
    }

    // MARK: List

    /// The sections left after the search, each with only its matching rows.
    private var visibleSections: [CoachHistory.Section] {
        let rows = coach.conversations.filter {
            CoachHistory.matches(title: $0.title, text: digests[$0.id]?.searchText, query: query)
        }
        return CoachHistory.sections(rows, now: Date())
    }

    @ViewBuilder
    private var content: some View {
        let sections = visibleSections
        if coach.conversations.isEmpty {
            emptyMessage(symbol: "bubble.left.and.bubble.right",
                         title: Text("No conversations yet"),
                         detail: Text("Your questions and briefs are kept here, newest first."))
        } else if sections.isEmpty {
            emptyMessage(symbol: "magnifyingglass",
                         title: Text("No results"),
                         detail: Text("No conversation matches “\(query)”."))
        } else {
            List {
                ForEach(sections) { section in
                    sectionTitle(section.group)
                    ForEach(section.rows, id: \.id) { row in
                        conversationRow(row, group: section.group)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .padding(.horizontal, -NoopMetrics.screenHPadding)
        }
    }

    private func sectionTitle(_ group: CoachHistory.Group) -> some View {
        Text(groupTitle(group))
            .font(StrandFont.overline)
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: NoopMetrics.screenHPadding,
                                      bottom: 0, trailing: NoopMetrics.screenHPadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(.isHeader)
    }

    private func groupTitle(_ group: CoachHistory.Group) -> LocalizedStringKey {
        switch group {
        case .pinned: return "Pinned"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .earlier: return "Earlier"
        }
    }

    private func conversationRow(_ row: CoachConversationRow, group: CoachHistory.Group) -> some View {
        let digest = digests[row.id]
        let isBrief = digest?.isBrief ?? false
        return Button {
            Task {
                await coach.openConversation(id: row.id)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                CoachHistoryIcon(isBrief: isBrief)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title.isEmpty ? String(localized: "New conversation") : row.title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                    if let preview = digest?.preview, !preview.isEmpty {
                        Text(preview)
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeLabel(row, group: group))
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if row.pinned {
                        Image(systemName: "pin.fill")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .accessibilityLabel(Text("Pinned"))
                    }
                }
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(coach.sending)
        .listRowInsets(EdgeInsets(top: 0, leading: NoopMetrics.screenHPadding,
                                  bottom: 0, trailing: NoopMetrics.screenHPadding))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        // No destructive role on the swipe: the delete waits for the confirmation, and a destructive
        // swipe animates the row away before anyone has confirmed.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                pendingDelete = row
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(StrandPalette.statusCritical)
            Button {
                coach.setConversationPinned(id: row.id, pinned: !row.pinned)
            } label: {
                Label(row.pinned ? "Unpin" : "Pin", systemImage: row.pinned ? "pin.slash" : "pin")
            }
            .tint(StrandPalette.textTertiary)
        }
        .contextMenu {
            Button {
                renameDraft = row.title
                renaming = row
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                coach.setConversationPinned(id: row.id, pinned: !row.pinned)
            } label: {
                Label(row.pinned ? "Unpin" : "Pin", systemImage: row.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                pendingDelete = row
            } label: {
                Label("Delete conversation", systemImage: "trash")
            }
        }
    }

    /// The row's time, written the way `CoachHistory.timeStyle` says for its group.
    private func timeLabel(_ row: CoachConversationRow, group: CoachHistory.Group) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
        switch CoachHistory.timeStyle(for: group) {
        case .hourMinute: return AppClock.hourMinuteFormatter().string(from: date)
        case .weekday: return date.formatted(.dateTime.weekday(.abbreviated))
        case .dayMonth: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    private func emptyMessage(symbol: String, title: Text, detail: Text) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityHidden(true)
            title
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            detail
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: Prompts

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}

/// The round mark in front of a conversation: a sun for a brief, a bubble for a question. The theme of
/// the mockup's icons (dumbbell, moon) is not stored, so a question always gets the bubble.
private struct CoachHistoryIcon: View {
    let isBrief: Bool

    var body: some View {
        let tint = isBrief ? StrandPalette.metricAmber : StrandPalette.textSecondary
        Image(systemName: isBrief ? "sun.max.fill" : "bubble.left")
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(isBrief ? 0.16 : 0.12), in: Circle())
            .accessibilityHidden(true)
    }
}
