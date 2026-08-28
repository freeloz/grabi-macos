import SwiftUI
import RecordUI
import GrabiDomain

/// Sign in / create account for Grabi Cloud. Shown the first time someone
/// taps "Share to Grabi Cloud" — and never before: the cloud is opt-in.
struct CloudSheet: View {
    @ObservedObject var store: CloudStore
    @Environment(\.dismiss) private var dismiss

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
            Text(L("app.cloud.signInTitle"))
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

            // Todo el inicio de sesión ocurre en el navegador: ahí vive el
            // widget de captcha que Supabase exige, y la web devuelve la
            // sesión a la app por el esquema grabi://.
            Button {
                store.signInWithGoogle()
                messageIsError = false
                message = L("app.cloud.googleWaiting")
            } label: {
                Text(L("app.cloud.google"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            HStack(spacing: GrabiSpace.s3) {
                Rectangle().fill(GrabiColor.border).frame(height: 1)
                Text(L("app.cloud.or"))
                    .font(GrabiFont.caption)
                    .foregroundStyle(GrabiColor.textSecondary)
                Rectangle().fill(GrabiColor.border).frame(height: 1)
            }

            GrabiButton(L("app.cloud.emailWeb"), kind: .primario) {
                store.signInWithEmail()
                messageIsError = false
                message = L("app.cloud.googleWaiting")
            }

            Button(L("app.cancel")) { dismiss() }
                .buttonStyle(.plain)
                .font(GrabiFont.caption)
                .foregroundStyle(GrabiColor.textSecondary)
        }
    }

}
