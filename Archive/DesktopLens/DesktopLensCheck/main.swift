import Foundation
import Metal
let device = MTLCreateSystemDefaultDevice()!
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let library = try device.makeLibrary(source: source, options: nil)
let desc = MTLRenderPipelineDescriptor()
desc.vertexFunction = library.makeFunction(name: "lensVertex")
desc.fragmentFunction = library.makeFunction(name: "lensFragment")
desc.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: desc)
let inputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 344, height: 344, mipmapped: false)
inputDesc.storageMode = .managed; inputDesc.usage = .shaderRead
let input = device.makeTexture(descriptor: inputDesc)!
var inputBytes = [UInt8](repeating: 255, count: 344 * 344 * 4)
for y in 0..<344 { for x in 0..<344 {
 let i = (y * 344 + x) * 4
 inputBytes[i] = UInt8(y * 255 / 343); inputBytes[i+1] = 60; inputBytes[i+2] = UInt8(x * 255 / 343)
}}
input.replace(region: MTLRegionMake2D(0,0,344,344), mipmapLevel: 0, withBytes: inputBytes, bytesPerRow: 344*4)
let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 320, height: 320, mipmapped: false)
outputDesc.storageMode = .managed; outputDesc.usage = [.renderTarget, .shaderRead]
let output = device.makeTexture(descriptor: outputDesc)!
let pass = MTLRenderPassDescriptor()
pass.colorAttachments[0].texture = output
pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
let command = device.makeCommandQueue()!.makeCommandBuffer()!
let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
var u:[SIMD4<Float>] = [SIMD4(320,320,20,0), SIMD4(12/344.0,12/344.0,320/344.0,320/344.0),SIMD4(344,344,7,0),.zero]
encoder.setRenderPipelineState(pipeline); encoder.setFragmentTexture(input,index:0)
encoder.setFragmentBytes(&u,length:64,index:0)
encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);encoder.endEncoding()
let blit = command.makeBlitCommandEncoder()!; blit.synchronize(resource:output);blit.endEncoding()
command.commit();command.waitUntilCompleted()
guard command.status == .completed else { fatalError("GPU command failed: \(String(describing: command.error))") }
var bytes=[UInt8](repeating:0,count:320*320*4)
output.getBytes(&bytes,bytesPerRow:320*4,from:MTLRegionMake2D(0,0,320,320),mipmapLevel:0)
func pixel(_ x:Int,_ y:Int)->[UInt8] {Array(bytes[((y*320+x)*4)..<((y*320+x)*4+4)])}
func check(_ value:Bool,_ name:String) { guard value else {fatalError(name)};print("PASS: \(name)") }
check(pixel(0,0)[3]==0,"rounded corner is transparent")
check(pixel(160,160)[3]==255,"center is fully sampled")
check(pixel(80,160)[2]<pixel(240,160)[2],"desktop horizontal orientation preserved")
check(pixel(160,80)[0]<pixel(160,240)[0],"desktop vertical orientation preserved")
let expected=Double(inputBytes[(172*344+172)*4+2])*0.86+255*0.98*0.14
check(abs(Double(pixel(160,160)[2])-expected)<3,"center mapping matches source plus neutral veil")
check(pixel(2,160)[2] > pixel(12,160)[2],"curved edge has specular highlight")
print("Desktop lens: 6 GPU assertions passed on \(device.name)")
