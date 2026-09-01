import Foundation

@main
struct DigestExplainQualityCheck {
    static func main() {
        precondition(DigestExplainQuality.verdict(selected: "这个系统", explanation: "") == .empty)
        precondition(DigestExplainQuality.verdict(selected: "这个系统", explanation: "   ") == .empty)
        precondition(DigestExplainQuality.verdict(selected: "这个系统", explanation: "嗯。") == .tooShort)
        precondition(DigestExplainQuality.verdict(selected: "这个系统", explanation: "作者在") == .tooShort)
        precondition(
            DigestExplainQuality.verdict(
                selected: "这个系统",
                explanation: "作者在视频中展示的"
            ) == .unrelated,
            "不含选中词的残句不得算成功"
        )
        precondition(
            DigestExplainQuality.verdict(
                selected: "这个系统",
                explanation: "这套系统把日常事务拆成可执行的步骤。"
            ) == .ok
        )
        precondition(
            DigestExplainQuality.verdict(
                selected: "transformer",
                explanation: "Transformer 是一种注意力架构。"
            ) == .ok
        )
        precondition(DigestExplainQuality.retryPrompt == "这句没答好")
        precondition(DigestExplainQuality.retryButtonTitle == "再试一次")
        print("digest_explain_quality_check=passed")
    }
}
