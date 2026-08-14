//
//  VehicleGarage3DViewer.swift
//  Chercharge
//
//  GTA-style garage selection stage:
//  • Tesla (and inferred Tesla models) → photoreal compositor turntable, drag to orbit
//  • Other EVs → interactive SceneKit showroom mesh with saved paint
//

import SceneKit
import SwiftUI

// MARK: - Body style (SceneKit fallback)

enum VehicleGarageBodyStyle: Hashable {
    case sedan
    case crossover
    case coupe

    static func infer(from vehicle: Vehicle) -> VehicleGarageBodyStyle {
        switch vehicle.compositorModelCode {
        case "my", "mx": return .crossover
        case "ms": return .coupe
        case "m3": return .sedan
        default:
            let blob = "\(vehicle.make) \(vehicle.model)".lowercased()
            if blob.contains("y") || blob.contains("x") || blob.contains("suv") || blob.contains("crossover") {
                return .crossover
            }
            if blob.contains("s") && blob.contains("model") { return .coupe }
            return .sedan
        }
    }
}

// MARK: - Public stage

/// Full garage stage: cream studio, gold platform, drag-to-orbit vehicle.
struct VehicleGarage3DStage: View {
    let vehicle: Vehicle
    var height: CGFloat = 220
    var autoSpin: Bool = true
    var showsHint: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            showroomBackdrop

            // Gold showroom platform
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Brand.gold.opacity(0.55),
                            Brand.gold.opacity(0.18),
                            Brand.gold.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 140
                    )
                )
                .frame(width: min(320, height * 1.55), height: height * 0.42)
                .offset(y: height * 0.28)
                .blur(radius: 1)
                .allowsHitTesting(false)

            // Soft floor reflection wash
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.02),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: min(280, height * 1.35), height: height * 0.18)
                .offset(y: height * 0.22)
                .blur(radius: 6)
                .allowsHitTesting(false)

            Image("CherchargeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64)
                .opacity(0.08)
                .offset(y: -height * 0.28)
                .allowsHitTesting(false)

            Group {
                if vehicle.compositorModelCode != nil {
                    PhotorealGarageTurntable(vehicle: vehicle, autoSpin: autoSpin)
                } else {
                    VehicleGarage3DViewer(
                        paint: vehicle.paintColor,
                        bodyStyle: .infer(from: vehicle),
                        autoSpin: autoSpin
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, showsHint ? 26 : 12)

            if showsHint {
                Text("Drag to rotate · \(vehicle.homeCardTitle)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Brand.gold.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Brand.gold.opacity(0.6),
                            Brand.gold.opacity(0.2),
                            Brand.gold.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Brand.greenDeep.opacity(0.1), radius: 14, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vehicle.displayName), 3D garage viewer")
        .accessibilityHint("Drag horizontally to rotate the vehicle")
    }

    private var showroomBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.975, green: 0.965, blue: 0.945),
                    Color(red: 0.920, green: 0.900, blue: 0.860),
                    Color(red: 0.860, green: 0.835, blue: 0.780)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Upper cove light (GTA garage key light)
            RadialGradient(
                colors: [
                    Color.white.opacity(0.55),
                    Brand.gold.opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 4,
                endRadius: 160
            )

            // Soft emerald rim
            RadialGradient(
                colors: [
                    Brand.greenDeep.opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.92, y: 0.55),
                startRadius: 2,
                endRadius: 110
            )
        }
    }
}

// MARK: - Photoreal Tesla compositor turntable (interactive)

/// Drag-to-orbit photoreal garage using Tesla’s studio compositor for the saved model + paint.
private struct PhotorealGarageTurntable: View {
    let vehicle: Vehicle
    var autoSpin: Bool = true

    /// Full orbit frames (mirrored sides for a continuous GTA-style spin).
    private let frames: [(view: String, flip: Bool)] = [
        ("STUD_3QTR", false),
        ("STUD_SIDE", false),
        ("STUD_REAR", false),
        ("STUD_SIDE", true),
        ("STUD_3QTR", true)
    ]

