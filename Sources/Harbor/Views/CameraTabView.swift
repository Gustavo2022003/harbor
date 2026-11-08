import SwiftUI
import AVFoundation

/// Aba "Espelho": o island desce como um retângulo vertical, com a câmera 1:1 embaixo do notch.
struct CameraTabView: View {
    @EnvironmentObject var camera: CameraManager
    @EnvironmentObject var vm: NotchViewModel

    private var radius: CGFloat { vm.bottomRadius(open: true) - 10 }

    var body: some View {
        VStack(spacing: 8) {
            preview
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: Câmera 1:1

    private var preview: some View {
        ZStack {
            Theme.card

            if camera.status == .authorized {
                CameraPreview(session: camera.session)
                    .scaleEffect(x: camera.mirrored ? -1 : 1, y: 1)
                    .opacity(camera.isRunning ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: camera.isRunning)
                if !camera.isRunning {
                    ProgressView().controlSize(.small)
                }
            } else if camera.status == .denied || camera.status == .restricted {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26)).foregroundStyle(Theme.secondary)
                    Text("Sem acesso à câmera")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Permita em Ajustes do Sistema › Privacidade › Câmera")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                    Button("Abrir Ajustes") { camera.openPrivacySettings() }
                        .buttonStyle(PillButtonStyle())
                }
                .padding(16)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 26)).foregroundStyle(Theme.secondary)
                    Text("Aguardando permissão")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(width: vm.cameraSide, height: vm.cameraSide)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if camera.isRunning {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                        .shadow(color: .green, radius: 3)
                    Text("AO VIVO").font(.system(size: 9.5, weight: .heavy))
                }
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(10)
                .transition(.opacity)
            }
        }
    }

    // MARK: Controles

    private var controls: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text(camera.currentDevice?.localizedName ?? "Câmera")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)

            if camera.devices.count > 1 {
                Menu {
                    ForEach(camera.devices, id: \.uniqueID) { d in
                        Button {
                            camera.select(d)
                        } label: {
                            if d.uniqueID == camera.currentDevice?.uniqueID {
                                Label(d.localizedName, systemImage: "checkmark")
                            } else {
                                Text(d.localizedName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .help("Trocar câmera")
            }

            CircleIconButton(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill",
                             tint: camera.mirrored ? Theme.orange : .white,
                             background: camera.mirrored ? Theme.orange.opacity(0.2) : Color.white.opacity(0.1),
                             size: 30) {
                withAnimation(.snappy) { camera.mirrored.toggle() }
            }
            .help(camera.mirrored ? "Espelhado" : "Normal")
        }
        .frame(width: vm.cameraSide, height: vm.cameraControlsHeight)
    }
}
