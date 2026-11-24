import SwiftUI
import CoreData

// MARK: - 标签色板

/// 标签预设颜色（与统计页 `Color(hex:)` 解析共用同一格式）
enum TagPalette {
    static let colors: [String] = [
        "#E5484D", // 红
        "#E9A13B", // 橙
        "#3B82F6", // 蓝
        "#22A06B", // 绿
        "#8B5CF6", // 紫
        "#14B8A6"  // 青
    ]
}

// MARK: - TagEditorView
//
// 可复用标签编辑器（用户反馈 2026-11-19）：任务创建页与详情页共用。
// - 全量标签 chips 多选（点按切换选中态）；
// - 内联「新建标签」：名称 + 6 色色板，创建后自动选中；
// - 长按 chip 弹出重命名 / 删除（删除为 Nullify：任务解除关联、专注数据保留）。
// 选择态只持有 `Tag.id`，保存时经 `TagViewModel.resolveTags(ids:)` 解析，
// 避免 View 直接改 NSManagedObject（架构约定：一律走 Service/VM）。

struct TagEditorView: View {
    @EnvironmentObject var tagViewModel: TagViewModel
    @EnvironmentObject var l10n: L10n

    /// 选中标签的 id 集合（Binding 由调用页持有）
    @Binding var selectedTagIDs: Set<UUID>

    // 新建标签
    @State private var showCreateField = false
    @State private var newTagName = ""
    @State private var newTagColorHex = TagPalette.colors[0]
    // 重命名 / 删除
    @State private var renamingTag: Tag?
    @State private var renameText = ""
    @State private var deletingTag: Tag?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipGrid
            if showCreateField {
                createRow
            }
        }
        // 重命名弹窗（iOS16+ alert 支持 TextField）
        .alert(L10n.shared.重命名, isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField(L10n.shared.标签名称, text: $renameText)
            Button(L10n.shared.取消, role: .cancel) { renamingTag = nil }
            Button(L10n.shared.确定) {
                if let tag = renamingTag {
                    tagViewModel.renameTag(tag, to: renameText)
                }
                renamingTag = nil
            }
        } message: {
            Text(L10n.shared.标签名称)
        }
        // 删除确认
        .alert(L10n.shared.删除标签, isPresented: Binding(
            get: { deletingTag != nil },
            set: { if !$0 { deletingTag = nil } }
        )) {
            Button(L10n.shared.取消, role: .cancel) { deletingTag = nil }
            Button(L10n.shared.删除, role: .destructive) {
                if let tag = deletingTag {
                    selectedTagIDs.remove(tag.id)
                    tagViewModel.deleteTag(tag)
                }
                deletingTag = nil
            }
        } message: {
            Text(L10n.shared.删除标签确认)
        }
    }

    // MARK: - Chips 网格

    private var chipGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tagViewModel.tags) { tag in
                tagChip(tag)
            }
            newTagChip
        }
    }

    private func tagChip(_ tag: Tag) -> some View {
        let isSelected = selectedTagIDs.contains(tag.id)
        let color = tag.colorHex.flatMap { Color(hex: $0) } ?? Color(hex: TagPalette.colors[0])
        return Button {
            if isSelected {
                selectedTagIDs.remove(tag.id)
            } else {
                selectedTagIDs.insert(tag.id)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(tag.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color.opacity(0.16) : Color.cardInsetFill)
            .overlay(
                Capsule().stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        // 无障碍：chip 朗读名称 + 选中态
        .accessibilityLabel(tag.name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        // 长按：重命名 / 删除
        .contextMenu {
            Button {
                renameText = tag.name
                renamingTag = tag
            } label: {
                Label(L10n.shared.重命名, systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingTag = tag
            } label: {
                Label(L10n.shared.删除标签, systemImage: "trash")
            }
        }
    }

    private var newTagChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                showCreateField.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showCreateField ? "xmark" : "plus")
                    .font(.caption2.weight(.semibold))
                Text(L10n.shared.新建标签)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .foregroundColor(.focusRed)
            .background(Color.cardInsetFill)
            .overlay(
                Capsule().stroke(Color.focusRed.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shared.新建标签)
    }

    // MARK: - 内联新建行

    private var createRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.shared.标签名称, text: $newTagName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.shared.标签名称)
                .onSubmit(createNewTag)

            // 色板
            HStack(spacing: 12) {
                ForEach(TagPalette.colors, id: \.self) { hex in
                    Button {
                        newTagColorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().strokeBorder(
                                    newTagColorHex == hex ? Color.primary.opacity(0.8) : Color.clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.shared.颜色)
                    .accessibilityAddTraits(newTagColorHex == hex ? .isSelected : [])
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button(L10n.shared.确定, action: createNewTag)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.cardInsetFill)
        .cornerRadius(10)
    }

    private func createNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let tag = tagViewModel.createTag(name: trimmed, colorHex: newTagColorHex) {
            selectedTagIDs.insert(tag.id)
        }
        newTagName = ""
        newTagColorHex = TagPalette.colors[0]
        showCreateField = false
    }
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var selected: Set<UUID> = []
        var body: some View {
            List {
                Section(L10n.shared.标签) {
                    TagEditorView(selectedTagIDs: $selected)
                }
            }
        }
    }
    return Demo()
        .environmentObject(TagViewModel(
            tagService: TagService(persistenceController: PersistenceController.preview),
            persistenceController: PersistenceController.preview
        ))
        .environmentObject(L10n.shared)
}
