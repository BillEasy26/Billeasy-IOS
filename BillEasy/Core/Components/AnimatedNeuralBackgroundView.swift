//
//  AnimatedNeuralBackgroundView.swift
//  BillEasy
//

import UIKit

final class AnimatedNeuralBackgroundView: UIView {
    struct Palette {
        let gradientColors: [UIColor]
        let dotColor: UIColor
        let lineColor: UIColor
        let lineWidth: CGFloat
        let nodeRadius: CGFloat
        let densityAreaDivisor: CGFloat
        let velocityScale: CGFloat

        static let authDark = Palette(
            gradientColors: [
                UIColor(hex: "#091A2D"),
                UIColor(hex: "#070F1B")
            ],
            dotColor: UIColor(fixedHex: "#38BDF8", alpha: 0.34),
            lineColor: UIColor(fixedHex: "#38BDF8", alpha: 0.18),
            lineWidth: 0.8,
            nodeRadius: 1.8,
            densityAreaDivisor: 10_000,
            velocityScale: 0.32
        )

        static let landingLight = Palette(
            gradientColors: [
                UIColor(fixedHex: "#FFFFFF"),
                UIColor(fixedHex: "#F8FAFC")
            ],
            dotColor: UIColor(fixedHex: "#10317F", alpha: 0.42),
            lineColor: UIColor(fixedHex: "#10317F", alpha: 0.18),
            lineWidth: 0.8,
            nodeRadius: 1.65,
            densityAreaDivisor: 10_000,
            velocityScale: 0.28
        )

        static let landingDark = Palette(
            gradientColors: [
                UIColor(fixedHex: "#081220"),
                UIColor(fixedHex: "#070F1B")
            ],
            dotColor: UIColor(fixedHex: "#38BDF8", alpha: 0.34),
            lineColor: UIColor(fixedHex: "#38BDF8", alpha: 0.18),
            lineWidth: 0.8,
            nodeRadius: 1.65,
            densityAreaDivisor: 10_000,
            velocityScale: 0.28
        )
    }

    private struct Particle {
        var position: CGPoint
        var velocity: CGVector
    }

    private let gradientLayer = CAGradientLayer()
    private let lineLayer = CAShapeLayer()
    private let nodeLayer = CAShapeLayer()

    private var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastBoundsSize: CGSize = .zero
    private var palette: Palette

    init(palette: Palette) {
        self.palette = palette
        super.init(frame: .zero)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopAnimating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds

        guard bounds.width > 0, bounds.height > 0 else { return }
        if lastBoundsSize != bounds.size {
            lastBoundsSize = bounds.size
            rebuildParticles()
            renderCurrentFrame()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopAnimating() : startAnimating()
    }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        applyPaletteToLayers()
        renderCurrentFrame()
    }

    func refreshLayout() {
        setNeedsLayout()
        layoutIfNeeded()
        renderCurrentFrame()
    }
}

private extension AnimatedNeuralBackgroundView {
    func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)

        lineLayer.fillColor = UIColor.clear.cgColor
        lineLayer.actions = ["path": NSNull(), "opacity": NSNull()]
        layer.addSublayer(lineLayer)

        nodeLayer.strokeColor = UIColor.clear.cgColor
        nodeLayer.actions = ["path": NSNull(), "opacity": NSNull()]
        layer.addSublayer(nodeLayer)

        applyPaletteToLayers()
    }

    func applyPaletteToLayers() {
        gradientLayer.colors = palette.gradientColors.map(\.cgColor)
        lineLayer.strokeColor = palette.lineColor.cgColor
        lineLayer.lineWidth = palette.lineWidth
        nodeLayer.fillColor = palette.dotColor.cgColor
    }

    func rebuildParticles() {
        let area = max(bounds.width * bounds.height, 1)
        let count = max(14, Int(area / palette.densityAreaDivisor))
        particles = (0..<count).map { _ in
            let x = CGFloat.random(in: 0...bounds.width)
            let y = CGFloat.random(in: 0...bounds.height)
            let vx = CGFloat.random(in: -palette.velocityScale...palette.velocityScale)
            let vy = CGFloat.random(in: -palette.velocityScale...palette.velocityScale)
            return Particle(position: CGPoint(x: x, y: y), velocity: CGVector(dx: vx, dy: vy))
        }
    }

    func startAnimating() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLink))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        } else {
            displayLink.preferredFramesPerSecond = 30
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    @objc func handleDisplayLink(_ link: CADisplayLink) {
        guard bounds.width > 0, bounds.height > 0, !particles.isEmpty else { return }

        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            renderCurrentFrame()
            return
        }

        let delta = min(max(link.timestamp - lastTimestamp, 0.0), 1.0 / 20.0)
        lastTimestamp = link.timestamp

        let velocityMultiplier = CGFloat(delta * 60)
        for index in particles.indices {
            var particle = particles[index]
            particle.position.x += particle.velocity.dx * velocityMultiplier
            particle.position.y += particle.velocity.dy * velocityMultiplier

            if particle.position.x < 0 || particle.position.x > bounds.width {
                particle.velocity.dx *= -1
                particle.position.x = min(max(particle.position.x, 0), bounds.width)
            }
            if particle.position.y < 0 || particle.position.y > bounds.height {
                particle.velocity.dy *= -1
                particle.position.y = min(max(particle.position.y, 0), bounds.height)
            }

            particles[index] = particle
        }

        renderCurrentFrame()
    }

    func renderCurrentFrame() {
        guard !particles.isEmpty else { return }

        let linePath = UIBezierPath()
        let nodePath = UIBezierPath()
        let maxDistance: CGFloat = bounds.width > 500 ? 150 : 120

        for particle in particles {
            nodePath.append(
                UIBezierPath(
                    arcCenter: particle.position,
                    radius: palette.nodeRadius,
                    startAngle: 0,
                    endAngle: 2 * .pi,
                    clockwise: true
                )
            )
        }

        if particles.count > 1 {
            for firstIndex in 0..<(particles.count - 1) {
                for secondIndex in (firstIndex + 1)..<particles.count {
                    let first = particles[firstIndex].position
                    let second = particles[secondIndex].position
                    let distance = hypot(first.x - second.x, first.y - second.y)
                    if distance < maxDistance {
                        linePath.move(to: first)
                        linePath.addLine(to: second)
                    }
                }
            }
        }

        lineLayer.path = linePath.cgPath
        nodeLayer.path = nodePath.cgPath
    }
}
