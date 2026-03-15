import Foundation

enum AppOpenAction {
    case openArchive(String)
    case compressFiles([URL])
    case extractArchive(String)
    case testArchive(String)
}

@MainActor
final class AppActionRouter: ObservableObject {
    static let shared = AppActionRouter()

    @Published private(set) var currentAction: AppOpenAction?

    private init() {}

    func dispatch(_ action: AppOpenAction) {
        currentAction = action
    }

    func consume() {
        currentAction = nil
    }
}
