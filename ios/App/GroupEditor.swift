import SwiftUI

struct GroupEditor: View {
    @ObservedObject var hub: NearbyHub
    @Binding var checked: Set<String>
    @Binding var groupName: String
    @Binding var targetGroup: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("目标分组") {
                Picker("目标分组", selection: $targetGroup) {
                    ForEach(hub.groupNames, id: \.self) { name in Text(name).tag(name) }
                    if !hub.groupNames.contains(targetGroup) && targetGroup != "__new__" { Text(targetGroup).tag(targetGroup) }
                    Text("新建组").tag("__new__")
                }
                if targetGroup == "__new__" {
                    TextField("新组名称", text: $groupName)
                }
            }
            Section("已选设备") {
                ForEach(Array(checked).sorted(), id: \.self) { id in
                    Text(hub.agents.first(where: { $0.id == id })?.name ?? id)
                }
            }
            Section {
                Button("移动 \(checked.count) 台") {
                    let name = targetGroup == "__new__" ? groupName.trimmingCharacters(in: .whitespacesAndNewlines) : targetGroup
                    guard !name.isEmpty else { return }
                    for id in checked { hub.setGroup(id, name: name) }
                    dismiss()
                }.disabled(checked.isEmpty)
            }
        }
        .navigationTitle("编辑分组")
    }
}
