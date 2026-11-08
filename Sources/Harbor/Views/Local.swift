import SwiftUI

/// Substituto de `@State` (no SDK do macOS 27 `@State` é uma macro que exige o Xcode completo).
@propertyWrapper
struct Local<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ v: Value) { value = v }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let b = box
        return Binding(get: { b.value }, set: { b.value = $0 })
    }
}
