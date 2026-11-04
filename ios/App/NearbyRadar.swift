import SwiftUI

struct NearbyRadar:View {
    @ObservedObject var hub:NearbyHub
    @State private var selected:NearbyAgent?
    @State private var page=0
    @State private var batchBusy=false
    @State private var error:String?
    @State private var editingGroups=false
    @State private var checked:Set<String>=[]
    @State private var groupName=""
    @State private var targetGroup="默认组"
    @State private var renameDevice:NearbyAgent?
    @State private var deviceName=""
    @State private var showRename=false
    @Environment(\.scenePhase) private var scenePhase
    private var devices:[NearbyAgent]{hub.agents.filter{!$0.demo}}
    private var pageSize:Int{devices.count>6 ? 10:6}
    private var pages:Int{max(1,(devices.count+pageSize-1)/pageSize)}
    private var visible:[NearbyAgent]{Array(devices.dropFirst(min(page,pages-1)*pageSize).prefix(pageSize))}
    private func open(_ agent:NearbyAgent){
        guard !hub.connecting.contains(agent.id) else{return}
        if agent.client.connected{selected=agent;return}
        Task{@MainActor in if await hub.connect(agent){selected=agent}else{error=agent.name+"："+agent.connection}}
    }
    private func connectAll(){
        batchBusy=true
        let targets=devices.filter{!$0.client.connected && ($0.approved || $0.available) && !hub.connecting.contains($0.id)}
        Task{@MainActor in defer{batchBusy=false};let failed=await hub.connectAll(targets);if !failed.isEmpty{error="连接失败："+failed.joined(separator:"、")+"。点击上方设备重试。"}}
    }
    @ViewBuilder private func deviceMenu(_ agent:NearbyAgent) -> some View {
        Button("重命名设备",systemImage:"pencil"){renameDevice=agent;deviceName=agent.name;showRename=true}
        Button("移动到分组",systemImage:"folder"){checked=[agent.id];groupName="";targetGroup=hub.group(of:agent.id);editingGroups=true}.disabled(!agent.client.connected)
    }
    var body:some View {
        NavigationStack{
            ScrollView{
                VStack(spacing:18){
                    HStack{
                        Button("连接全部",systemImage:"link"){connectAll()}.disabled(batchBusy || devices.filter{!$0.client.connected && ($0.approved || $0.available)}.isEmpty)
                        Spacer()
                        Button("设备与分组",systemImage:"folder.badge.plus"){checked=[];groupName="";targetGroup="默认组";editingGroups=true}.disabled(devices.isEmpty)
                        Button("管理分组",systemImage:"folder"){groupName="";targetGroup="默认组";editingGroups=true}.disabled(hub.deviceGroups.isEmpty)
                    }.buttonStyle(.bordered).controlSize(.small).disabled(batchBusy)
                    GeometryReader{geo in
                        let center=CGPoint(x:geo.size.width/2,y:150)
                        ZStack{
                            ForEach([50,100,150],id:\.self){radius in RadarRing(radius:CGFloat(radius),width:geo.size.width)}
                            VStack(spacing:4){AoraAnimatedAvatar(phase:"idle",active:true,shape:"blob").frame(width:64,height:64);Text("Aora").font(.caption2)}.position(center)
                            ForEach(Array(visible.enumerated()),id:\.element.id){index,agent in
                                let angle:Double=Double(index) * (2 * .pi / Double(max(visible.count,1))) - .pi/2
                                let orbSize:CGFloat=devices.count>6 ? 42:62
                                let orbX:CGFloat=center.x + cos(angle) * min(geo.size.width*0.39,148)
                                let orbY:CGFloat=center.y + sin(angle) * 140
                                Button{open(agent)}label:{DeviceOrb(agent:agent,size:orbSize)}
                                    .buttonStyle(.plain)
                                    .contextMenu{deviceMenu(agent)}
                                    .position(x:orbX,y:orbY)
                            }
                        }
                    }.frame(height:300)
                    HStack{Button{page=max(0,page-1)}label:{Label("上一页",systemImage:"chevron.left")}.disabled(page==0);Spacer();Text("第 \(page+1) / \(pages) 页").font(.caption).foregroundStyle(.secondary);Spacer();Button{page=min(pages-1,page+1)}label:{Label("下一页",systemImage:"chevron.right")}.disabled(page>=pages-1)}
                    if let error{Text(error).font(.caption).foregroundStyle(.orange)}
                    if devices.filter({$0.client.connected}).isEmpty && devices.isEmpty {Text("暂无设备").font(.caption).foregroundStyle(.secondary)}
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:160))],spacing:14){
                        ForEach(devices.filter{$0.client.connected}){agent in
                            Button{selected=agent}label:{
                                VStack(alignment:.leading,spacing:10){
                                    HStack{Text(agent.name).lineLimit(1);Spacer();Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}
                                    Text(hub.group(of:agent.id)).font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing:5){ForEach(agent.client.snapshot.tasks.prefix(3)){task in Text(task).font(.caption).lineLimit(1).padding(.horizontal,6).padding(.vertical,3).background(Color(uiColor:.secondarySystemBackground),in:Capsule())};if agent.client.snapshot.tasks.count>3{Text("+\(agent.client.snapshot.tasks.count-3)").font(.caption).foregroundStyle(.secondary)}}
                                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:18))
                            }.buttonStyle(.plain).contextMenu{deviceMenu(agent)}
                        }
                    }
                    VStack(alignment:.leading,spacing:12){
                        Text("未连接的设备").font(.headline)
                        if devices.filter({!$0.client.connected}).isEmpty {Text("没有未连接的设备").font(.caption).foregroundStyle(.secondary)}
                        ForEach(devices.filter{!$0.client.connected}){agent in
                            HStack(spacing:12){
                                DeviceOrb(agent:agent,size:52)
                                VStack(alignment:.leading,spacing:4){Text(agent.name).font(.headline).lineLimit(1);Text(hub.group(of:agent.id)).font(.caption).foregroundStyle(.secondary)}
                                Spacer()
                                if agent.available && !hub.connecting.contains(agent.id){Button("连接",systemImage:"link"){open(agent)}.buttonStyle(.borderedProminent)}
                                if hub.connecting.contains(agent.id){ProgressView().controlSize(.small)}
                            }.padding(.vertical,6).contextMenu{deviceMenu(agent)}
                        }
                    }
                }.padding(18)
            }
            .navigationTitle("附近").toolbar{ToolbarItem(placement:.primaryAction){Button("刷新",systemImage:"arrow.clockwise"){Task{await hub.refresh()}}}}
            .sheet(item:$selected){agent in DeviceWorkspace(hub:hub,initialDevice:agent.id,singleDevice:false,onLeave:{selected=nil})}
            .sheet(isPresented:$editingGroups){NavigationStack{GroupEditor(hub:hub,checked:$checked,groupName:$groupName,targetGroup:$targetGroup)}}
            .alert("设备名称",isPresented:$showRename){TextField("名称",text:$deviceName);Button("取消",role:.cancel){renameDevice=nil};Button("保存"){if let agent=renameDevice{hub.rename(agent,to:deviceName)};renameDevice=nil}}
            .onChange(of:scenePhase){phase in if phase == .active{Task{await hub.refresh()}}}
        }
    }
}
struct RadarRing:View {
    var radius:CGFloat
    var width:CGFloat
    var body:some View {
        Circle().stroke(Color.mint.opacity(0.16),lineWidth:1.2).frame(width:radius*2,height:radius*2).position(x:width/2,y:150)
    }
}
struct DeviceOrb:View {
    @ObservedObject var agent:NearbyAgent
    var size:CGFloat=64
    var body:some View {
        ZStack {
            if agent.client.connected {Circle().fill(Color.mint.opacity(0.12)).frame(width:size+14,height:size+14)}
            AoraAnimatedAvatar(phase:agent.phase,active:agent.client.connected,shape:agent.avatarShape,hue:agent.avatarHue).frame(width:size,height:size)
            if agent.client.connected {Circle().fill(.green).frame(width:10,height:10).offset(x:size/2-4,y:-size/2+4)}
            if agent.client.snapshot.busy {Text("处理中").font(.system(size:9,weight:.bold)).padding(.horizontal,6).padding(.vertical,2).background(.orange,in:Capsule()).offset(y:size/2+12)}
        }.frame(width:size+14,height:size+14).contentShape(Circle())
    }
}
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