    @State private var index: Double = 0
    @State private var dragStartIndex: Double = 0
    @State private var isDragging = false
    @State private var resumeSpinAt: Date = .distantPast
    @State private var loaded: [Int: Image] = [:]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: isDragging || !autoSpin)) { context in
            let displayIndex = resolvedIndex(at: context.date)
            let i = normalizedFrame(displayIndex)
            let frame = frames[i]

            ZStack {
                // Soft contact shadow under the car
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 200, height: 28)
                    .blur(radius: 10)
                    .offset(y: 58)
                    .allowsHitTesting(false)

                turntableImage(frame: frame, index: i)
                    .transition(.opacity)
                    .id(i)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            // Lock spin position into state so drag starts from what you see.
                            let visual = resolvedIndex(at: Date())
                            index = visual
                            dragStartIndex = visual
                        }
                        let delta = Double(value.translation.width) / 56.0
                        index = dragStartIndex - delta
                    }
                    .onEnded { value in
                        let velocity = Double(value.predictedEndTranslation.width - value.translation.width) / 56.0
                        index -= velocity * 0.35
                        index = index.rounded()
                        isDragging = false
                        resumeSpinAt = Date().addingTimeInterval(2.2)
                    }
            )
            .onAppear { prefetchAll() }
            .onChange(of: vehicle.id) { _, _ in
                loaded = [:]
                index = 0
                prefetchAll()
            }
            .onChange(of: vehicle.paintColor) { _, _ in
                loaded = [:]
                prefetchAll()
            }
        }
    }

    private func resolvedIndex(at date: Date) -> Double {
        if isDragging { return index }
        if autoSpin, date >= resumeSpinAt {
            let elapsed = date.timeIntervalSince(resumeSpinAt)
            return index + elapsed * 0.55
        }
        return index
    }

    private func normalizedFrame(_ value: Double) -> Int {
        let count = frames.count
        let i = Int(value.rounded())
        return ((i % count) + count) % count
    }

    @ViewBuilder
    private func turntableImage(frame: (view: String, flip: Bool), index: Int) -> some View {
        Group {
            if let image = loaded[index] {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: frame.flip ? -1 : 1, y: 1)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
            } else if let url = vehicle.teslaCompositorURL(view: frame.view, size: 700) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(x: frame.flip ? -1 : 1, y: 1)
                            .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
                            .onAppear { loaded[index] = image }
                    case .empty:
                        ProgressView()
                            .tint(Brand.gold)
                    case .failure:
                        proceduralFallback
                    @unknown default:
                        proceduralFallback
                    }
                }
            } else {
                proceduralFallback
            }
        }
        .animation(.easeOut(duration: 0.18), value: index)
    }

    private var proceduralFallback: some View {
        VehicleGarage3DViewer(
            paint: vehicle.paintColor,
            bodyStyle: .infer(from: vehicle),
            autoSpin: false
        )
    }

    private func prefetchAll() {
        for (offset, frame) in frames.enumerated() {
            guard loaded[offset] == nil,
                  let url = vehicle.teslaCompositorURL(view: frame.view, size: 700) else { continue }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let ui = UIImage(data: data) else { return }
                await MainActor.run {
                    loaded[offset] = Image(uiImage: ui)
                }
            }
        }
    }
}

// MARK: - SceneKit bridge (non-Tesla / offline fallback)

struct VehicleGarage3DViewer: UIViewRepresentable {
    let paint: TeslaPaint
    let bodyStyle: VehicleGarageBodyStyle
    var autoSpin: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.makeScene(paint: paint, bodyStyle: bodyStyle)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 60

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(VehicleGarage3DCoordinator.handlePan(_:))
        )
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        context.coordinator.attach(view: view, autoSpin: autoSpin)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.updateVehicle(paint: paint, bodyStyle: bodyStyle, autoSpin: autoSpin)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: VehicleGarage3DCoordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> VehicleGarage3DCoordinator {
        VehicleGarage3DCoordinator()
    }
}

