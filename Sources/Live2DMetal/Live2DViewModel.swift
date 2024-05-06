import SwiftUI

public final class Live2DViewModel: ObservableObject {
    @Published public var isAwake: Bool
    @Published public var isTalking: Bool

    public init(isAwake: Bool, isTalking: Bool) {
        self.isAwake = isAwake
        self.isTalking = isTalking
    }
}
