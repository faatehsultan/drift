import SwiftUI

struct AgentApprovalView: View {
    @ObservedObject var agent: AgentModel

    var body: some View {
        if let r = agent.pending.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.2))
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claude Code wants to use \(r.tool)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(r.project.isEmpty ? "Permission request" : r.project)
                            .font(.system(size: 11))
                            .foregroundColor(.dim)
                    }
                    Spacer(minLength: 0)
                    if agent.pending.count > 1 {
                        Text("1 of \(agent.pending.count)").font(.system(size: 11)).foregroundColor(.dim)
                    }
                }
                ScrollView {
                    Text(r.detail.isEmpty ? "No details" : r.detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 72)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
                HStack(spacing: 8) {
                    Button("Ask in terminal") { agent.resolve(r.id, .ask) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.dim)
                    Spacer()
                    OutlineButton(title: "Deny") { agent.resolve(r.id, .deny) }
                    PillButton(title: "Allow", icon: "checkmark") { agent.resolve(r.id, .allow) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .id(r.id)
        }
    }
}
