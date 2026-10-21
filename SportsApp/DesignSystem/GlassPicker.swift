import SwiftUI

/// A Liquid Glass segmented control: a glass capsule with a lighter pill that slides to the selection,
/// in place of the system's blue segmented picker.
struct GlassPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    @Namespace private var namespace

    init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { selection = option.value }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(.white.opacity(0.22))
                                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                                        .matchedGeometryEffect(id: "selection", in: namespace)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(3)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .fixedSize()
    }
}

extension GlassPicker where Value: CaseIterable & RawRepresentable, Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    /// For string-backed enums: one segment per case, titled by its raw value.
    init(selection: Binding<Value>) {
        self.init(selection: selection, options: Value.allCases.map { ($0, $0.rawValue) })
    }
}
