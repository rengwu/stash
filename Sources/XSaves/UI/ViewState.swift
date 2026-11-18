import SwiftUI

/// Stands in for @State, which the macOS 27 SDK implements as a macro the Command Line Tools cannot expand.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>
    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}
