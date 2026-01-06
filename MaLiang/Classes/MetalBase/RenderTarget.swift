//
//  RenderTarget.swift
//  MaLiang
//
//  Created by Harley-xk on 2019/4/15.
//

import UIKit
import Foundation
import Metal
import simd

/// a target for any thing that can be render on
open class RenderTarget {
    
    /// texture to render on
    public private(set) var texture: MTLTexture?
    
    /// the scale level of view, all things scales
    open var scale: CGFloat = 1 {
        didSet {
            updateTransformBuffer()
        }
    }
    
    /// the zoom level of render target, only scale render target
    open var zoom: CGFloat = 1

    /// the offset of render target with zoomed size
    open var contentOffset: CGPoint = .zero {
        didSet {
            updateTransformBuffer()
        }
    }
    
    /// create with texture and device
    /// - Note: Ensures the initial texture is properly cleared and the render pass
    ///   descriptor is correctly configured to prevent artifacts on first display.
    public init(size: CGSize, pixelFormat: MTLPixelFormat, device: MTLDevice?) {
        
        self.drawableSize = size
        self.pixelFormat = pixelFormat
        self.device = device
        // Create an empty texture (properly initialized with zeros)
        self.texture = makeEmptyTexture()
        self.commandQueue = device?.makeCommandQueue()
        
        renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor?.colorAttachments[0]
        attachment?.texture = texture
        
        // Fix: Set loadAction to .clear for initial setup to ensure clean state
        // This prevents artifacts (horizontal lines) on first display.
        // After initial setup, it can be changed to .load for subsequent renders.
        attachment?.loadAction = .clear
        attachment?.storeAction = .store
        
        updateBuffer(with: size)
    }
    
    /// clear the contents of texture
    /// - Note: Previously, clearing only created a new texture but didn't ensure
    ///   the old command buffer was properly committed. This could cause
    ///   rendering artifacts when clear() was called multiple times.
    ///   Now ensures all pending commands are committed before creating new texture.
    open func clear() {
        // Fix: Commit any pending commands before clearing to ensure
        // all previous rendering operations are completed and don't interfere
        // with the new empty texture. This prevents artifacts when clear()
        // is called multiple times.
        if commandBuffer != nil {
            commitCommands()
        }
        
        // Create a new empty texture (which will be properly initialized with zeros)
        texture = makeEmptyTexture()
        
        // Update the render pass descriptor to use the new texture
        renderPassDescriptor?.colorAttachments[0].texture = texture
        // Set loadAction to .clear to ensure the texture is cleared on next render
        renderPassDescriptor?.colorAttachments[0].loadAction = .clear
        
        // Commit the clear operation
        commitCommands()
    }
    
    internal var pixelFormat: MTLPixelFormat = .bgra8Unorm
    internal var drawableSize: CGSize
    internal var uniform_buffer: MTLBuffer!
    internal var transform_buffer: MTLBuffer!
    internal var renderPassDescriptor: MTLRenderPassDescriptor?
    internal var commandBuffer: MTLCommandBuffer?
    internal var commandQueue: MTLCommandQueue?
    internal var device: MTLDevice?
    
    internal func updateBuffer(with size: CGSize) {
        self.drawableSize = size
        let metrix = Matrix.identity
        let zoomUniform = 2 * Float(zoom / scale )
        metrix.scaling(x: zoomUniform  / Float(size.width), y: -zoomUniform / Float(size.height), z: 1)
        metrix.translation(x: -1, y: 1, z: 0)
        uniform_buffer = device?.makeBuffer(bytes: metrix.m, length: MemoryLayout<Float>.size * 16, options: [])
        
        updateTransformBuffer()
    }
    
    internal func updateTransformBuffer() {
        let scaleFactor = UIScreen.main.nativeScale
        var transform = ScrollingTransform(offset: contentOffset * scaleFactor, scale: scale)
        transform_buffer = device?.makeBuffer(bytes: &transform, length: MemoryLayout<ScrollingTransform>.stride, options: [])
    }
    
    internal func prepareForDraw() {
        if commandBuffer == nil {
            commandBuffer = commandQueue?.makeCommandBuffer()
        }
    }

    internal func makeCommandEncoder() -> MTLRenderCommandEncoder? {
        guard let commandBuffer = commandBuffer, let rpd = renderPassDescriptor else {
            return nil
        }
        return commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
    }
    
    internal func commitCommands() {
        commandBuffer?.commit()
        commandBuffer = nil
    }
    
    // make empty texture
    /// Creates a new empty texture and ensures it's properly initialized
    /// - Note: The texture is cleared with zeros (transparent black) to prevent
    ///   any uninitialized memory artifacts (like horizontal lines) on first display.
    internal func makeEmptyTexture() -> MTLTexture? {
        guard drawableSize.width * drawableSize.height > 0 else {
            return nil
        }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                         width: Int(drawableSize.width),
                                                                         height: Int(drawableSize.height),
                                                                         mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        let texture = device?.makeTexture(descriptor: textureDescriptor)
        
        // Fix: Ensure the new texture is properly cleared with zeros
        // This prevents uninitialized memory artifacts (horizontal lines) on first display
        texture?.clear()
        
        return texture
    }
    
}