@MainActor
final class VehicleGarage3DCoordinator: NSObject {
    private weak var scnView: SCNView?
    private var turntable: SCNNode?
    private var vehicleRoot: SCNNode?
    private var displayLink: CADisplayLink?
    private var yaw: Float = .pi * 0.28
    private var pitch: Float = -0.08
    private var angularVelocity: Float = 0.32
    private var userInteracting = false
    private var idleResumeAt: CFTimeInterval = 0
    private var autoSpinEnabled = true
    private var currentPaint: TeslaPaint = .pearlWhite
    private var currentBody: VehicleGarageBodyStyle = .sedan

    func attach(view: SCNView, autoSpin: Bool) {
        scnView = view
        autoSpinEnabled = autoSpin
        angularVelocity = autoSpin ? 0.32 : 0
        startDisplayLink()
        applyOrientation()
    }

    func teardown() {
        displayLink?.invalidate()
        displayLink = nil
        scnView = nil
    }

    func makeScene(paint: TeslaPaint, bodyStyle: VehicleGarageBodyStyle) -> SCNScene {
        currentPaint = paint
        currentBody = bodyStyle

        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.fogStartDistance = 7
        scene.fogEndDistance = 16
        scene.fogColor = UIColor(red: 0.90, green: 0.88, blue: 0.84, alpha: 1)
        scene.lightingEnvironment.contents = UIColor(red: 0.94, green: 0.92, blue: 0.88, alpha: 1)
        scene.lightingEnvironment.intensity = 1.15

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 36
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.wantsExposureAdaptation = true
        cameraNode.camera?.bloomIntensity = 0.15
        cameraNode.camera?.bloomThreshold = 0.85
        cameraNode.position = SCNVector3(0, 1.05, 3.85)
        cameraNode.look(at: SCNVector3(0, 0.38, 0))
        scene.rootNode.addChildNode(cameraNode)

        addLights(to: scene.rootNode)
        addShowroomFloor(to: scene.rootNode)

        let table = SCNNode()
        table.name = "turntable"
        scene.rootNode.addChildNode(table)
        turntable = table

        let vehicle = buildVehicle(paint: paint, bodyStyle: bodyStyle)
        vehicle.position = SCNVector3(0, 0.14, 0)
        table.addChildNode(vehicle)
        vehicleRoot = vehicle

        return scene
    }

    func updateVehicle(paint: TeslaPaint, bodyStyle: VehicleGarageBodyStyle, autoSpin: Bool) {
        autoSpinEnabled = autoSpin

        if paint != currentPaint, bodyStyle == currentBody, let root = vehicleRoot {
            currentPaint = paint
            applyPaint(paint, to: root)
            return
        }

        guard paint != currentPaint || bodyStyle != currentBody else { return }
        currentPaint = paint
        currentBody = bodyStyle

        vehicleRoot?.removeFromParentNode()
        let vehicle = buildVehicle(paint: paint, bodyStyle: bodyStyle)
        vehicle.position = SCNVector3(0, 0.14, 0)
        turntable?.addChildNode(vehicle)
        vehicleRoot = vehicle
    }

    private func applyPaint(_ paint: TeslaPaint, to root: SCNNode) {
        let bodyMat = paintBodyMaterial(paint)
        root.enumerateChildNodes { node, _ in
            guard let name = node.name, name.hasPrefix("paint") else { return }
            node.geometry?.firstMaterial = bodyMat
        }
    }

