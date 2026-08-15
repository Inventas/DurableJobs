import SwiftUI

struct DashboardOperationConfirmationModifier: ViewModifier {
    @ObservedObject var store: DurableQueueDashboardStore
    @Binding var operation: DashboardOperation?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            operation?.title ?? "Confirm Operation",
            isPresented: Binding(
                get: { operation != nil },
                set: { isPresented in
                    if !isPresented {
                        operation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let operation {
                if operation.isDestructive {
                    Button(operation.confirmationLabel, role: .destructive) {
                        perform(operation)
                    }
                } else {
                    Button(operation.confirmationLabel) {
                        perform(operation)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                operation = nil
            }
        } message: {
            if let operation {
                Text(operation.message)
            }
        }
    }

    private func perform(_ requestedOperation: DashboardOperation) {
        operation = nil
        Task {
            await store.perform(requestedOperation)
        }
    }
}

extension View {
    func confirmsDashboardOperation(
        _ operation: Binding<DashboardOperation?>,
        store: DurableQueueDashboardStore
    ) -> some View {
        modifier(
            DashboardOperationConfirmationModifier(
                store: store,
                operation: operation
            )
        )
    }
}
