import Live2DMetalObjC
import AVFoundation
import CubismNativeFramework
import Metal
import UIKit

protocol Live2DManagerDelegate: AnyObject {
    func modelDidLoad()
}

final class Live2DManager {
    private var viewMatrix = Csm.CubismMatrix44()
    private var model = Live2DModel()
    private var renderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.depthAttachment.clearDepth = 1.0
        return descriptor
    }()
    private let resourcesPath: String
    private let modelName: String
    weak var delegate: (any Live2DManagerDelegate)?
    var isTalking = false

    init(resourcesPath: String, modelName: String) {
        self.resourcesPath = resourcesPath
        self.modelName = modelName
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.loadScene()
        }
    }

    func onDrag(x: Csm.csmFloat32, y: Csm.csmFloat32) {
        model.setDragging(x: x, y: y)
    }

    func onTap(x: Csm.csmFloat32, y: Csm.csmFloat32) {
        if LAppDefine.DebugLogEnable {
            print("[APP]tap point: {x:\(x) y:\(y)}")
        }

        if model.hitTest(LAppDefine.HitAreaNameHead, x: x, y: y) {
            if LAppDefine.DebugLogEnable {
                print("[APP]hit area: [\(LAppDefine.HitAreaNameHead)]")
            }
            model.setRandomExpression()
        } else if model.hitTest(LAppDefine.HitAreaNameBody, x: x, y: y) {
            if LAppDefine.DebugLogEnable {
                print("[APP]hit area: [\(LAppDefine.HitAreaNameBody)]")
            }
            model.startRandomMotion(LAppDefine.MotionGroupTapBody, priority: LAppDefine.PriorityNormal)
        }
    }

    func onUpdate(
        commandBuffer: MTLCommandBuffer,
        currentDrawable: CAMetalDrawable,
        depthTexture: MTLTexture?,
        frame: CGRect
    ) {
        let width = frame.size.width
        let height = frame.size.height

        var projection = Csm.CubismMatrix44()

        guard let device = renderingManager?.getMTLDevice() else {
            print("Failed to get model or device.")
            return
        }

        renderPassDescriptor.colorAttachments[0].texture = currentDrawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        renderPassDescriptor.depthAttachment.texture = depthTexture

        CubismNativeProxy.startFrameInMetalRenderer(
            with: device,
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor
        )

        guard model.isModelAvailable() else {
            print("Failed to model->GetModel().")
            return
        }

        if model.getCanvasWidth() ?? 0 > 1.0 && width < height {
            model.model.pointee.GetModelMatrix()?.pointee.SetWidth(2.0)
            projection.Scale(1.0, Float(width) / Float(height))
        } else {
            projection.Scale(Float(height) / Float(width), 1.0)
        }

        if viewMatrix != nil {
            projection.MultiplyByMatrix(&viewMatrix)
        }

        let value = (model.userTimeSeconds - floor(model.userTimeSeconds)) * 4
        let lipSyncValue = if value < 1 {
            value
        } else if value < 2 {
            2 - value
        } else if value < 3 {
            value - 2
        } else {
            (4 - value) * 0.7
        }
        model.update(isTalking ? lipSyncValue : 0)
        model.draw(with: &projection)
    }

    func loadScene() {
        // Construct the path to model3.json
        let modelPath = "\(resourcesPath)\(modelName)/"
        let modelJsonName = "\(modelName).model3.json"

        model.loadAssets(withDirectory: modelPath, fileName: modelJsonName)

        delegate?.modelDidLoad()
    }

    func setViewMatrix(_ m: UnsafeMutablePointer<Csm.CubismViewMatrix>) {
        if let array = viewMatrix.GetArray(), let mArray = m.pointee.GetArray() {
            for i in 0..<16 {
                array[i] = mArray[i]
            }
        }
    }

    private var renderingManager: CubismRenderingInstanceSingleton_Metal? {
        CubismRenderingInstanceSingleton_Metal.sharedManager() as? CubismRenderingInstanceSingleton_Metal
    }
}
