import SwiftUI
import RecordUI
import GrabiDomain

/// Sign in / create account for Grabi Cloud. Shown the first time someone
/// taps "Share to Grabi Cloud" — and never before: the cloud is opt-in.
struct CloudSheet: View {
    @ObservedObject var store: CloudStore
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(spacing: GrabiSpace.s3) {
            MascotView(pose: .waving, size: 64)

            if let account = store.account {
                signedIn(account)
            } else {
                form
            }
        }
        .padding(GrabiSpace.s6)
        .frame(width: 340)
        .background(GrabiColor.bg)
    }

    private func signedIn(_ account: CloudAccount) -> some View {
        VStack(spacing: GrabiSpace.s3) {
            Text(L("app.cloud.signedInTitle"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GrabiColor.text)
            Text(account.email)
                .font(GrabiFont.body)
                .foregroundStyle(GrabiColor.textSecondary)
            GrabiButton(L("app.cloud.done"), kind: .primario) { dismiss() }
            Button(L("app.cloud.signOut")) {
                store.signOut()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(GrabiFont.caption)
            .foregroundStyle(GrabiColor.textSecondary)
        }
    }

    private var form: some View {
        VStack(spacing: GrabiSpace.s3) {
            Text(creating ? L("app.cloud.createTitle") : L("app.cloud.signInTitle"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(GrabiColor.text)
            Text(L("app.cloud.hint"))
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(GrabiFont.caption)
                    .foregroundStyle(messageIsError ? GrabiColor.error : GrabiColor.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(L("app.cloud.email"), text: $email)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            SecureField(L("app.cloud.password"), text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            GrabiButton(creating ? L("app.cloud.create") : L("app.cloud.signIn"),
                        kind: .primario, action: submit)
                .disabled(working || email.isEmpty || password.count < 8)

            Button(creating ? L("app.cloud.toggleHave") : L("app.cloud.toggleCreate")) {
                creating.toggle()
                message = nil
            }
            .buttonStyle(.plain)
            .font(GrabiFont.caption)
            .foregroundStyle(GrabiColor.brandStrong)

            Button(L("app.cancel")) { dismiss() }
                .buttonStyle(.plain)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.textSecondary)
        }
    }

    private func submit() {
        guard !working, !email.isEmpty, password.count >= 8 else { return }
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                if creating {
                    let signedIn = try await store.signUp(email: email, password: password)
                    if signedIn { dismiss() }
                    else {
                        messageIsError = false
                        message = L("app.cloud.checkEmail")
                    }
                } else {
                    try await store.signIn(email: email, password: password)
                    dismiss()
                }
            } catch let error as CloudError {
                messageIsError = true
                message = error.userMessage
            } catch {
                messageIsError = true
                message = L("app.cloud.failed")
            }
        }
    }
}
