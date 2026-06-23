import SwiftUI
import AVFoundation
import Observation

/// 全屏跟做模式 ViewModel
@MainActor
@Observable
final class CookingViewModel {
    let recipe: Recipe

    private(set) var currentStepIndex: Int = 0
    private(set) var isTimerRunning = false
    private(set) var elapsedSeconds: Int = 0
    private(set) var isVoiceEnabled = true
    private(set) var isCompleted = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var timerTask: Task<Void, Never>?

    var steps: [Step] {
        recipe.steps.sorted { $0.stepNumber < $1.stepNumber }
    }

    var currentStep: Step? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var totalSteps: Int { steps.count }

    init(recipe: Recipe) {
        self.recipe = recipe
    }

    // MARK: - 输入

    func goToNextStep() {
        guard currentStepIndex < steps.count - 1 else {
            complete()
            return
        }
        currentStepIndex += 1
        resetTimer()
        speakCurrentStep()
    }

    func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
        resetTimer()
    }

    func toggleTimer() {
        if isTimerRunning {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func toggleVoice() {
        isVoiceEnabled.toggle()
        if isVoiceEnabled {
            speakCurrentStep()
        } else {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    func complete() {
        isCompleted = true
        stopTimer()

        // 记录跟做完成
        Task {
            try? await AppContainer.shared.recipeRepo.incrementCookCount()
        }
    }

    // MARK: - 私有

    private func startTimer() {
        isTimerRunning = true
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        isTimerRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    private func resetTimer() {
        stopTimer()
        elapsedSeconds = 0
    }

    private func speakCurrentStep() {
        guard isVoiceEnabled, let step = currentStep else { return }
        let utterance = AVSpeechUtterance(string: step.descriptionText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85  // 稍慢，适合厨房环境
        speechSynthesizer.speak(utterance)
    }
}
