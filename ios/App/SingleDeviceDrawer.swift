import SwiftUI

struct AgentHome:View {
    @ObservedObject var hub:NearbyHub
    var onDevices:()->Void
    var body:some View {
        if let first=hub.agents.first(where:{$0.approved || $0.demo}) {
            DeviceWorkspace(hub:hub,initialDevice:first.id,onLeave:onDevices)
        } else {
            NavigationStack {
                VStack { Image(systemName:"iphone.gen3").font(.largeTitle).foregroundStyle(.secondary); Text("暂无已连接设备").font(.headline); Text("在设备页面连接安卓后，这里显示全部 agent 和聊天。").font(.subheadline).foregroundStyle(.secondary) }
                    .navigationTitle("agent")
                    .toolbar{NavigationLink("模型",destination:ModelChatView())}
            }
        }
    }
}
struct SingleDeviceDrawer:View {
    @ObservedObject var agent:NearbyAgent
    @ObservedObject var bridge:BridgeClient
    @ObservedObject var hub:NearbyHub
    var close:()->Void
    var leave:()->Void
    init(agent:NearbyAgent,hub:NearbyHub,close:@escaping()->Void,leave:@escaping()->Void) {
        self.agent=agent;self.bridge=agent.client;self.hub=hub;self.close=close;self.leave=leave
    }
    var body:some View {
        NavigationStack {
            VStack(spacing:0) {
                HStack(spacing:12) {
                    AoraAnimatedAvatar(phase:agent.phase,active:bridge.snapshot.busy,shape:agent.avatarShape,hue:agent.avatarHue).frame(width:52,height:52)
                    VStack(alignment:.leading,spacing:5) {
                        Text(agent.name).font(.title2.bold()).lineLimit(1)
                        HStack(spacing:5){Circle().fill(bridge.connected ? .green:.gray).frame(width:7,height:7);Text(bridge.connected ? bridge.snapshot.title:"未连接").font(.caption).foregroundStyle(.secondary)}
                    }
                    Spacer()
                    Button(action:close){Image(systemName:"xmark").foregroundStyle(.secondary)}.accessibilityLabel("关闭侧栏")
                }.padding(22)
                List {
                    Button {Task{if await bridge.newChat(){close()}}} label:{Label("新对话",systemImage:"square.and.pencil").font(.title3)}
                        .disabled(bridge.connected || bridge.snapshot.busy || bridge.sending || bridge.switchingChat)
                    NavigationLink {KnowledgeView(hub:hub,defaultDevice:agent.id)} label:{Label("记忆与技能",systemImage:"heart").font(.title3)}
                    if let message=bridge.commandStatus,!message.hasPrefix("指令状态") {Text(message).font(.caption).foregroundStyle(.orange)}
                    if let error=bridge.conversationError {Text(error).font(.caption).foregroundStyle(.orange)}
                    Section("最近") {
                        ForEach(bridge.conversations) {chat in
                            SingleDeviceChatRow(bridge:bridge,chat:chat,close:close)
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                Divider()
                HStack {
                    NavigationLink {SyncSettings().toolbar(.visible,for:.navigationBar)} label:{Label("设置",systemImage:"gearshape")}
                    Spacer()
                    Button("设备",systemImage:"iphone.gen3",action:leave)
                }.padding(20)
            }.background(Color(uiColor:.systemBackground)).toolbar(.hidden,for:.navigationBar)
            .task {await bridge.refreshConversations()}
            .onChange(of:bridge.snapshot.chatRevision){_,_ in Task{await bridge.refreshConversations()}}
            .onChange(of:bridge.snapshot.currentConversationId){_,_ in Task{await bridge.refreshConversations()}}
        }
    }
}
private struct SingleDeviceChatRow:View {
    @ObservedObject var bridge:BridgeClient
    var chat:DeviceConversation
    var close:()->Void
    private var rowContent:some View {
        HStack {
            Text(chat.title).fontWeight(bridge.snapshot.currentConversationId==chat.id ? .semibold:.regular).lineLimit(2)
            Spacer()
            if chat.needsAttention {Image(systemName:"exclamationmark.circle").foregroundStyle(.orange)}
            if chat.updatedAt>0 {Text(Date(timeIntervalSince1970:chat.updatedAt),style:.time).font(.caption).foregroundStyle(.secondary)}
        }.padding(.vertical,8)
    }
    var body:some View {
        Button {Task{if await bridge.selectChat(chat.id){close()}}} label:{rowContent}
            .buttonStyle(.plain).disabled(bridge.switchingChat || bridge.sending)
            .modifier(ChatDeletionActions(bridge:bridge,chat:chat))
            .listRowBackground(bridge.snapshot.currentConversationId==chat.id ? Color.white.opacity(0.08):Color.clear)
    }
}
struct ChatDeletionActions:ViewModifier {
    @ObservedObject var bridge:BridgeClient
    var chat:DeviceConversation
    @State private var showDeleteConfirm=false
    @State private var showRename=false
    @State private var renameText=""
    func body(content:Content) -> some View {
        content.contextMenu{
            Button("重命名聊天"){renameText=chat.title;showRename=true}
            Button("删除聊天",role:.destructive){showDeleteConfirm=true}
        }
        .alert("删除聊天？",isPresented:$showDeleteConfirm){Button("删除",role:.destructive){Task{await bridge.deleteChat(chat.id)}};Button("取消",role:.cancel){}}message:{Text("删除“\(chat.title)”及安卓端对应记录、附件和关联定时任务。无法撤销。")}
        .alert("重命名聊天",isPresented:$showRename){TextField("聊天标题",text:$renameText);Button("取消",role:.cancel){};Button("保存"){Task{try? await bridge.renameChat(id:chat.id,title:renameText.trimmingCharacters(in:.whitespacesAndNewlines))}}}
    }
}