    // MARK: - Interaction

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = scnView else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            userInteracting = true
            angularVelocity = 0
        case .changed:
            yaw += Float(translation.x) * 0.014
            pitch = max(-0.35, min(0.18, pitch - Float(translation.y) * 0.006))
            gesture.setTranslation(.zero, in: view)
            applyOrientation()
        case .ended, .cancelled:
            userInteracting = false
            angularVelocity = Float(velocity.x) * 0.002
            idleResumeAt = CACurrentMediaTime() + 2.2
        default:
            break
        }
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !userInteracting else { return }

        if abs(angularVelocity) > 0.002 {
            yaw += angularVelocity * Float(link.duration)
            angularVelocity *= 0.96
            applyOrientation()
            return
        }

        angularVelocity = 0
        guard autoSpinEnabled, CACurrentMediaTime() >= idleResumeAt else { return }
        yaw += 0.42 * Float(link.duration)
        applyOrientation()
    }

    private func applyOrientation() {
        turntable?.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    // MARK: - Scene construction

    private func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        ambient.light?.color = UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)
        root.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1100
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowSampleCount = 8
        key.light?.shadowColor = UIColor.black.withAlphaComponent(0.32)
        key.light?.color = UIColor(white: 0.99, alpha: 1)
        key.eulerAngles = SCNVector3(-0.95, 0.48, 0)
        root.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 480
        fill.light?.color = UIColor(red: 0.92, green: 0.82, blue: 0.55, alpha: 1)
        fill.position = SCNVector3(-2.0, 2.6, 2.2)
        root.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 320
        rim.light?.color = UIColor(red: 0.14, green: 0.34, blue: 0.26, alpha: 1)
        rim.position = SCNVector3(2.6, 1.4, -1.8)
        root.addChildNode(rim)

        let spot = SCNNode()
        spot.light = SCNLight()
        spot.light?.type = .spot
        spot.light?.intensity = 650
        spot.light?.spotInnerAngle = 18
        spot.light?.spotOuterAngle = 48
        spot.light?.color = UIColor(white: 1, alpha: 1)
        spot.position = SCNVector3(0, 3.4, 1.2)
        spot.look(at: SCNVector3(0, 0.2, 0))
        root.addChildNode(spot)
    }

    private func addShowroomFloor(to root: SCNNode) {
        let disk = SCNCylinder(radius: 1.65, height: 0.04)
        disk.firstMaterial = mat(
            color: UIColor(red: 0.78, green: 0.74, blue: 0.66, alpha: 1),
            metal: 0.62,
            rough: 0.22
        )
        let platform = SCNNode(geometry: disk)
        platform.position = SCNVector3(0, 0, 0)
        root.addChildNode(platform)

        let ring = SCNTorus(ringRadius: 1.65, pipeRadius: 0.028)
        ring.firstMaterial = mat(
            color: UIColor(red: 0.82, green: 0.68, blue: 0.38, alpha: 1),
            metal: 0.92,
            rough: 0.16
        )
        let rim = SCNNode(geometry: ring)
        rim.position = SCNVector3(0, 0.025, 0)
        root.addChildNode(rim)

        let glow = SCNCylinder(radius: 1.25, height: 0.012)
        glow.firstMaterial = mat(
            color: UIColor(red: 1, green: 0.92, blue: 0.7, alpha: 0.4),
            metal: 0.1,
            rough: 0.75,
            emission: UIColor(red: 0.9, green: 0.75, blue: 0.35, alpha: 0.28)
        )
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, 0.045, 0)
        root.addChildNode(glowNode)
    }

    /// Premium EV silhouette with model-specific proportions (not a toy box stack).
    private func buildVehicle(paint: TeslaPaint, bodyStyle: VehicleGarageBodyStyle) -> SCNNode {
        let root = SCNNode()
        root.name = "premiumEV"

        let bodyMat = paintBodyMaterial(paint)
        let glassMat = mat(
            color: UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 0.72),
            metal: 0.08,
            rough: 0.03,
            transparent: true
        )
        let darkTrim = mat(color: UIColor(white: 0.07, alpha: 1), metal: 0.62, rough: 0.35)
        let tireMat = mat(color: UIColor(white: 0.05, alpha: 1), metal: 0.12, rough: 0.82)
        let aeroDisc = mat(color: UIColor(white: 0.16, alpha: 1), metal: 0.72, rough: 0.28)
        let chrome = mat(color: UIColor(white: 0.85, alpha: 1), metal: 0.95, rough: 0.12)
        let lightBar = mat(
            color: UIColor(white: 0.96, alpha: 1),
            metal: 0.2,
            rough: 0.1,
            emission: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.9)
        )
        let rearLight = mat(
            color: UIColor(red: 0.78, green: 0.1, blue: 0.12, alpha: 1),
            metal: 0.25,
            rough: 0.18,
            emission: UIColor(red: 0.75, green: 0.06, blue: 0.08, alpha: 0.8)
        )

        let dims = bodyDimensions(bodyStyle)
        let ride: Float = 0.22

        // Lower body — long chamfer reads as automotive sheet metal
        let lower = SCNBox(
            width: dims.length,
            height: dims.bodyHeight,
            length: dims.width,
            chamferRadius: min(dims.bodyHeight * 0.48, 0.18)
        )
        lower.firstMaterial = bodyMat
        let lowerNode = SCNNode(geometry: lower)
        lowerNode.name = "paintBody"
        lowerNode.position = SCNVector3(0, ride + Float(dims.bodyHeight / 2), 0)
        root.addChildNode(lowerNode)

        // Beltline shoulder
        let shoulder = SCNBox(
            width: dims.length * 0.94,
            height: dims.bodyHeight * 0.42,
            length: dims.width * 1.05,
            chamferRadius: 0.14
        )
        shoulder.firstMaterial = bodyMat
        let shoulderNode = SCNNode(geometry: shoulder)
        shoulderNode.name = "paintShoulder"
        shoulderNode.position = SCNVector3(0, ride + Float(dims.bodyHeight * 0.74), 0)
        root.addChildNode(shoulderNode)

        // Hood plane
        let hood = SCNBox(
            width: dims.length * 0.28,
            height: 0.06,
            length: dims.width * 0.9,
            chamferRadius: 0.03
        )
        hood.firstMaterial = bodyMat
        let hoodNode = SCNNode(geometry: hood)
        hoodNode.name = "paintHood"
        hoodNode.position = SCNVector3(
            Float(dims.length * 0.28),
            ride + Float(dims.bodyHeight * 0.92),
            0
        )
        hoodNode.eulerAngles.z = -0.06
        root.addChildNode(hoodNode)

        // Greenhouse / canopy
        let canopy = SCNBox(
            width: dims.cabinLength,
            height: dims.cabinHeight,
            length: dims.cabinWidth,
            chamferRadius: min(dims.cabinHeight * 0.5, 0.16)
        )
        canopy.firstMaterial = glassMat
        let canopyNode = SCNNode(geometry: canopy)
        canopyNode.position = SCNVector3(
            Float(dims.cabinOffsetX),
            ride + Float(dims.bodyHeight + dims.cabinHeight * 0.36),
            0
        )
        canopyNode.eulerAngles.z = bodyStyle == .coupe ? -0.1 : -0.05
        root.addChildNode(canopyNode)

        // Painted roof
        let roof = SCNBox(
            width: dims.cabinLength * 0.7,
            height: 0.045,
            length: dims.cabinWidth * 0.52,
            chamferRadius: 0.02
        )
        roof.firstMaterial = bodyMat
        let roofNode = SCNNode(geometry: roof)
        roofNode.name = "paintRoof"
        roofNode.position = SCNVector3(
            Float(dims.cabinOffsetX - 0.05),
            ride + Float(dims.bodyHeight + dims.cabinHeight * 0.8),
            0
        )
        root.addChildNode(roofNode)

        // Closed fascia
        let fascia = SCNBox(
            width: 0.09,
            height: dims.bodyHeight * 0.68,
            length: dims.width * 0.9,
            chamferRadius: 0.04
        )
        fascia.firstMaterial = darkTrim
        let fasciaNode = SCNNode(geometry: fascia)
        fasciaNode.position = SCNVector3(
            Float(dims.length * 0.49),
            ride + Float(dims.bodyHeight * 0.4),
            0
        )
        root.addChildNode(fasciaNode)

        // Front light bar
        let frontBar = SCNBox(width: 0.045, height: 0.038, length: dims.width * 0.8, chamferRadius: 0.012)
        frontBar.firstMaterial = lightBar
        let frontBarNode = SCNNode(geometry: frontBar)
        frontBarNode.position = SCNVector3(
            Float(dims.length * 0.512),
            ride + Float(dims.bodyHeight * 0.58),
            0
        )
        root.addChildNode(frontBarNode)

        // Rear light bar
        let rearBar = SCNBox(width: 0.045, height: 0.042, length: dims.width * 0.74, chamferRadius: 0.012)
        rearBar.firstMaterial = rearLight
        let rearBarNode = SCNNode(geometry: rearBar)
        rearBarNode.position = SCNVector3(
            Float(-dims.length * 0.512),
            ride + Float(dims.bodyHeight * 0.62),
            0
        )
        root.addChildNode(rearBarNode)

        // Side mirrors
        for side: Float in [-1, 1] {
            let mirror = SCNBox(width: 0.1, height: 0.05, length: 0.14, chamferRadius: 0.02)
            mirror.firstMaterial = bodyMat
            let mirrorNode = SCNNode(geometry: mirror)
            mirrorNode.name = "paintMirror"
            mirrorNode.position = SCNVector3(
                Float(dims.length * 0.18),
                ride + Float(dims.bodyHeight + 0.08),
                side * Float(dims.width * 0.58)
            )
            root.addChildNode(mirrorNode)
        }

        // Charge port
        let port = SCNBox(width: 0.11, height: 0.09, length: 0.028, chamferRadius: 0.015)
        port.firstMaterial = darkTrim
        let portNode = SCNNode(geometry: port)
        portNode.position = SCNVector3(
            Float(dims.length * 0.16),
            ride + Float(dims.bodyHeight * 0.55),
            Float(dims.width * 0.53)
        )
        root.addChildNode(portNode)

        // Aero wheels
        let wheelX: [CGFloat] = [dims.length * 0.32, -dims.length * 0.30]
        let wheelZ: [CGFloat] = [dims.width * 0.55, -dims.width * 0.55]
        let wheelRadius: CGFloat = bodyStyle == .crossover ? 0.26 : 0.235
        for x in wheelX {
            for z in wheelZ {
                let tire = SCNCylinder(radius: wheelRadius, height: 0.17)
                tire.firstMaterial = tireMat
                let tireNode = SCNNode(geometry: tire)
                tireNode.eulerAngles.x = .pi / 2
                tireNode.position = SCNVector3(Float(x), Float(wheelRadius), Float(z))
                root.addChildNode(tireNode)

                let disc = SCNCylinder(radius: wheelRadius * 0.78, height: 0.175)
                disc.firstMaterial = aeroDisc
                let discNode = SCNNode(geometry: disc)
                discNode.eulerAngles.x = .pi / 2
                discNode.position = SCNVector3(Float(x), Float(wheelRadius), Float(z))
                root.addChildNode(discNode)

                let hub = SCNCylinder(radius: wheelRadius * 0.16, height: 0.18)
                hub.firstMaterial = chrome
                let hubNode = SCNNode(geometry: hub)
                hubNode.eulerAngles.x = .pi / 2
                hubNode.position = SCNVector3(Float(x), Float(wheelRadius), Float(z))
                root.addChildNode(hubNode)
            }
        }

        // Contact shadow
        let shadow = SCNCylinder(radius: dims.length * 0.42, height: 0.01)
        shadow.firstMaterial = mat(
            color: UIColor.black.withAlphaComponent(0.22),
            metal: 0,
            rough: 1
        )
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.position = SCNVector3(0, 0.008, 0)
        root.addChildNode(shadowNode)

        if bodyStyle == .crossover {
            let rail = SCNBox(width: dims.cabinLength * 0.68, height: 0.028, length: 0.032, chamferRadius: 0.01)
            rail.firstMaterial = darkTrim
            let railR = SCNNode(geometry: rail)
            railR.position = SCNVector3(
                Float(dims.cabinOffsetX),
                ride + Float(dims.bodyHeight + dims.cabinHeight * 0.92),
                Float(dims.cabinWidth * 0.3)
            )
            root.addChildNode(railR)
            let railL = railR.clone()
            railL.position.z = Float(-dims.cabinWidth * 0.3)
            root.addChildNode(railL)
        }

        return root
    }

    private struct BodyDims {
        let length: CGFloat
        let width: CGFloat
        let bodyHeight: CGFloat
        let cabinLength: CGFloat
        let cabinWidth: CGFloat
        let cabinHeight: CGFloat
        let cabinOffsetX: CGFloat
    }

    private func bodyDimensions(_ style: VehicleGarageBodyStyle) -> BodyDims {
        switch style {
        case .sedan:
            return BodyDims(
                length: 2.52, width: 1.1, bodyHeight: 0.42,
                cabinLength: 1.32, cabinWidth: 0.98, cabinHeight: 0.38, cabinOffsetX: -0.05
            )
        case .crossover:
            return BodyDims(
                length: 2.42, width: 1.16, bodyHeight: 0.5,
                cabinLength: 1.38, cabinWidth: 1.04, cabinHeight: 0.46, cabinOffsetX: -0.03
            )
        case .coupe:
            return BodyDims(
                length: 2.58, width: 1.12, bodyHeight: 0.4,
                cabinLength: 1.2, cabinWidth: 1.0, cabinHeight: 0.34, cabinOffsetX: -0.1
            )
        }
    }

    private func paintBodyMaterial(_ paint: TeslaPaint) -> SCNMaterial {
        let color = paint.uiColor
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.name = "vehiclePaint"
        m.diffuse.contents = color
        m.metalness.contents = paint.garageMetalness
        m.roughness.contents = paint.garageRoughness
        m.specular.contents = UIColor.white.withAlphaComponent(0.35)
        if paint == .pearlWhite || paint == .silver {
            m.emission.contents = color.withAlphaComponent(0.035)
        }
        m.fillMode = .fill
        return m
    }

    private func mat(
        color: UIColor,
        metal: CGFloat,
        rough: CGFloat,
        emission: UIColor? = nil,
        transparent: Bool = false
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let emission {
            m.emission.contents = emission
        }
        if transparent {
            m.transparency = 0.62
            m.isDoubleSided = true
        }
        m.fillMode = .fill
        return m
    }
}

// MARK: - Vehicle compositor helpers

extension Vehicle {
    /// Model code for Tesla studio renders (`m3`, `my`, `ms`, `mx`), including light inference.
    var compositorModelCode: String? {
        if let code = teslaModelCode { return code }
        let blob = "\(make) \(model) \(name)".lowercased()
        if blob.contains("model 3") || blob.contains("model3") { return "m3" }
        if blob.contains("model y") || blob.contains("modely") { return "my" }
        if blob.contains("model s") || blob.contains("models") { return "ms" }
        if blob.contains("model x") || blob.contains("modelx") { return "mx" }
        // Default premium EV garage hero when make is Tesla without a parsed model.
        if make.lowercased() == "tesla" { return "m3" }
        return nil
    }

    func teslaCompositorURL(view: String, size: Int = 1200) -> URL? {
        guard let model = compositorModelCode else { return nil }
        let paint = paintColor.compositorCode
        let string =
            "https://static-assets.tesla.com/v1/compositor/?model=\(model)&view=\(view)&size=\(size)&bkba_opt=1&options=\(paint),$W39B"
        return URL(string: string)
    }
}

// MARK: - Paint bridge

extension TeslaPaint {
    var uiColor: UIColor {
        switch self {
        case .pearlWhite:
            return UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1)
        case .solidBlack:
            return UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        case .deepBlue:
            return UIColor(red: 0.10, green: 0.22, blue: 0.45, alpha: 1)
        case .midnightSilver:
            return UIColor(red: 0.38, green: 0.40, blue: 0.43, alpha: 1)
        case .red:
            return UIColor(red: 0.68, green: 0.09, blue: 0.12, alpha: 1)
        case .silver:
            return UIColor(red: 0.74, green: 0.75, blue: 0.76, alpha: 1)
        }
    }

    fileprivate var garageMetalness: CGFloat {
        switch self {
        case .pearlWhite, .silver, .midnightSilver: return 0.8
        case .solidBlack: return 0.9
        case .deepBlue, .red: return 0.74
        }
    }

    fileprivate var garageRoughness: CGFloat {
        switch self {
        case .pearlWhite: return 0.16
        case .solidBlack: return 0.14
        case .deepBlue, .red: return 0.2
        case .midnightSilver, .silver: return 0.26
        }
    }
}
